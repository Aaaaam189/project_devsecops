#!/usr/bin/env bash
#
# Smoke test for the FoundersSync Docker Compose stack.
#
# What it does:
#   1. Starts the stack and waits for every container's healthcheck to pass.
#   2. Registers a brand-new test user (a fresh database has no users).
#   3. Logs in with that user.
#   4. Calls an authenticated endpoint with the JWT from login.
#   5. Checks the frontend responds.
#
# Exit code is 0 only if every step succeeds. On failure, it prints which
# check failed and exits 1 immediately — it does not continue past a failure.
#
# Usage:
#   ./scripts/smoke-test.sh
#
# Requires: docker compose, curl, a POSIX shell (bash). No jq dependency —
# JSON fields are pulled out with grep/sed since the response bodies are flat.

set -u

GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"
FRONTEND_URL="${FRONTEND_URL:-http://localhost:3001}"
COMPOSE_WAIT_TIMEOUT="${COMPOSE_WAIT_TIMEOUT:-300}"

TEST_EMAIL="smoketest-$(date +%s)-$$@test.com"
TEST_PASSWORD="SmokeTest123!"

PASS=0
FAIL=1

step() {
    printf '... %s\n' "$1"
}

ok() {
    printf 'OK   %s\n' "$1"
}

fail_and_exit() {
    printf 'FAIL %s\n' "$1"
    printf '\nSmoke test failed at: %s\n' "$1"
    exit "$FAIL"
}

# Extracts a JSON string field's value with grep/sed, no jq needed.
# Usage: json_field '"accessToken"' <<< "$body"
json_field() {
    local field="$1"
    grep -o "\"${field}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed -E "s/\"${field}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"/\1/" | head -n1
}

# ──────────────────────────────────────────
# 1. Start the stack and wait for healthchecks
# ──────────────────────────────────────────
step "docker compose up -d --wait (timeout ${COMPOSE_WAIT_TIMEOUT}s)"
if ! docker compose up -d --wait --wait-timeout "$COMPOSE_WAIT_TIMEOUT"; then
    fail_and_exit "docker compose up -d --wait (one or more containers did not become healthy)"
fi
ok "all containers healthy"

# ──────────────────────────────────────────
# 2. Register a fresh test user
# ──────────────────────────────────────────
step "register test user ($TEST_EMAIL)"
register_body=$(printf '{"email":"%s","password":"%s"}' "$TEST_EMAIL" "$TEST_PASSWORD")
register_response=$(curl -s -w '\n%{http_code}' -X POST "$GATEWAY_URL/api/auth/register" \
    -H "Content-Type: application/json" \
    -d "$register_body")
register_status=$(printf '%s' "$register_response" | tail -n1)
register_json=$(printf '%s' "$register_response" | sed '$d')

if [ "$register_status" != "200" ] && [ "$register_status" != "201" ]; then
    printf 'register response (status %s): %s\n' "$register_status" "$register_json"
    fail_and_exit "register test user (expected 200/201, got $register_status)"
fi
ok "register test user (status $register_status)"

# ──────────────────────────────────────────
# 3. Log in with the same user
# ──────────────────────────────────────────
step "login with test user"
login_response=$(curl -s -w '\n%{http_code}' -X POST "$GATEWAY_URL/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "$register_body")
login_status=$(printf '%s' "$login_response" | tail -n1)
login_json=$(printf '%s' "$login_response" | sed '$d')

if [ "$login_status" != "200" ]; then
    printf 'login response (status %s): %s\n' "$login_status" "$login_json"
    fail_and_exit "login with test user (expected 200, got $login_status)"
fi

access_token=$(printf '%s' "$login_json" | json_field "accessToken")
if [ -z "$access_token" ]; then
    printf 'login response: %s\n' "$login_json"
    fail_and_exit "login with test user (no accessToken in response)"
fi
ok "login with test user (status $login_status, token received)"

# ──────────────────────────────────────────
# 4. Authenticated call: fetch own profile
# ──────────────────────────────────────────
step "fetch /api/users/me with JWT"
me_response=$(curl -s -w '\n%{http_code}' "$GATEWAY_URL/api/users/me" \
    -H "Authorization: Bearer $access_token")
me_status=$(printf '%s' "$me_response" | tail -n1)
me_json=$(printf '%s' "$me_response" | sed '$d')

if [ "$me_status" != "200" ]; then
    printf '/api/users/me response (status %s): %s\n' "$me_status" "$me_json"
    fail_and_exit "fetch /api/users/me (expected 200, got $me_status)"
fi

returned_email=$(printf '%s' "$me_json" | json_field "email")
if [ "$returned_email" != "$TEST_EMAIL" ]; then
    printf '/api/users/me response: %s\n' "$me_json"
    fail_and_exit "fetch /api/users/me (email mismatch: expected $TEST_EMAIL, got $returned_email)"
fi
ok "fetch /api/users/me (status $me_status, email matches)"

# ──────────────────────────────────────────
# 5. Frontend reachable
# ──────────────────────────────────────────
step "frontend reachable at $FRONTEND_URL"
frontend_status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$FRONTEND_URL/")
if [ "$frontend_status" != "200" ]; then
    fail_and_exit "frontend reachable (expected 200, got $frontend_status)"
fi
ok "frontend reachable (status $frontend_status)"

printf '\nAll smoke tests passed.\n'
exit "$PASS"
