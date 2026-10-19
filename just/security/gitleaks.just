# ── Security: Gitleaks ─────────────────────────────────────────────────────

security-gitleaks-check-fd:
    bash contrib/security/security.sh gitleaks-check-fd

security-gitleaks-check-fd-linux-x86: security-gitleaks-check-fd

# Tickoni gitleaks check: dispatcher → platform-specific recipe.
security-gitleaks-check-tk:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
    linux-x86) exec just security-gitleaks-check-tk-linux-x86 ;;
    linux-arm) exec just security-gitleaks-check-tk-linux-x86 ;;
    macos-x86) exec just security-gitleaks-check-tk-linux-x86 ;;
    macos-arm) exec just security-gitleaks-check-tk-linux-x86 ;;
    windows-x86) exec just security-gitleaks-check-tk-linux-x86 ;;
    windows-arm) exec just security-gitleaks-check-tk-linux-x86 ;;
    *) echo "unsupported host platform for security-gitleaks-check-tk: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

security-gitleaks-check-tk-linux-x86:
    bash contrib/security/security.sh gitleaks-check-tk

security-gitleaks-check-tk-linux-arm: security-gitleaks-check-tk-linux-x86
security-gitleaks-check-tk-macos-x86: security-gitleaks-check-tk-linux-x86
security-gitleaks-check-tk-macos-arm: security-gitleaks-check-tk-linux-x86
security-gitleaks-check-tk-windows-x86: security-gitleaks-check-tk-linux-x86
security-gitleaks-check-tk-windows-arm: security-gitleaks-check-tk-linux-x86

security-gitleaks-check-linux-x86:
    @just security-gitleaks-check-fd-linux-x86
    @just security-gitleaks-check-tk-linux-x86

security-gitleaks-check-all:
    @just security-gitleaks-check-fd
    @just security-gitleaks-check-tk
