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
: "${JWT_SECRET:?Set JWT_SECRET in .env or before running this script}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
RABBITMQ_USER="${RABBITMQ_USER:-guest}"
RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-guest}"

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NS" create secret generic postgres-credentials \
  --from-literal=username="$POSTGRES_USER" \
  --from-literal=password="$POSTGRES_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NS" create secret generic rabbitmq-credentials \
  --from-literal=username="$RABBITMQ_USER" \
  --from-literal=password="$RABBITMQ_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NS" create secret generic jwt-secret \
  --from-literal=secret="$JWT_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secrets ready in namespace $NS"