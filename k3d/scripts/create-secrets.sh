#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-foundersync}"
: "${POSTGRES_PASSWORD:?Set POSTGRES_PASSWORD first}"
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

echo "Secrets ready in namespace $NS"