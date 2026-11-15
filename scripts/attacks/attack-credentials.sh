#!/usr/bin/env bash
#
# Default/weak credential attacks against the three data stores. These
# run from a disposable container on the compose network (not docker exec
# into the target container), so they represent what anyone who can reach
# these ports could do, not just someone with host access.
#
# Attack 4: RabbitMQ guest/guest, both the broker (AMQP, port 5672) and
#           the management API (HTTP, port 15672).
# Attack 5: Postgres with a short list of common weak passwords.
# Attack 6: MongoDB with no username/password at all, reading real chat
#           data (not just a ping).
#
# Convention: same as attack-authz.sh — one line per attempt, SUCCEEDED
# or BLOCKED, exit 1 if anything SUCCEEDED.

set -u

NETWORK="${NETWORK:-development-platform-owana_team_foundersync-network}"
RESULT=0

ok_blocked()    { printf '[ATTACK] %s -> BLOCKED\n' "$1"; }
bad_succeeded() { printf '[ATTACK] %s -> SUCCEEDED\n' "$1"; }

# ──────────────────────────────────────────
# Attack 4a: RabbitMQ management API, guest/guest
# ──────────────────────────────────────────
status=$(docker run --rm --network "$NETWORK" curlimages/curl -s -o /dev/null -w '%{http_code}' \
    -u guest:guest http://rabbitmq-foundersync:15672/api/overview)
if [ "$status" = "200" ]; then
    bad_succeeded "rabbitmq-management-guest-guest (status $status)"
    RESULT=1
else
    ok_blocked "rabbitmq-management-guest-guest (status $status)"
fi

# ──────────────────────────────────────────
# Attack 4b: RabbitMQ broker (AMQP), guest/guest — a real connection and
# queue declare, not just a port check. Runs a tiny Python script inside
# a disposable container since AMQP needs a real client, not curl.
# ──────────────────────────────────────────
amqp_result=$(docker run --rm --network "$NETWORK" python:3-alpine sh -c "
pip install -q pika 2>/dev/null
python3 -c \"
import pika
try:
    creds = pika.PlainCredentials('guest', 'guest')
    params = pika.ConnectionParameters(host='rabbitmq-foundersync', credentials=creds, connection_attempts=1, socket_timeout=5)
    conn = pika.BlockingConnection(params)
    ch = conn.channel()
    ch.queue_declare(queue='attack-script-probe', auto_delete=True)
    conn.close()
    print('CONNECTED')
except Exception as e:
    print('REJECTED:', e)
\"
" 2>/dev/null)

if echo "$amqp_result" | grep -q "CONNECTED"; then
    bad_succeeded "rabbitmq-broker-guest-guest (AMQP connect + queue declare succeeded)"
    RESULT=1
else
    ok_blocked "rabbitmq-broker-guest-guest ($amqp_result)"
fi

# ──────────────────────────────────────────
# Attack 5: Postgres, try a short list of common weak passwords.
# Reports whichever one works, rather than assuming a specific value —
# the exact weak password can drift between environments, the point is
# that one trivially guessable password works at all.
# ──────────────────────────────────────────
PG_CANDIDATES="postgres admin123 admin password root"
pg_found=""
for pw in $PG_CANDIDATES; do
    out=$(docker run --rm --network "$NETWORK" postgres:16-alpine \
        psql "postgresql://postgres:${pw}@postgres:5432/auth_db" -tAc "select 1" 2>/dev/null)
    if [ "$out" = "1" ]; then
        pg_found="$pw"
        break
    fi
done

if [ -n "$pg_found" ]; then
    bad_succeeded "postgres-weak-password (password '$pg_found' worked)"
    RESULT=1
else
    ok_blocked "postgres-weak-password (none of: $PG_CANDIDATES)"
fi

# ──────────────────────────────────────────
# Attack 6: MongoDB with no credentials, read actual chat message data.
# ──────────────────────────────────────────
mongo_count=$(docker run --rm --network "$NETWORK" mongo:7-jammy \
    mongosh "mongodb://mongodb:27017/chatdb" --quiet --eval "db.messages.countDocuments()" 2>/dev/null)

if echo "$mongo_count" | grep -qE '^[0-9]+$'; then
    bad_succeeded "mongodb-no-auth-read-messages (read $mongo_count message(s) with zero credentials)"
    RESULT=1
else
    ok_blocked "mongodb-no-auth-read-messages (could not read: $mongo_count)"
fi

exit "$RESULT"
