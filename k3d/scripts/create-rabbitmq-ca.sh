#!/usr/bin/env bash
# Creates the rabbitmq-ca Secret: ONLY the CA certificate (ca.crt), which
# the services mount to verify the broker's TLS certificate.
#
# Why a separate Secret instead of mounting rabbitmq-tls: rabbitmq-tls also
# holds the broker's private key (tls.key). Clients need the CA certificate
# only, and a service that can be compromised should not be able to read the
# broker's key. The CA certificate is public information, not a secret, but
# a Secret is a convenient way to ship it.
#
# Run after k3d/scripts/create-rabbitmq-tls.sh, which generates the CA.
#
# On Windows Git Bash the TLS script needs MSYS2_ARG_CONV_EXCL='/CN=' (see
# its own notes); this script has no such arguments.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CA_FILE="$REPO_ROOT/k3d/tls/rabbitmq/ca.crt"
NS="${NS:-foundersync}"
SECRET_NAME="${RABBITMQ_CA_SECRET_NAME:-rabbitmq-ca}"

command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required" >&2; exit 1; }
[ -f "$CA_FILE" ] || { echo "$CA_FILE not found. Run k3d/scripts/create-rabbitmq-tls.sh first." >&2; exit 1; }

secret_json() {
  kubectl -n "$NS" create secret generic "$SECRET_NAME" \
    --from-file=ca.crt="$CA_FILE" \
    --dry-run=client -o json
}

if ! secret_json | kubectl create --validate=false -f - >/dev/null 2>&1; then
  secret_json | kubectl replace --validate=false -f - >/dev/null
fi

echo "RabbitMQ CA Secret $SECRET_NAME is ready in namespace $NS"
