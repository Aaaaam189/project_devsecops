#!/usr/bin/env bash
#
# Authorization attacks (no network/credential tricks, just the app's own
# API). These target a real, already-confirmed gap: post-service and
# notification-service trust a caller-supplied userId with no token check
# at all, and nothing stops a valid token for one user being used to act
# as a different user.
#
# Attack 1: read another user's notifications with no token at all.
# Attack 2: create a post "as" another user (impersonation via a trusted
#           request body field).
# Attack 3: delete another user's profile with no token at all
#           (DELETE /api/users/{userId} requires no Authorization header
#           in user-service today). Only ever targets the throwaway
#           "victim" user this script itself registered a moment earlier
#           — never a real or admin account. Reads the profile before
#           and after as a control, so the evidence shows the account
#           existed, then shows it's gone.
#
# Convention: each attempt prints one line:
#   [ATTACK] <name> -> SUCCEEDED   (the attacker got what they wanted)
#   [ATTACK] <name> -> BLOCKED     (server refused)
# Exit 0 only if every attack is BLOCKED. Exit 1 if any SUCCEEDED.

set -u

GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"
RESULT=0

ok_blocked()    { printf '[ATTACK] %s -> BLOCKED\n' "$1"; }
bad_succeeded() { printf '[ATTACK] %s -> SUCCEEDED\n' "$1"; RESULT=1; }

register_and_login() {
    local email="$1"
    local password="SmokeTest123!"
    local body status json
    body=$(printf '{"email":"%s","password":"%s"}' "$email" "$password")
    curl -s -X POST "$GATEWAY_URL/api/auth/register" -H "Content-Type: application/json" -d "$body" >/dev/null
    json=$(curl -s -X POST "$GATEWAY_URL/api/auth/login" -H "Content-Type: application/json" -d "$body")
    echo "$json"
}

json_field() {
    local field="$1"
    grep -o "\"${field}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed -E "s/\"${field}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"/\1/" | head -n1
}

# ──────────────────────────────────────────
# Set up two real users: A (victim) and B (attacker)
# ──────────────────────────────────────────
STAMP=$(date +%s)
EMAIL_A="victim-${STAMP}-$$@test.com"
EMAIL_B="attacker-${STAMP}-$$@test.com"

login_a=$(register_and_login "$EMAIL_A")
login_b=$(register_and_login "$EMAIL_B")

USER_A_ID=$(echo "$login_a" | json_field "userId")
USER_B_ID=$(echo "$login_b" | json_field "userId")
TOKEN_B=$(echo "$login_b" | json_field "accessToken")

if [ -z "$USER_A_ID" ] || [ -z "$USER_B_ID" ] || [ -z "$TOKEN_B" ]; then
    echo "SETUP FAILED: could not register/login both users. Raw responses:"
    echo "A: $login_a"
    echo "B: $login_b"
    exit 2
fi

echo "Victim (A)   userId: $USER_A_ID"
echo "Attacker (B) userId: $USER_B_ID"
echo

# ──────────────────────────────────────────
# Attack 1: read A's notifications with no token at all
# ──────────────────────────────────────────
status=$(curl -s -o /tmp/attack1_body -w '%{http_code}' "$GATEWAY_URL/api/notifications/$USER_A_ID")
if [ "$status" = "200" ]; then
    bad_succeeded "read-any-notifications-no-token (status $status)"
else
    ok_blocked "read-any-notifications-no-token (status $status)"
fi

# ──────────────────────────────────────────
# Attack 2: create a post "as" A, using B's identity to make the request
# but A's userId in the body — no token required by post-service at all,
# so this also works with zero Authorization header.
# ──────────────────────────────────────────
post_body=$(printf '{"content":"posted by attacker script","userId":"%s"}' "$USER_A_ID")
status=$(curl -s -o /tmp/attack2_body -w '%{http_code}' -X POST "$GATEWAY_URL/api/posts" \
    -H "Content-Type: application/json" -d "$post_body")
created_as=$(cat /tmp/attack2_body | json_field "userId")
if [ "$status" = "201" ] && [ "$created_as" = "$USER_A_ID" ]; then
    bad_succeeded "impersonate-and-post-as-victim (status $status, post created with victim's userId)"
else
    ok_blocked "impersonate-and-post-as-victim (status $status)"
fi

# ──────────────────────────────────────────
# Attack 3: delete A's (the throwaway victim's) profile with no token.
# Control reads before and after prove the account existed and then
# doesn't, rather than just trusting the DELETE response code alone.
# ──────────────────────────────────────────
before_status=$(curl -s -o /tmp/attack3_before -w '%{http_code}' "$GATEWAY_URL/api/users/$USER_A_ID")
before_id=$(cat /tmp/attack3_before | json_field "userId")

delete_status=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "$GATEWAY_URL/api/users/$USER_A_ID")

after_status=$(curl -s -o /tmp/attack3_after -w '%{http_code}' "$GATEWAY_URL/api/users/$USER_A_ID")

if [ "$before_status" = "200" ] && [ "$before_id" = "$USER_A_ID" ] && [ "$delete_status" = "204" ] && [ "$after_status" != "200" ]; then
    bad_succeeded "delete-another-users-profile-no-token (before=$before_status, delete=$delete_status, after=$after_status)"
else
    ok_blocked "delete-another-users-profile-no-token (before=$before_status, delete=$delete_status, after=$after_status)"
fi

rm -f /tmp/attack1_body /tmp/attack2_body /tmp/attack3_before /tmp/attack3_after
exit "$RESULT"
