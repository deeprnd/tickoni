#!/usr/bin/env bash
# Run all compiled test binaries sequentially.
# Zig 0.16 stores test binaries in .zig-cache/o/<hash>/test,
# not in zig-out/bin/ (addRunArtifact handles that automatically).
set -uo pipefail

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

for bin in "${binaries[@]}"; do
    name=$(basename "$(dirname "$bin")")
    echo -n "  ${name}... "
    if "$bin"; then
        echo "OK"
        passed=$((passed + 1))
    else
        echo "FAILED"
        failures=$((failures + 1))
    fi
done

if [[ $failures -gt 0 ]]; then
    echo ""
    echo "FAIL: $failures of ${#binaries[@]} tests failed (${passed} passed)" >&2
    exit 1
fi

echo "All ${#binaries[@]} tests passed."
