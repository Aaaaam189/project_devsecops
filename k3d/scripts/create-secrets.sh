#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ -f "$REPO_ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
fi

NS="${NS:-foundersync}"
: "${POSTGRES_PASSWORD:?Set POSTGRES_PASSWORD in .env or before running this script}"
: "${POSTGRES_APP_PASSWORD:?Set POSTGRES_APP_PASSWORD in .env or before running this script}"
: "${RABBITMQ_ADMIN_PASSWORD:?Set RABBITMQ_ADMIN_PASSWORD in .env or before running this script}"
: "${RABBITMQ_APP_PASSWORD:?Set RABBITMQ_APP_PASSWORD in .env or before running this script}"
: "${MONGO_ADMIN_PASSWORD:?Set MONGO_ADMIN_PASSWORD in .env or before running this script}"
: "${MONGO_CHAT_PASSWORD:?Set MONGO_CHAT_PASSWORD in .env or before running this script}"
: "${JWT_SECRET:?Set JWT_SECRET in .env or before running this script}"
: "${ADMIN_PASSWORD:?Set ADMIN_PASSWORD in .env or before running this script}"
ADMIN_USERNAME="${ADMIN_USERNAME:-admin@foundersync.com}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_APP_USER="${POSTGRES_APP_USER:-foundersync_app}"
RABBITMQ_ADMIN_USER="${RABBITMQ_ADMIN_USER:-rabbitmq_admin}"
RABBITMQ_APP_USER="${RABBITMQ_APP_USER:-foundersync_app}"
MONGO_ADMIN_USER="${MONGO_ADMIN_USER:-mongodb_admin}"
MONGO_CHAT_USER="${MONGO_CHAT_USER:-foundersync_chat}"

apply_credential_secret() {
  name="$1"
  username="$2"
  password="$3"
  username_b64="$(printf '%s' "$username" | base64 | tr -d '\n')"
  password_b64="$(printf '%s' "$password" | base64 | tr -d '\n')"
  payload="$(printf '{"apiVersion":"v1","kind":"Secret","metadata":{"name":"%s","namespace":"%s"},"type":"Opaque","data":{"username":"%s","password":"%s"}}' "$name" "$NS" "$username_b64" "$password_b64")"

  if ! printf '%s' "$payload" | kubectl create --validate=false -f - >/dev/null 2>&1; then
    printf '%s' "$payload" | kubectl replace --validate=false -f - >/dev/null
  fi
}

apply_credential_secret postgres-credentials "$POSTGRES_USER" "$POSTGRES_PASSWORD"
apply_credential_secret postgres-app-credentials "$POSTGRES_APP_USER" "$POSTGRES_APP_PASSWORD"
apply_credential_secret rabbitmq-admin-credentials "$RABBITMQ_ADMIN_USER" "$RABBITMQ_ADMIN_PASSWORD"
apply_credential_secret rabbitmq-app-credentials "$RABBITMQ_APP_USER" "$RABBITMQ_APP_PASSWORD"
apply_credential_secret rabbitmq-credentials "$RABBITMQ_ADMIN_USER" "$RABBITMQ_ADMIN_PASSWORD"
apply_credential_secret mongodb-credentials "$MONGO_ADMIN_USER" "$MONGO_ADMIN_PASSWORD"
apply_credential_secret mongodb-chat-credentials "$MONGO_CHAT_USER" "$MONGO_CHAT_PASSWORD"
apply_credential_secret auth-admin-credentials "$ADMIN_USERNAME" "$ADMIN_PASSWORD"

jwt_b64="$(printf '%s' "$JWT_SECRET" | base64 | tr -d '\n')"
jwt_payload="$(printf '{"apiVersion":"v1","kind":"Secret","metadata":{"name":"jwt-secret","namespace":"%s"},"type":"Opaque","data":{"secret":"%s"}}' "$NS" "$jwt_b64")"

if ! printf '%s' "$jwt_payload" | kubectl create --validate=false -f - >/dev/null 2>&1; then
  printf '%s' "$jwt_payload" | kubectl replace --validate=false -f - >/dev/null
fi

echo "Secrets ready in namespace $NS"