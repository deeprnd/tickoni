# ── Quality: Spell ─────────────────────────────────────────────────────────

quality-spell-check-linux:
    cspell lint --no-progress .

# Quality spell checker: dispatcher → platform-specific recipe.
quality-spell-check:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
    linux-x86) exec just quality-spell-check-linux-x86 ;;
    linux-arm) exec just quality-spell-check-linux-x86 ;;
    macos-x86) exec just quality-spell-check-linux-x86 ;;
    macos-arm) exec just quality-spell-check-linux-x86 ;;
    windows-x86) exec just quality-spell-check-linux-x86 ;;
    windows-arm) exec just quality-spell-check-linux-x86 ;;
    *) echo "unsupported host platform for quality-spell-check: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

quality-spell-check-linux-x86: quality-spell-check-linux

quality-spell-check-linux-arm: quality-spell-check-linux-x86
quality-spell-check-macos-x86: quality-spell-check-linux-x86
quality-spell-check-macos-arm: quality-spell-check-linux-x86
quality-spell-check-windows-x86: quality-spell-check-linux-x86
quality-spell-check-windows-arm: quality-spell-check-linux-x86

quality-spell-check-all:
    just quality-spell-check
