#!/usr/bin/env bash
set -euo pipefail
# Run Zig system-test against a pre-started llama.cpp server (Windows).
# Caller is responsible for starting the server and cleaning up.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$(dirname "$SCRIPT_DIR")/.." && pwd)"

echo "running live investment system demo proof (Windows)"

# Use orchestrator to run the Zig test
ZIG_GLOBAL_CACHE_DIR="$REPO_ROOT/build/.zig-global-cache" python "$(dirname "$SCRIPT_DIR")/test/orchestrator.py" zig-test --target system-test
