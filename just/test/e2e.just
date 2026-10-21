# ── Test: E2E recipes ───────────────────────────────────────────────────
# E2E lanes (currently no-op placeholders).

test-e2e-fd:
    @true

# Tickoni E2E lane: dispatcher → platform-specific recipes.
test-e2e-tk:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
    linux-x86) exec just test-e2e-tk-linux-x86 ;;
    linux-arm) exec just test-e2e-tk-linux-x86 ;;
    macos-x86) exec just test-e2e-tk-macos-x86 ;;
    macos-arm) exec just test-e2e-tk-macos-arm ;;
    windows-x86) exec just test-e2e-tk-windows-x86 ;;
    windows-arm) exec just test-e2e-tk-windows-arm ;;
    *) echo "unsupported host platform for test-e2e-tk: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

test-e2e-tk-linux-x86:
    @true
test-e2e-tk-linux-arm: test-e2e-tk-linux-x86
test-e2e-tk-macos-x86: test-e2e-tk-linux-x86
test-e2e-tk-macos-arm: test-e2e-tk-linux-x86
test-e2e-tk-windows-x86: test-e2e-tk-linux-x86
test-e2e-tk-windows-arm: test-e2e-tk-linux-x86

test-e2e-all:
    {{ python }} contrib/tool/readme/run-badged-command.py e2e bash -c "just test-e2e-fd && just test-e2e-tk"
