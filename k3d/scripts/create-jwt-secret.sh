#!/usr/bin/env bash
# Creates the jwt-secret Secret referenced by auth.yaml, user.yaml and
# chat.yaml's envFromSecret blocks. Kept as its own script rather than
# editing Member A's create-secrets.sh directly, since she owns that
# file's contract (postgres-credentials, rabbitmq-credentials) and the
# JWT secret is a B-side addition pending her sign-off.
#
# Default matches the JWT_SECRET fallback already used in
# docker-compose.yml / config-repo/auth-service.yml, so behavior is
# unchanged from Compose unless JWT_SECRET is overridden in the
# environment before running this script.
set -euo pipefail

NS="${NS:-foundersync}"
JWT_SECRET="${JWT_SECRET:-founderssync_jwt_secret_minimum_32_characters_ok}"

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NS" create secret generic jwt-secret \
  --from-literal=secret="$JWT_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "jwt-secret ready in namespace $NS"
