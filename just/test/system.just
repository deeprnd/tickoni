# Test: System and E2E recipes

# Tickoni system lane: opt-in real-LLM investment demo proof.
# Full end-to-end: setup (orchestrator.py llm-server) → start server → run tests → cleanup.
test-system-tk:
    bash ../../contrib/test/run_live_investment_demo.sh

test-system-tk-linux-x86: test-system-tk
test-system-tk-linux-arm: test-system-tk
test-system-tk-macos-x86: test-system-tk
test-system-tk-macos-arm: test-system-tk

test-system-fd:
    @true

test-system-all:
    {{ python }} ../../contrib/tool/readme/run-badged-command.py system bash -c "just test-system-tk && just test-system-fd"

# Infrastructure: ensure llama.cpp and model (for LLM system tests)

# Build llama.cpp and download model using orchestrator.py (CPU only).
infra-ensure-llamacpp:
    python3 ../../contrib/setup/orchestrator.py llm-server

infra-ensure-llamacpp-win:
    {{ python }} ../../contrib/setup/orchestrator.py llm-server --platform windows-x86

infra-ensure-llamacpp-win-arm:
    {{ python }} ../../contrib/setup/orchestrator.py llm-server --platform windows-arm

# Download the GGUF model for system tests (requires `hf` CLI).
# (hf-model is handled by orchestrator.py llm-server; kept for explicitness.)
infra-ensure-model:
    python3 ../../contrib/setup/orchestrator.py llm-server
