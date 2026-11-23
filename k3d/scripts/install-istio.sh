#!/usr/bin/env bash
set -euo pipefail

ISTIO_VERSION="1.24.3"
ISTIO_PROFILE="demo"

if ! command -v istioctl >/dev/null 2>&1; then
  echo "istioctl is required. Install version ${ISTIO_VERSION} before running this script." >&2
  exit 1
fi

client_version="$(istioctl version --remote=false 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -u | head -n 1 || true)"
if [[ -z "$client_version" ]]; then
  echo "Could not determine the istioctl version. Install istioctl ${ISTIO_VERSION}." >&2
  exit 1
fi
if [[ "$client_version" != "$ISTIO_VERSION" ]]; then
  echo "Istioctl version mismatch: found $client_version, expected $ISTIO_VERSION." >&2
  exit 1
fi

# Why the extra --set flags (all three are needed on k3d):
#  - holdApplicationUntilProxyStarts: the app container waits for its sidecar,
#    otherwise a Java service can start before the proxy is ready and fail its
#    config-server fetch.
#  - istio-ingressgateway type ClusterIP: the demo profile makes it a
#    LoadBalancer, and k3s would then try to bind host port 80 a second time
#    (Traefik already holds it). Traefik reaches the gateway through the
#    Ingress in k3d/ingress.yaml instead.
#  - smaller sidecar requests, so ten sidecars fit on a single-node k3d cluster.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
istioctl install \
  --set "profile=${ISTIO_PROFILE}" \
  --set meshConfig.defaultConfig.proxyStatsMatcher.inclusionRegexps[0]='.*' \
  --set meshConfig.defaultConfig.holdApplicationUntilProxyStarts=true \
  --set values.gateways.istio-ingressgateway.type=ClusterIP \
  --set values.global.proxy.resources.requests.cpu=20m \
  --set values.global.proxy.resources.requests.memory=64Mi \
  -y

kubectl apply -f "$SCRIPT_DIR/../namespace.yaml"
kubectl apply -f "$SCRIPT_DIR/../istio-peer-authentication.yaml"
kubectl apply -f "$SCRIPT_DIR/../istio-gateway.yaml"

kubectl -n istio-system rollout status deployment/istio-ingressgateway --timeout=120s
kubectl -n istio-system get service istio-ingressgateway
kubectl -n foundersync get gateway,virtualservice
echo "Istio ${ISTIO_VERSION} installed with profile ${ISTIO_PROFILE}"
