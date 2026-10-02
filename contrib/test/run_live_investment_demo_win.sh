#!/usr/bin/env bash
# End-to-end live investment demo (Windows): setup → start server → run tests → cleanup.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

# Windows target platform for the orchestrator (windows-x86 | windows-arm).
PLATFORM="${1:-windows-x86}"

# Phase 1: Setup via orchestrator (download llama.cpp + download model)
python contrib/setup/orchestrator.py llm-server --platform "$PLATFORM"

# Phase 2: Start llama.cpp server (infrastructure)
python contrib/test/orchestrator.py llm-server-start

# Phase 3: Run system test (test)
bash contrib/test/run_system_model_tests_win.sh

# Phase 4: Cleanup (stop server)
python contrib/test/orchestrator.py llm-server-stop
