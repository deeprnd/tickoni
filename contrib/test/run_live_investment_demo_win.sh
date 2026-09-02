#!/usr/bin/env bash
# End-to-end live investment demo (Windows): setup → start server → run tests → cleanup.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Phase 1: Setup via orchestrator (download llama.cpp + download model)
python "$(dirname "$SCRIPT_DIR")/setup/orchestrator.py" llm-server --platform windows-x86

# Phase 2: Start llama.cpp server (infrastructure)
python "$(dirname "$SCRIPT_DIR")/test/orchestrator.py" llm-server-start

# Phase 3: Run system test (test)
bash contrib/test/run_system_model_tests_win.sh

# Phase 4: Cleanup (stop server)
python "$(dirname "$SCRIPT_DIR")/test/orchestrator.py" llm-server-stop
