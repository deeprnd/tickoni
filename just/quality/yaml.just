# ── Quality: YAML ──────────────────────────────────────────────────────────

quality-yaml-check-linux:
    find . -name '*.yaml' -o -name '*.yml' | grep -vE '^(./opt|./node_modules|./build/.zig-global-cache|./build|./target|./zig-out|\\.git)/' | xargs -r yamllint -f parsable

# Quality YAML checker: dispatcher → platform-specific recipe.
quality-yaml-check:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
    linux-x86) exec just quality-yaml-check-linux-x86 ;;
    linux-arm) exec just quality-yaml-check-linux-x86 ;;
    macos-x86) exec just quality-yaml-check-linux-x86 ;;
    macos-arm) exec just quality-yaml-check-linux-x86 ;;
    windows-x86) exec just quality-yaml-check-linux-x86 ;;
    windows-arm) exec just quality-yaml-check-linux-x86 ;;
    *) echo "unsupported host platform for quality-yaml-check: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

quality-yaml-check-linux-x86: quality-yaml-check-linux

quality-yaml-check-linux-arm: quality-yaml-check-linux-x86
quality-yaml-check-macos-x86: quality-yaml-check-linux-x86
quality-yaml-check-macos-arm: quality-yaml-check-linux-x86
quality-yaml-check-windows-x86: quality-yaml-check-linux-x86
quality-yaml-check-windows-arm: quality-yaml-check-linux-x86

quality-yaml-check-all:
    {{ python }} contrib/tool/readme/run-badged-command.py quality-yaml bash -c "just quality-yaml-check"
