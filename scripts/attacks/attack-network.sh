#!/usr/bin/env bash
#
# Network-layer attacks: things that work today because there is no
# network segmentation yet, not because of an application bug. These are
# expected to flip at step 6 (Istio mTLS + default-deny network policy),
# not step 5.
#
# Attack 7: config-server leaks every service's resolved config with no
#           auth, including app.jwt.secret in plaintext. This is the
#           attack that explains WHY attack-forged-token.sh's real-secret
#           variant is possible — an attacker doesn't even need repo
#           access, just a reachable config-server.
# Attack 8: reach a backend service's business endpoint directly on its
#           published port, skipping the gateway entirely.
# Attack 9: same call, but from a throwaway container on the compose
#           network calling the service by name — the "wrong caller"
#           case, no gateway and no token, service-to-service.
#
# startup-service is used for 8/9 because it has a real AuthFilter
# (expect 401 both times today — the finding here is "reachable", not
# "unauthenticated", that's covered by attack-authz.sh against
# post-service/notification-service instead).
#
# Convention: same as the other attack-*.sh — SUCCEEDED/BLOCKED per line,
# exit 1 if anything SUCCEEDED.

set -u

CONFIG_SERVER_URL="${CONFIG_SERVER_URL:-http://localhost:8888}"
STARTUP_SERVICE_PORT_URL="${STARTUP_SERVICE_PORT_URL:-http://localhost:8083}"
NETWORK="${NETWORK:-development-platform-owana_team_foundersync-network}"
RESULT=0

ok_blocked()    { printf '[ATTACK] %s -> BLOCKED\n' "$1"; }
bad_succeeded() { printf '[ATTACK] %s -> SUCCEEDED\n' "$1"; }

# ──────────────────────────────────────────
# Attack 7: config-server leaks app.jwt.secret (and RabbitMQ/mail
# credentials) with zero authentication.
# ──────────────────────────────────────────
body=$(curl -s "$CONFIG_SERVER_URL/auth-service/default")
if echo "$body" | grep -q "app.jwt.secret"; then
    secret_line=$(echo "$body" | grep -o '"app.jwt.secret":"[^"]*"')
    bad_succeeded "config-server-leaks-jwt-secret ($secret_line)"
    RESULT=1
else
    ok_blocked "config-server-leaks-jwt-secret (no app.jwt.secret in response)"
fi

# ──────────────────────────────────────────
# Attack 8: direct port, bypass the gateway entirely, from the host.
# Any non-000 response (even a 401) means the port is reachable from
# outside — "blocked" here would mean connection refused/timeout, not a
# 401. A 401 still means the attacker found a live endpoint to probe
# further, including against attack-forged-token.sh's payloads.
# ──────────────────────────────────────────
status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$STARTUP_SERVICE_PORT_URL/api/startups")
if [ "$status" != "000" ]; then
    bad_succeeded "direct-port-bypass-gateway (status $status, service reachable without going through :8080)"
    RESULT=1
else
    ok_blocked "direct-port-bypass-gateway (no response, port not reachable)"
fi

# ──────────────────────────────────────────
# Attack 9: wrong caller — a throwaway container on the same compose
# network calling startup-service by its service name, no token, no
# gateway involved at all.
# ──────────────────────────────────────────
status=$(docker run --rm --network "$NETWORK" curlimages/curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
    http://startup-service:8083/api/startups)
if [ "$status" != "000" ]; then
    bad_succeeded "wrong-caller-throwaway-container (status $status, reached startup-service directly by name)"
    RESULT=1
else
    ok_blocked "wrong-caller-throwaway-container (no response)"
fi

exit "$RESULT"
