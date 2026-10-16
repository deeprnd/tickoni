# ── Test: System recipes ─────────────────────────────────────────────────
# System tests: opt-in real-LLM investment demo proof.

# Tickoni system lane: opt-in real-LLM investment demo proof.
# Full end-to-end: setup (orchestrator.py llm-server) → start server → run tests → cleanup.
test-system-tk:
    bash contrib/test/run_live_investment_demo.sh

test-system-tk-linux-x86: test-system-tk
test-system-tk-macos-x86: test-system-tk
test-system-tk-macos-arm: test-system-tk

test-system-fd:
    @true

test-system-all:
    {{ python }} contrib/tool/readme/run-badged-command.py system bash -c "just test-system-tk && just test-system-fd"

test-system-tk-windows-x86:
    bash contrib/test/run_live_investment_demo_win.sh

test-system-tk-windows-arm: test-system-tk-windows-x86

# Infrastructure: ensure llama.cpp and model (for LLM system tests)
infra-ensure-llamacpp:
    {{ python }} contrib/setup/orchestrator.py llm-server

infra-ensure-llamacpp-win:
    {{ python }} contrib/setup/orchestrator.py llm-server --platform windows-x86

# Download the GGUF model for system tests (requires `hf` CLI).
infra-ensure-model:
    {{ python }} contrib/setup/orchestrator.py llm-server
