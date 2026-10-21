# ── Security: Proof ────────────────────────────────────────────────────────

security-proof-check-fd:
    bash contrib/security/security.sh proof-check-fd

security-proof-check-fd-linux-x86: security-proof-check-fd

# Tickoni proof check: dispatcher → platform-specific recipe.
security-proof-check-tk:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
    linux-x86) exec just security-proof-check-tk-linux-x86 ;;
    linux-arm) exec just security-proof-check-tk-linux-x86 ;;
    macos-x86) exec just security-proof-check-tk-linux-x86 ;;
    macos-arm) exec just security-proof-check-tk-linux-x86 ;;
    windows-x86) exec just security-proof-check-tk-linux-x86 ;;
    windows-arm) exec just security-proof-check-tk-linux-x86 ;;
    *) echo "unsupported host platform for security-proof-check-tk: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

security-proof-check-tk-linux-x86:
    @true

security-proof-check-tk-linux-arm: security-proof-check-tk-linux-x86
security-proof-check-tk-macos-x86: security-proof-check-tk-linux-x86
security-proof-check-tk-macos-arm: security-proof-check-tk-linux-x86
security-proof-check-tk-windows-x86: security-proof-check-tk-linux-x86
security-proof-check-tk-windows-arm: security-proof-check-tk-linux-x86

security-proof-check-linux-x86:
    @just security-proof-check-fd-linux-x86
    @just security-proof-check-tk-linux-x86

security-proof-check-all:
    @just security-proof-check-fd
    @just security-proof-check-tk
