#!/usr/bin/env bash
# Creates only the jwt-secret Secret. The recommended k3d bootstrap is
# k3d/scripts/create-secrets.sh, which creates this Secret together with
# the PostgreSQL and RabbitMQ Secrets.
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
: "${JWT_SECRET:?Set JWT_SECRET in .env or before running this script}"

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NS" create secret generic jwt-secret \
  --from-literal=secret="$JWT_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "jwt-secret ready in namespace $NS"
