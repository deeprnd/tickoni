# ── Setup: Secrets/gitleaks ──────────────────────────────────────────────
# Gitleaks installation (no quality, no build tools beyond what gitleaks needs).
#
# Bare dispatcher auto-detects platform and routes to the correct recipe.

setup-gitleaks:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
      linux-x86) exec just setup-gitleaks-linux-x86 ;;
      linux-arm) echo "setup-gitleaks not available for linux-arm" >&2; exit 1 ;;
      macos-x86) exec just setup-gitleaks-macos-x86 ;;
      macos-arm) exec just setup-gitleaks-macos-arm ;;
      windows-x86) exec just setup-gitleaks-windows-x86 ;;
      windows-arm) exec just setup-gitleaks-windows-arm ;;
      *) echo "unsupported host platform for setup-gitleaks: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

# Secrets-only: gitleaks
setup-gitleaks-linux-x86:
    {{ python }} contrib/setup/orchestrator.py core,essential,secrets --platform {{ os }}-{{ arch }}

setup-gitleaks-macos-x86:
    {{ python }} contrib/setup/orchestrator.py core,essential,secrets --platform {{ os }}-{{ arch }}

setup-gitleaks-macos-arm:
    {{ python }} contrib/setup/orchestrator.py core,essential,secrets --platform {{ os }}-{{ arch }}

setup-gitleaks-windows-x86:
    {{ python }} contrib/setup/orchestrator.py core,essential,secrets --platform windows-x86

setup-gitleaks-windows-arm:
    {{ python }} contrib/setup/orchestrator.py core,essential,secrets --platform windows-arm
