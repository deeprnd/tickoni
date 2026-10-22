# ── Setup: Quality recipes ─────────────────────────────────────────────────
# Quality tool installation (shellcheck, actionlint, yamllint, pre-commit, buf + go).
#
# Bare dispatcher auto-detects platform and routes to the correct recipe.

setup-quality:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
      linux-x86) exec just setup-quality-linux-x86 ;;
      linux-arm) exec just setup-quality-linux-x86 ;;
      macos-x86) exec just setup-quality-macos-x86 ;;
      macos-arm) exec just setup-quality-macos-arm ;;
      windows-x86) exec just setup-quality-windows-x86 ;;
      windows-arm) exec just setup-quality-windows-arm ;;
      *) echo "unsupported host platform for setup-quality: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

# Quality: build + quality tools
setup-quality-linux-x86:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build --platform {{ os }}-{{ arch }}
    {{ python }} contrib/setup/orchestrator.py quality --platform {{ os }}-{{ arch }}

setup-quality-macos-x86:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build --platform {{ os }}-{{ arch }}
    {{ python }} contrib/setup/orchestrator.py quality --platform {{ os }}-{{ arch }}

setup-quality-macos-arm:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build --platform {{ os }}-{{ arch }}
    {{ python }} contrib/setup/orchestrator.py quality --platform {{ os }}-{{ arch }}

setup-quality-windows-x86:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build --platform {{ os }}-{{ arch }}
    {{ python }} contrib/setup/orchestrator.py quality --platform {{ os }}-{{ arch }}

setup-quality-windows-arm:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build --platform {{ os }}-{{ arch }}
    {{ python }} contrib/setup/orchestrator.py quality --platform {{ os }}-{{ arch }}
