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
# Set PROBE_OPTS="--annotations=sidecar.istio.io/inject=false" to run the
# probes without an Istio sidecar (an attacker pod with no mesh identity).
PROBE_OPTS="${PROBE_OPTS:-}"
RESULT=0

ok_blocked()    { printf '[ATTACK] %s -> BLOCKED\n' "$1"; }
bad_succeeded() { printf '[ATTACK] %s -> SUCCEEDED\n' "$1"; RESULT=1; }

# probe <image> <shell command>: run the command in a throwaway pod and
# print its stdout. The pod is removed when it exits.
probe() {
    # shellcheck disable=SC2086
    kubectl run "atk-$RANDOM$RANDOM" --image="$1" --image-pull-policy=IfNotPresent \
        --restart=Never --rm -i --quiet -n "$NS" $PROBE_OPTS \
        --command -- sh -c "$2" 2>/dev/null
}

# ──────────────────────────────────────────
# Attack 4a: RabbitMQ management API, guest/guest
# ──────────────────────────────────────────
status=$(probe curlimages/curl 'curl -s -o /dev/null -w "%{http_code}" -m 5 -u guest:guest http://rabbitmq:15672/api/overview' | tail -n1)
if [ "$status" = "200" ]; then
    bad_succeeded "rabbitmq-management-guest-guest (status $status)"
else
    ok_blocked "rabbitmq-management-guest-guest (status $status)"
fi

# ──────────────────────────────────────────
# Attack 4b: RabbitMQ AMQP, guest/guest. Needs a real AMQP client, so the
# Python script is passed base64-encoded to avoid shell quoting problems.
# ──────────────────────────────────────────
PY_PROBE=$(cat <<'PY'
import pika
try:
    creds = pika.PlainCredentials('guest', 'guest')
    params = pika.ConnectionParameters(host='rabbitmq', port=5672, credentials=creds,
                                       connection_attempts=1, socket_timeout=5)
    conn = pika.BlockingConnection(params)
    ch = conn.channel()
    ch.queue_declare(queue='attack-script-probe', auto_delete=True)
    conn.close()
    print('CONNECTED')
except Exception as e:
    print('REJECTED:', type(e).__name__)
PY
)
py_b64=$(printf '%s\n' "$PY_PROBE" | base64 | tr -d '\n')
amqp_result=$(probe python:3-alpine "pip install -q pika >/dev/null 2>&1; echo $py_b64 | base64 -d | python3" | tail -n1)
if echo "$amqp_result" | grep -q "CONNECTED"; then
    bad_succeeded "rabbitmq-broker-guest-guest (AMQP connect + queue declare succeeded)"
else
    ok_blocked "rabbitmq-broker-guest-guest (${amqp_result:-no output})"
fi

# ──────────────────────────────────────────
# Attack 4c: is the management port reachable at all, with no credentials?
# Any HTTP answer (even 401) means a pod can reach the admin interface.
# ──────────────────────────────────────────
status=$(probe curlimages/curl 'curl -s -o /dev/null -w "%{http_code}" -m 5 http://rabbitmq:15672/api/overview' | tail -n1)
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
if echo "$pg_found" | grep -q "^FOUND"; then
    bad_succeeded "postgres-weak-password (${pg_found#FOUND } worked)"
else
    ok_blocked "postgres-weak-password (${pg_found:-no output}; tried postgres/foundersync_app with 8 common passwords)"
fi

# ──────────────────────────────────────────
# Attack 6: MongoDB with no credentials, read real chat data.
# ──────────────────────────────────────────
mongo_out=$(probe mongo:7-jammy 'mongosh "mongodb://mongodb:27017/chatdb" --quiet --eval "db.messages.countDocuments()" 2>&1 | tail -n1')
if echo "$mongo_out" | grep -qE '^[0-9]+$'; then
    bad_succeeded "mongodb-no-auth-read-messages (read $mongo_out message(s) with zero credentials)"
else
    ok_blocked "mongodb-no-auth-read-messages (${mongo_out:-no output})"
fi

exit "$RESULT"
