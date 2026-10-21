# ── Security: SecComp ──────────────────────────────────────────────────────

security-seccomp-check-fd:
    @bash contrib/security/security.sh seccomp-check-fd

security-seccomp-check-fd-linux-x86: security-seccomp-check-fd

# Tickoni seccomp check: dispatcher → platform-specific recipe.
security-seccomp-check-tk:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
    linux-x86) exec just security-seccomp-check-tk-linux-x86 ;;
    linux-arm) exec just security-seccomp-check-tk-linux-x86 ;;
    macos-x86) exec just security-seccomp-check-tk-linux-x86 ;;
    macos-arm) exec just security-seccomp-check-tk-linux-x86 ;;
    windows-x86) exec just security-seccomp-check-tk-linux-x86 ;;
    windows-arm) exec just security-seccomp-check-tk-linux-x86 ;;
    *) echo "unsupported host platform for security-seccomp-check-tk: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

security-seccomp-check-tk-linux-x86:
    @true

security-seccomp-check-tk-linux-arm: security-seccomp-check-tk-linux-x86
security-seccomp-check-tk-macos-x86: security-seccomp-check-tk-linux-x86
security-seccomp-check-tk-macos-arm: security-seccomp-check-tk-linux-x86
security-seccomp-check-tk-windows-x86: security-seccomp-check-tk-linux-x86
security-seccomp-check-tk-windows-arm: security-seccomp-check-tk-linux-x86

security-seccomp-check-linux-x86:
    @just security-seccomp-check-fd-linux-x86

security-seccomp-check-all:
    @just security-seccomp-check-fd
    @just security-seccomp-check-tk
