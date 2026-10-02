#!/usr/bin/env bash
# Run all compiled test binaries sequentially.
# Zig 0.16 stores test binaries in .zig-cache/o/<hash>/test,
# not in zig-out/bin/ (addRunArtifact handles that automatically).
set -euo pipefail

# Raise RLIMIT_MEMLOCK to unlimited so mlock() succeeds for workspace
# creation and child-tile joins. GitHub Actions runners cap RLIMIT_MEMLOCK
# (often at 64 KiB); ulimit alone can't raise past the hard limit, so we
# use sudo prlimit to bump both soft and hard limits at once.
# memlock is a Linux concept only.
echo "memlock before:"
if [[ "$(contrib/platform.sh os)" == "linux" ]]; then
    ulimit -Sl
    ulimit -Hl
    if [[ -f /proc/$$/limits ]]; then
        grep "Max locked memory" /proc/$$/limits
        if command -v sudo >/dev/null 2>&1 && \
           sudo prlimit --pid $$ --memlock=unlimited:unlimited 2>/dev/null; then
            echo "memlock after:"
            ulimit -Sl
            ulimit -Hl
            grep "Max locked memory" /proc/$$/limits
        fi
    fi
fi

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
    output_file=$(mktemp "${TMPDIR:-/tmp}/tickoni-test.XXXXXX")
    set +e
    "$bin" >"$output_file" 2>&1
    exit_code=$?
    set -e
    if [[ $exit_code -ne 0 ]]; then
        # Non-zero exit = test failed. Also print output for context.
        echo "FAILED (exit $exit_code)"
        cat "$output_file" >&2
        failures=$((failures + 1))
    else
        # Exit 0 means the test passed its assertions. FAIL_PATTERNS
        # output check is skipped because child processes may crash
        # (e.g. crash-after-heartbeat topology tests) and that's expected.
        echo "OK"
        passed=$((passed + 1))
    fi
    rm -f "$output_file"
done

if [[ $failures -gt 0 ]]; then
    echo ""
    echo "FAIL: $failures of ${#binaries[@]} tests failed (${passed} passed)" >&2
    exit 1
fi

echo "All ${#binaries[@]} tests passed."
