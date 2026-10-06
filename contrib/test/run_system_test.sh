#!/usr/bin/env bash
# Run Zig system-test against a pre-started llama.cpp server.
# Lifecycle: start server → run tests → stop server.
# Setup/install is a separate step: `just infra-ensure-llamacpp`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$(dirname "$SCRIPT_DIR")/.." && pwd)"

# Phase 1: Start server
python3 "$(dirname "$SCRIPT_DIR")/test/orchestrator.py" llm-server-start

# Phase 2: Run tests
ZIG_GLOBAL_CACHE_DIR="$REPO_ROOT/build/.zig-global-cache" python3 "$(dirname "$SCRIPT_DIR")/test/orchestrator.py" zig-test --target system-test

# Phase 3: Cleanup
python3 "$(dirname "$SCRIPT_DIR")/test/orchestrator.py" llm-server-stop
