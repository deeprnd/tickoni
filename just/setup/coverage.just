# ── Setup: Coverage toolchain ──────────────────────────────────────────────
#
# Bare dispatcher auto-detects platform and routes to the correct recipe.

setup-coverage:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
      linux-x86) exec just setup-coverage-linux-x86-clang ;;
      linux-arm) echo "setup-coverage not available for linux-arm" >&2; exit 1 ;;
      macos-x86) exec just setup-coverage-macos-x86 ;;
      macos-arm) exec just setup-coverage-macos-arm ;;
      *) echo "unsupported host platform for setup-coverage: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

setup-coverage-linux-x86-clang:
    {{ python }} contrib/setup/orchestrator.py coverage,toolchain

setup-coverage-macos-x86:
    {{ python }} contrib/setup/orchestrator.py core,build,toolchain,coverage

setup-coverage-macos-arm:
    {{ python }} contrib/setup/orchestrator.py core,build,toolchain,coverage
