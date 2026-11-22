#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CERT_DIR="$REPO_ROOT/k3d/tls/rabbitmq"
NS="${NS:-foundersync}"
SECRET_NAME="${RABBITMQ_TLS_SECRET_NAME:-rabbitmq-tls}"
DAYS="${RABBITMQ_TLS_DAYS:-825}"

command -v openssl >/dev/null 2>&1 || { echo "openssl is required" >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required" >&2; exit 1; }

mkdir -p "$CERT_DIR"
umask 077

openssl req -x509 -newkey rsa:4096 -sha256 -nodes \
  -keyout "$CERT_DIR/ca.key" \
  -out "$CERT_DIR/ca.crt" \
  -days "$DAYS" \
  -subj "/CN=FoundersSync RabbitMQ CA" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:1" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"

cat > "$CERT_DIR/server-ext.cnf" <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:rabbitmq,DNS:rabbitmq.foundersync,DNS:rabbitmq.foundersync.svc,DNS:rabbitmq.foundersync.svc.cluster.local
EOF

openssl req -new -newkey rsa:2048 -nodes \
  -keyout "$CERT_DIR/tls.key" \
  -out "$CERT_DIR/tls.csr" \
  -subj "/CN=rabbitmq.foundersync.svc"

openssl x509 -req -sha256 \
  -in "$CERT_DIR/tls.csr" \
  -CA "$CERT_DIR/ca.crt" \
  -CAkey "$CERT_DIR/ca.key" \
  -CAcreateserial \
  -out "$CERT_DIR/tls.crt" \
  -days "$DAYS" \
  -extfile "$CERT_DIR/server-ext.cnf"

rm -f "$CERT_DIR/tls.csr" "$CERT_DIR/ca.srl" "$CERT_DIR/server-ext.cnf"

secret_json() {
  kubectl -n "$NS" create secret generic "$SECRET_NAME" \
    --from-file=ca.crt="$CERT_DIR/ca.crt" \
    --from-file=tls.crt="$CERT_DIR/tls.crt" \
    --from-file=tls.key="$CERT_DIR/tls.key" \
    --dry-run=client -o json
}

if ! secret_json | kubectl create --validate=false -f - >/dev/null 2>&1; then
  secret_json | kubectl replace --validate=false -f - >/dev/null
fi

echo "RabbitMQ TLS Secret $SECRET_NAME is ready in namespace $NS"
