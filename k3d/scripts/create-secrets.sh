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
: "${JWT_SECRET:?Set JWT_SECRET in .env or before running this script}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_APP_USER="${POSTGRES_APP_USER:-foundersync_app}"
RABBITMQ_USER="${RABBITMQ_USER:-guest}"
RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-guest}"

kubectl -n "$NS" delete secret postgres-credentials postgres-app-credentials rabbitmq-credentials jwt-secret --ignore-not-found=true >/dev/null

kubectl -n "$NS" create secret generic postgres-credentials \
  --from-literal=username="$POSTGRES_USER" \
  --from-literal=password="$POSTGRES_PASSWORD"

kubectl -n "$NS" create secret generic postgres-app-credentials \
  --from-literal=username="$POSTGRES_APP_USER" \
  --from-literal=password="$POSTGRES_APP_PASSWORD"

kubectl -n "$NS" create secret generic rabbitmq-credentials \
  --from-literal=username="$RABBITMQ_USER" \
  --from-literal=password="$RABBITMQ_PASSWORD"

kubectl -n "$NS" create secret generic jwt-secret \
  --from-literal=secret="$JWT_SECRET"

echo "Secrets ready in namespace $NS"