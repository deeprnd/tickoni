#!/usr/bin/env bash
# End-to-end live investment demo: setup → start server → run tests → cleanup.
# This replaces the old monolithic run_system_model_tests.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Phase 1: Setup via orchestrator (download llama.cpp + download model)
python3 "$(dirname "$SCRIPT_DIR")/setup/orchestrator.py" llm-server

# Phase 2: Start llama.cpp server (infrastructure)
python3 "$(dirname "$SCRIPT_DIR")/test/orchestrator.py" llm-server-start

# Phase 3: Run system test (test)
bash contrib/test/run_system_model_tests.sh

# Phase 4: Cleanup (stop server)
python3 "$(dirname "$SCRIPT_DIR")/test/orchestrator.py" llm-server-stop
