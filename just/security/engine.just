# ── Security: Engine ───────────────────────────────────────────────────────

# Tickoni engine check: dispatcher → platform-specific recipe.
security-engine-check-tk:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
    linux-x86) exec just security-engine-check-tk-linux-x86 ;;
    linux-arm) exec just security-engine-check-tk-linux-x86 ;;
    macos-x86) exec just security-engine-check-tk-linux-x86 ;;
    macos-arm) exec just security-engine-check-tk-linux-x86 ;;
    windows-x86) exec just security-engine-check-tk-linux-x86 ;;
    windows-arm) exec just security-engine-check-tk-linux-x86 ;;
    *) echo "unsupported host platform for security-engine-check-tk: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

security-engine-check-tk-linux-x86:
    {{ python }} contrib/quality/engine/engine_check_changes.py
    {{ python }} contrib/quality/engine/linter.py --root {{ justfile_directory() }} --severity ERROR contrib/quality/engine/checks

security-engine-check-tk-linux-arm: security-engine-check-tk-linux-x86
security-engine-check-tk-macos-x86: security-engine-check-tk-linux-x86
security-engine-check-tk-macos-arm: security-engine-check-tk-linux-x86
security-engine-check-tk-windows-x86: security-engine-check-tk-linux-x86
security-engine-check-tk-windows-arm: security-engine-check-tk-linux-x86

# Aggregator calls dispatcher (which dispatches to platform recipe).
security-engine-check-all:
    @just security-engine-check-tk
