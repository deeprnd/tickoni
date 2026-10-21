# ── Test: System recipes ─────────────────────────────────────────────────
# System tests: opt-in real-LLM investment demo proof.

# Tickoni system lane: dispatcher → platform-specific recipes.
test-system-tk:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
    linux-x86) exec just test-system-tk-linux-x86 ;;
    linux-arm) exec just test-system-tk-linux-x86 ;;
    macos-x86) exec just test-system-tk-linux-x86 ;;
    macos-arm) exec just test-system-tk-linux-x86 ;;
    windows-x86) exec just test-system-tk-windows-x86 ;;
    windows-arm) exec just test-system-tk-windows-arm ;;
    *) echo "unsupported host platform for test-system-tk: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

test-system-tk-linux-x86:
    bash contrib/test/run_live_investment_demo.sh

test-system-tk-linux-arm: test-system-tk-linux-x86
test-system-tk-macos-x86: test-system-tk-linux-x86
test-system-tk-macos-arm: test-system-tk-linux-x86

test-system-tk-windows-x86:
    bash contrib/test/run_live_investment_demo_win.sh windows-x86

test-system-tk-windows-arm:
    bash contrib/test/run_live_investment_demo_win.sh windows-arm

test-system-fd:
    @true

test-system-all:
    {{ python }} contrib/tool/readme/run-badged-command.py system bash -c "just test-system-tk && just test-system-fd"

# Infrastructure: ensure llama.cpp and model (for LLM system tests)
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

# Download the GGUF model for system tests (requires `hf` CLI).
infra-ensure-model:
    {{ python }} contrib/setup/orchestrator.py llm-server
