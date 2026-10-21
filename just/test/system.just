# ── Test: System recipes ─────────────────────────────────────────────────
# System tests: live-LLM investment tests via llama.cpp server.

test-system-tk:
    bash contrib/test/run_system_test.sh

test-system-tk-linux-x86:
    bash contrib/test/run_system_test.sh

test-system-tk-linux-arm: test-system-tk-linux-x86
test-system-tk-macos-x86: test-system-tk-linux-x86
test-system-tk-macos-arm: test-system-tk-linux-x86
test-system-tk-windows-x86:
    bash contrib/test/run_system_test.sh windows-x86
test-system-tk-windows-arm: test-system-tk-windows-x86

test-system-all:
    {{ python }} contrib/tool/readme/run-badged-command.py system bash -c "just test-system-tk"

infra-ensure-llamacpp:
    {{ python }} contrib/setup/orchestrator.py llm-server

infra-ensure-llamacpp-linux-x86:
    {{ python }} contrib/setup/orchestrator.py llm-server --platform linux-x86

infra-ensure-llamacpp-linux-arm:
    {{ python }} contrib/setup/orchestrator.py llm-server --platform linux-arm

infra-ensure-llamacpp-macos-x86:
    {{ python }} contrib/setup/orchestrator.py llm-server --platform macos-x86

infra-ensure-llamacpp-macos-arm:
    {{ python }} contrib/setup/orchestrator.py llm-server --platform macos-arm

infra-ensure-llamacpp-win-x86:
    {{ python }} contrib/setup/orchestrator.py llm-server --platform windows-x86

infra-ensure-llamacpp-win-arm:
    {{ python }} contrib/setup/orchestrator.py llm-server --platform windows-arm
