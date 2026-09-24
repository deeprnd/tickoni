#!/usr/bin/env bash
# Run all compiled test binaries sequentially.
# Zig 0.16 stores test binaries in .zig-cache/o/<hash>/test,
# not in zig-out/bin/ (addRunArtifact handles that automatically).
set -euo pipefail

echo "Finding test binaries..."

# Prefer explicit artifact paths passed from build.zig. Fall back to cache
# discovery for older callers.
declare -a binaries=("$@")
if [[ ${#binaries[@]} -eq 0 ]]; then
    while IFS= read -r bin; do
        binaries+=("$bin")
    done < <(find .zig-cache/o -name test -type f 2>/dev/null | sort)
fi

if [[ ${#binaries[@]} -eq 0 ]]; then
    echo "ERROR: No test binaries found in .zig-cache/o/" >&2
    exit 1
fi

echo "Found ${#binaries[@]} test binaries, running sequentially..."
failures=0
passed=0

# Patterns that indicate a test failure even if the binary exits 0
FAIL_PATTERNS=(
    "SIGABRT"
    "ERR"
    "FAILED"
    "failed command:"
    "segmentation fault"
    "core dumped"
)

for bin in "${binaries[@]}"; do
    name=$(basename "$(dirname "$bin")")
    echo -n "  ${name}... "
    output=$("$bin" 2>&1) || true
    exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo "FAILED (exit $exit_code)"
        failures=$((failures + 1))
    else
        # Also check output for failure indicators that the test binary
        # might not have translated to a non-zero exit code (e.g. supervisor
        # crashes via SIGABRT that the test binary spawns but doesn't check).
        found_fail=0
        for pat in "${FAIL_PATTERNS[@]}"; do
            if echo "$output" | grep -q "$pat"; then
                echo "FAILED (output contains '$pat')"
                found_fail=1
                break
            fi
        done
        if [[ $found_fail -eq 0 ]]; then
            echo "OK"
            passed=$((passed + 1))
        else
            failures=$((failures + 1))
        fi
    fi
done

if [[ $failures -gt 0 ]]; then
    echo ""
    echo "FAIL: $failures of ${#binaries[@]} tests failed (${passed} passed)" >&2
    exit 1
fi

echo "All ${#binaries[@]} tests passed."
