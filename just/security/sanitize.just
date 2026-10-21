# ── Security: ASan/UBSan ───────────────────────────────────────────────────

security-sanitize-check-fd:
    bash contrib/security/security.sh sanitize-check-fd

security-sanitize-check-fd-linux-x86: security-sanitize-check-fd

# Tickoni sanitize check: dispatcher → platform-specific recipe.
security-sanitize-check-tk:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
    linux-x86) exec just security-sanitize-check-tk-linux-x86 ;;
    linux-arm) exec just security-sanitize-check-tk-linux-x86 ;;
    macos-x86) exec just security-sanitize-check-tk-linux-x86 ;;
    macos-arm) exec just security-sanitize-check-tk-linux-x86 ;;
    windows-x86) exec just security-sanitize-check-tk-linux-x86 ;;
    windows-arm) exec just security-sanitize-check-tk-linux-x86 ;;
    *) echo "unsupported host platform for security-sanitize-check-tk: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

security-sanitize-check-tk-linux-x86:
    bash contrib/security/security.sh sanitize-check-tk

security-sanitize-check-tk-linux-arm: security-sanitize-check-tk-linux-x86
security-sanitize-check-tk-macos-x86: security-sanitize-check-tk-linux-x86
security-sanitize-check-tk-macos-arm: security-sanitize-check-tk-linux-x86
security-sanitize-check-tk-windows-x86: security-sanitize-check-tk-linux-x86
security-sanitize-check-tk-windows-arm: security-sanitize-check-tk-linux-x86

security-sanitize-check-linux-x86:
    @just security-sanitize-check-fd-linux-x86
    @just security-sanitize-check-tk-linux-x86

security-sanitize-check-qt:
    bash contrib/security/security.sh sanitize-check-qt

security-sanitize-check-qt-linux-x86: security-sanitize-check-qt

security-sanitize-check-all:
    @just security-sanitize-check-fd
    @just security-sanitize-check-tk
    @just security-sanitize-check-qt
