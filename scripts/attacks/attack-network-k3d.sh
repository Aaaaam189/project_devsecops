#!/usr/bin/env bash
#
# k3d version of attack-network.sh. Probes run as throwaway pods in the
# cluster instead of containers on the Docker Compose network.
#
# Attack 7a: config-server serves a real secret value (not a ${PLACEHOLDER})
#            for app.jwt.secret or any password.
# Attack 7b: config-server is reachable from an arbitrary pod. Today any
#            pod can read every service's config. Step 6 (Istio
#            AuthorizationPolicy) should flip this to BLOCKED.
# Attack 8:  reach a backend service directly from the host, bypassing the
#            gateway. On k3d only :8080 is published, so this is expected
#            to be BLOCKED already.
# Attack 9:  wrong caller. A throwaway pod calls startup-service by name,
#            no token, no gateway. Step 6 should flip this to BLOCKED.
#
# Convention: one line per attempt, SUCCEEDED or BLOCKED. Exit 1 if any
# SUCCEEDED.

set -u

NS="${NS:-foundersync}"
# Probes run WITHOUT an Istio sidecar by default: an attacker pod with no
# mesh identity. Set PROBE_OPTS="" to give the probe a sidecar and the
# default ServiceAccount instead (then Istio's AuthorizationPolicy decides).
PROBE_OPTS="${PROBE_OPTS---annotations=sidecar.istio.io/inject=false}"
STARTUP_SERVICE_PORT_URL="${STARTUP_SERVICE_PORT_URL:-http://localhost:8083}"
RESULT=0

ok_blocked()    { printf '[ATTACK] %s -> BLOCKED\n' "$1"; }
bad_succeeded() { printf '[ATTACK] %s -> SUCCEEDED\n' "$1"; RESULT=1; }

# The pod first prints a sentinel; if it never arrives the probe did not run
# and the output is __PROBE_FAILED__. An empty result must never be read as
# BLOCKED.
probe() {
    local out attempt body
    for attempt in 1 2 3; do
        # shellcheck disable=SC2086
        out=$(kubectl run "atk-$RANDOM$RANDOM" --image="$1" --image-pull-policy=IfNotPresent \
            --restart=Never --rm -i --quiet -n "$NS" $PROBE_OPTS \
            --command -- sh -c "echo __PROBE_OK__; sleep 6; $2" 2>/dev/null)
        body=$(printf '%s\n' "$out" | grep -v '__PROBE_OK__' | sed '/^[[:space:]]*$/d')
        # Sentinel seen AND some result printed: the probe really ran.
        if printf '%s\n' "$out" | grep -q '__PROBE_OK__' && [ -n "$body" ]; then
            printf '%s\n' "$body"
            return
        fi
    done
    echo "__PROBE_FAILED__"
}
probe_ok() {
    if [ "$1" = "__PROBE_FAILED__" ]; then
        echo "SETUP FAILED: the probe pod did not run (image pull, scheduling or attach problem). Result would be meaningless."
        exit 2
    fi
}

# ──────────────────────────────────────────
# Attack 7a + 7b: read config-server from a throwaway pod.
# The body is checked inside the pod, so no secret value ever leaves it.
# Output is one line: "STATUS=<code> LITERAL_SECRET=<yes|no>".
# LITERAL_SECRET=yes if any password/secret key holds a value that is not
# a ${NAME} placeholder. A ${NAME:dummy-...} placeholder is accepted
# (the AWS keys default to dummy values). Any other default is flagged.
# ──────────────────────────────────────────
cfg=$(probe curlimages/curl '
bad=no
code=000
for svc in auth-service user-service startup-service post-service notification-service; do
  body=$(curl -s -m 5 -w "\n%{http_code}" http://config-server:8888/$svc/default)
  code=$(printf "%s" "$body" | tail -n1)
  json=$(printf "%s" "$body" | sed "\$d")
  if printf "%s" "$json" | tr "," "\n" | grep -iE "\"[^\"]*(secret|password)[^\"]*\"" | grep -vE ":\"\\$\{[A-Z_]+(:dummy-[a-z-]+)?\}\"" | grep -q .; then bad=yes; fi
done
echo "STATUS=$code LITERAL_SECRET=$bad"' | tail -n1)
probe_ok "$cfg"

if echo "$cfg" | grep -q "LITERAL_SECRET=yes"; then
    bad_succeeded "config-server-leaks-literal-secret (a secret/password value is served in clear text)"
elif echo "$cfg" | grep -q "STATUS=200"; then
    ok_blocked "config-server-leaks-literal-secret (${cfg}; only \${PLACEHOLDER} values served)"
else
    ok_blocked "config-server-leaks-literal-secret (${cfg}; config-server not reachable from this pod, body not checked)"
fi

if echo "$cfg" | grep -q "STATUS=200"; then
    bad_succeeded "config-server-reachable-from-any-pod (status 200, any pod can read every service's config)"
else
    ok_blocked "config-server-reachable-from-any-pod (${cfg:-no response})"
fi

# ──────────────────────────────────────────
# Attack 8: direct port from the host, bypassing the gateway.
# ──────────────────────────────────────────
status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$STARTUP_SERVICE_PORT_URL/api/startups")
if [ "$status" != "000" ]; then
    bad_succeeded "direct-port-bypass-gateway (status $status, service reachable without going through :8080)"
else
    ok_blocked "direct-port-bypass-gateway (no response, port not reachable from the host)"
fi

# ──────────────────────────────────────────
# Attack 9: wrong caller, a throwaway pod calls startup-service directly.
# Any HTTP status (even 401) means the pod reached the service.
# ──────────────────────────────────────────
# A 403 whose body is "RBAC: access denied" is Istio's AuthorizationPolicy
# refusing the caller, so it counts as BLOCKED. A connection that fails
# (000) is a pod without a sidecar being refused by STRICT mTLS.
status=$(probe curlimages/curl 'out=$(curl -s -m 5 -w "|%{http_code}" http://startup-service:8083/api/startups); case "$out" in *"RBAC: access denied"*) echo DENIED;; *) echo "${out##*|}";; esac' | tail -n1)
probe_ok "$status"
if [ "$status" = "DENIED" ]; then
    ok_blocked "wrong-caller-throwaway-pod (refused by the Istio AuthorizationPolicy: RBAC access denied)"
elif [ -n "$status" ] && [ "$status" != "000" ]; then
    bad_succeeded "wrong-caller-throwaway-pod (status $status, reached startup-service directly by name)"
else
    ok_blocked "wrong-caller-throwaway-pod (status ${status:-none}, connection refused or reset)"
fi

exit "$RESULT"
