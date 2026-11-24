#!/usr/bin/env bash
#
# Runs all 4 attack scripts against whatever stack is currently up on
# localhost, and saves a timestamped copy of the full output under
# evidence/red/ or evidence/green/.
#
# Usage:
#   ./scripts/attacks/run-all.sh red     # before steps 5-7 (expected: mostly SUCCEEDED)
#   ./scripts/attacks/run-all.sh green   # after steps 5-7  (expected: mostly BLOCKED)
#   TARGET=k3d ./scripts/attacks/run-all.sh green   # against the k3d cluster
#
# "red" and "green" are just where the output file goes — this script
# does not itself know which phase you're in, it just runs the same 4
# scripts every time so the before/after comparison is apples to apples.
#
# Exit code:
#   0 if every attack is BLOCKED, or the only SUCCEEDED lines are the
#     documented residual risk from attack-forged-token.sh (10b/10c).
#   1 if ANY OTHER attack SUCCEEDED — that's a real regression, not a
#     known, accepted risk.
#
# Does not wait for docker compose health itself — run this against a
# stack you already confirmed is healthy (docker compose up -d --wait),
# same as scripts/smoke-test.sh.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

MODE="${1:-}"
if [ "$MODE" != "red" ] && [ "$MODE" != "green" ]; then
    echo "Usage: $0 red|green"
    exit 2
fi

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUT_DIR="$REPO_ROOT/evidence/$MODE"
OUT_FILE="$OUT_DIR/$TIMESTAMP.txt"
mkdir -p "$OUT_DIR"

# TARGET=compose (default) runs the Docker Compose versions. TARGET=k3d runs
# the k3d versions of the credential and network attacks (probes run as
# throwaway pods) and reads the real JWT secret from .env for the forged
# token attack. The secret is never printed.
TARGET="${TARGET:-compose}"
if [ "$TARGET" = "k3d" ]; then
    ATTACKS="attack-authz.sh attack-credentials-k3d.sh attack-network-k3d.sh attack-forged-token.sh"
    if [ -f "$REPO_ROOT/.env" ]; then
        set -a
        # shellcheck disable=SC1091
        . "$REPO_ROOT/.env"
        set +a
        export REAL_SECRET="${REAL_SECRET:-${JWT_SECRET:-}}"
    fi
else
    ATTACKS="attack-authz.sh attack-credentials.sh attack-network.sh attack-forged-token.sh"
fi

# Lines containing this marker never fail the overall run, even though
# they print SUCCEEDED — this is the documented shared-JWT-secret risk,
# which step 5 does not change and which we are not forcing green.
EXPECTED_MARKER="(expected, documented residual risk)"

OVERALL_RESULT=0
TOTAL_SUCCEEDED=0
TOTAL_BLOCKED=0
TOTAL_EXPECTED=0

{
    echo "Attack suite run: $TIMESTAMP"
    echo "Mode: $MODE"
    echo "Target: $TARGET (gateway localhost:8080)"
    echo "============================================================"
    echo

    for script in $ATTACKS; do
        echo "---- $script ----"
        script_output=$(bash "$SCRIPT_DIR/$script" 2>&1)
        script_exit=$?
        echo "$script_output"
        echo "(exit code: $script_exit)"
        echo

        succeeded_lines=$(echo "$script_output" | grep -c "SUCCEEDED" || true)
        expected_lines=$(echo "$script_output" | grep -c "$EXPECTED_MARKER" || true)
        unexpected_lines=$((succeeded_lines - expected_lines))

        blocked_lines=$(echo "$script_output" | grep -c "BLOCKED" || true)

        TOTAL_SUCCEEDED=$((TOTAL_SUCCEEDED + succeeded_lines))
        TOTAL_EXPECTED=$((TOTAL_EXPECTED + expected_lines))
        TOTAL_BLOCKED=$((TOTAL_BLOCKED + blocked_lines))

        if [ "$unexpected_lines" -gt 0 ]; then
            OVERALL_RESULT=1
        fi

        # Exit code 2 means the script could not run its checks (setup failed).
        # Missing results are not passing results, so the whole suite fails.
        if [ "$script_exit" -eq 2 ]; then
            echo "SETUP FAILED in $script: its checks did not run"
            OVERALL_RESULT=1
        fi
    done

    echo "============================================================"
    echo "Summary: $TOTAL_BLOCKED blocked, $TOTAL_SUCCEEDED succeeded ($TOTAL_EXPECTED of those are the documented residual risk)"
    if [ "$OVERALL_RESULT" -eq 0 ]; then
        echo "RESULT: PASS (every attack blocked, or only the documented residual risk succeeded)"
    else
        echo "RESULT: FAIL (an attack succeeded that is not on the documented residual-risk list)"
    fi
} | tee "$OUT_FILE"

echo
echo "Saved: $OUT_FILE"
exit "$OVERALL_RESULT"
