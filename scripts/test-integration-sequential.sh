#!/usr/bin/env bash
set -euo pipefail

TIMEOUT=60
PASS=0
FAIL=0
HANG=0

echo "=============================================="
echo "Sequential Integration Test Runner"
echo "=============================================="
echo ""

# First, build all integration test binaries
echo "Building integration test binaries..."
if ! zig build -Dtest=true integration-test 2>&1; then
    echo "Build failed"
    exit 1
fi
echo ""
echo "Build complete. Finding test binaries..."
echo ""

# Find all test binaries in zig-cache/o/<hash>/test
# The integration tests are registered via addPlainTestRun which uses addArtifactArg
# and run steps. Let me find them.
declare -a TESTS=()

# Integration tests from build-lib/lanes/integration.zig:
# Static tests (investment): test-investment-allowed-trade, etc.
# Process tests: test-metric-tile-integration, test-process-pipeline, etc.
# Other: test-investment-demo-test, test-investment-replay, test-investment-decision-cards, test-mock-servers, test-model-tile-http

# Zig test binaries end up in .zig-cache/o/<hash>/test
mapfile -d '' TESTS < <(find .zig-cache/o -name "test" -type f -executable -print0 2>/dev/null | sort -z)

echo "Found ${#TESTS[@]} test binaries:"
for b in "${TESTS[@]}"; do
    echo "  $b"
done
echo ""

if [ ${#TESTS[@]} -eq 0 ]; then
    echo "ERROR: No test binaries found"
    exit 1
fi

for binary in "${TESTS[@]}"; do
    name=$(basename "$(dirname "$binary")")
    echo "=== RUNNING: $name ==="
    start=$(date +%s)
    
    if timeout ${TIMEOUT}s "$binary"; then
        elapsed=$(( $(date +%s) - start ))
        echo "PASS (${elapsed}s): $name"
        PASS=$((PASS + 1))
    else
        elapsed=$(( $(date +%s) - start ))
        if [ "$elapsed" -ge $((TIMEOUT - 5)) ]; then
            echo "HANG/timeout (${elapsed}s): $name (timed out after ${TIMEOUT}s)"
            HANG=$((HANG + 1))
        else
            echo "FAIL (${elapsed}s): $name"
            FAIL=$((FAIL + 1))
        fi
    fi
    echo ""
done

echo "=============================================="
echo "Results: PASS=$PASS FAIL=$FAIL HANG=$HANG"
echo "=============================================="
