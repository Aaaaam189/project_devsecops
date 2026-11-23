#!/usr/bin/env bash
#
# k3d version of attack-credentials.sh. Same four attacks, but the probes
# run as throwaway pods inside the cluster (namespace $NS) instead of
# containers on the Docker Compose network, and use the in-cluster service
# names (rabbitmq, postgres, mongodb).
#
# Attack 4a: RabbitMQ management API with guest/guest.
# Attack 4b: RabbitMQ AMQP with guest/guest (real connection + queue declare).
# Attack 4c: RabbitMQ management port reachable at all (no credentials).
#            Step 7 closes this port, so it flips from SUCCEEDED to BLOCKED.
# Attack 5:  Postgres with a short list of weak passwords, as the
#            superuser and as the application user.
# Attack 6:  MongoDB with no credentials, reading real chat data.
#
# Convention: one line per attempt, SUCCEEDED or BLOCKED. Exit 1 if any
# SUCCEEDED.

set -u

NS="${NS:-foundersync}"
# Probes run WITHOUT an Istio sidecar by default: an attacker pod with no
# mesh identity. (A probe with a sidecar makes `kubectl run -i` time out.)
PROBE_OPTS="${PROBE_OPTS---annotations=sidecar.istio.io/inject=false}"
RESULT=0

ok_blocked()    { printf '[ATTACK] %s -> BLOCKED\n' "$1"; }
bad_succeeded() { printf '[ATTACK] %s -> SUCCEEDED\n' "$1"; RESULT=1; }

# The 6s sleep lets the network-policy rules for the new pod IP sync first;
# a brand-new pod is briefly refused, which would look like a block.
# probe <image> <shell command>: run the command in a throwaway pod and
# print its stdout. The pod is removed when it exits. The pod first prints
# a sentinel; if the sentinel never arrives the probe did not run, and the
# output is __PROBE_FAILED__. An empty result must never be read as BLOCKED.
probe() {
    local out attempt body
    for attempt in 1 2 3; do
        # shellcheck disable=SC2086
        out=$(kubectl run "atk-$RANDOM$RANDOM" --image="$1" --image-pull-policy=IfNotPresent \
            --restart=Never --rm -i --quiet -n "$NS" $PROBE_OPTS \
            --command -- sh -c "echo __PROBE_OK__; sleep 6; $2" 2>/dev/null)
        body=$(printf '%s\n' "$out" | grep -v '__PROBE_OK__' | sed '/^[[:space:]]*$/d')
        # Sentinel seen AND some result printed: the probe really ran.
        if printf '%s\n' "$out" | grep -q '__PROBE_OK__' && [ -n "$body" ]; then
            printf '%s\n' "$body"
            return
        fi
    done
    echo "__PROBE_FAILED__"
}
# probe_ok <value>: stop the whole script if the probe did not run.
probe_ok() {
    if [ "$1" = "__PROBE_FAILED__" ]; then
        echo "SETUP FAILED: the probe pod did not run (image pull, scheduling or attach problem). Result would be meaningless."
        exit 2
    fi
}

# ──────────────────────────────────────────
# Attack 4a: RabbitMQ management API, guest/guest
# ──────────────────────────────────────────
status=$(probe curlimages/curl 'curl -s -o /dev/null -w "%{http_code}" -m 5 -u guest:guest http://rabbitmq:15672/api/overview' | tail -n1)
probe_ok "$status"
if [ "$status" = "200" ]; then
    bad_succeeded "rabbitmq-management-guest-guest (status $status)"
else
    ok_blocked "rabbitmq-management-guest-guest (status $status)"
fi

# ──────────────────────────────────────────
# Attack 4b: RabbitMQ AMQP over TLS (5671), guest/guest. Plain 5672 is closed.
# A small stdlib Python AMQP login is passed base64-encoded (no shell quoting).
# ──────────────────────────────────────────
PY_PROBE=$(cat <<'PY'
# Stdlib-only AMQP 0-9-1 login over TLS (no pip: under default-deny a pod in
# the namespace cannot reach the internet). Sends Connection.Start-Ok with
# PLAIN credentials and reports whether the broker answers with Connection.Tune
# (login accepted) or anything else (login refused).
import os, socket, ssl, struct
user = os.environ.get('AMQP_USER', 'guest')
pw = os.environ.get('AMQP_PASS', 'guest')
def frame(ftype, ch, payload):
    return struct.pack('>BHI', ftype, ch, len(payload)) + payload + b'\xce'
try:
    raw = socket.create_connection(('rabbitmq', 5671), timeout=5)
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    s = ctx.wrap_socket(raw, server_hostname='rabbitmq')
    s.settimeout(5)
    s.sendall(b'AMQP\x00\x00\x09\x01')
    s.recv(8192)
    resp = b'\x00' + user.encode() + b'\x00' + pw.encode()
    body = (struct.pack('>HH', 10, 11) + struct.pack('>I', 0)
            + bytes([5]) + b'PLAIN' + struct.pack('>I', len(resp)) + resp
            + bytes([5]) + b'en_US')
    s.sendall(frame(1, 0, body))
    data = s.recv(8192)
    if len(data) >= 11 and data[0] == 1 and struct.unpack('>HH', data[7:11]) == (10, 30):
        print('CONNECTED')
    else:
        print('REJECTED: broker did not send Connection.Tune')
except Exception as e:
    print('REJECTED:', type(e).__name__)
PY
)
py_b64=$(printf '%s\n' "$PY_PROBE" | base64 | tr -d '\n')
amqp_result=$(probe python:3-alpine "echo $py_b64 | base64 -d | python3" | tail -n1)
probe_ok "$amqp_result"
if echo "$amqp_result" | grep -q "CONNECTED"; then
    bad_succeeded "rabbitmq-broker-guest-guest (AMQP login over TLS accepted)"
else
    ok_blocked "rabbitmq-broker-guest-guest (${amqp_result:-no output})"
fi

# ──────────────────────────────────────────
# Attack 4c: is the management port reachable at all, with no credentials?
# Any HTTP answer (even 401) means a pod can reach the admin interface.
# ──────────────────────────────────────────
status=$(probe curlimages/curl 'curl -s -o /dev/null -w "%{http_code}" -m 5 http://rabbitmq:15672/api/overview' | tail -n1)
probe_ok "$status"
if [ -n "$status" ] && [ "$status" != "000" ]; then
    bad_succeeded "rabbitmq-management-port-reachable (status $status, admin interface reachable from any pod)"
else
    ok_blocked "rabbitmq-management-port-reachable (status ${status:-none})"
fi

# ──────────────────────────────────────────
# Attack 5: Postgres, weak passwords for the superuser and the app user.
# One pod runs the whole loop. Prints user/password only if one works.
# ──────────────────────────────────────────
pg_found=$(probe postgres:16-alpine 'for u in postgres foundersync_app; do for pw in postgres admin123 admin password root foundersync_app guest changeme; do out=$(PGCONNECT_TIMEOUT=5 PGPASSWORD=$pw psql -h postgres -U $u -d auth_db -tAc "select 1" 2>/dev/null); if [ "$out" = "1" ]; then echo "FOUND $u/$pw"; exit 0; fi; done; done; echo NONE' | tail -n1)
probe_ok "$pg_found"
if echo "$pg_found" | grep -q "^FOUND"; then
    bad_succeeded "postgres-weak-password (${pg_found#FOUND } worked)"
else
    ok_blocked "postgres-weak-password (${pg_found:-no output}; tried postgres/foundersync_app with 8 common passwords)"
fi

# ──────────────────────────────────────────
# Attack 6: MongoDB with no credentials, read real chat data.
# ──────────────────────────────────────────
mongo_out=$(probe mongo:7-jammy 'mongosh "mongodb://mongodb:27017/chatdb" --quiet --eval "db.messages.countDocuments()" 2>&1 | tail -n1')
probe_ok "$mongo_out"
if echo "$mongo_out" | grep -qE '^[0-9]+$'; then
    bad_succeeded "mongodb-no-auth-read-messages (read $mongo_out message(s) with zero credentials)"
else
    ok_blocked "mongodb-no-auth-read-messages (${mongo_out:-no output})"
fi

exit "$RESULT"
