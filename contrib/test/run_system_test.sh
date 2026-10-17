#!/usr/bin/env bash
# Run Zig system-test against a pre-started llama.cpp server.
# Lifecycle: start server → run tests → stop server.
# Setup/install is a separate step: `just infra-ensure-llamacpp`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$(dirname "$SCRIPT_DIR")/.." && pwd)"

# Use the repository-wide Python resolver. On Windows, `python3` may be the
# Microsoft Store alias while `py -3` is the working interpreter.
read -r -a PYTHON_CMD <<< "$(bash "$REPO_ROOT/contrib/setup/python.sh")"
PYTHON=("${PYTHON_CMD[@]}")

if command -v cygpath >/dev/null 2>&1; then
  ORCHESTRATOR_PATH="$(cygpath -w "$SCRIPT_DIR/orchestrator.py")"
  ZIG_GLOBAL_CACHE_PATH="$(cygpath -w "$REPO_ROOT/build/.zig-global-cache")"
else
  ORCHESTRATOR_PATH="$SCRIPT_DIR/orchestrator.py"
  ZIG_GLOBAL_CACHE_PATH="$REPO_ROOT/build/.zig-global-cache"
fi

# Phase 1: Start server
"${PYTHON[@]}" "$ORCHESTRATOR_PATH" llm-server-start

# Phase 2: Run tests
ZIG_GLOBAL_CACHE_DIR="$ZIG_GLOBAL_CACHE_PATH" "${PYTHON[@]}" "$ORCHESTRATOR_PATH" zig-test --target system-test

# Phase 3: Cleanup
"${PYTHON[@]}" "$ORCHESTRATOR_PATH" llm-server-stop
