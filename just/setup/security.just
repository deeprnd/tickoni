# ── Setup: Security/formal-verification (CBMC suite) ───────────────────────
#
# Bare dispatcher auto-detects platform and routes to the correct recipe.

setup-security:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
      linux-x86) exec just setup-security-linux-x86 ;;
      macos-x86) exec just setup-security-macos-x86 ;;
      *) echo "unsupported host platform for setup-security: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

# Security/formal-verification (CBMC suite)
setup-security-linux-x86:
    {{ python }} contrib/setup/orchestrator.py core,security --platform {{ os }}-{{ arch }}

setup-security-macos-x86:
    {{ python }} contrib/setup/orchestrator.py core,security --platform {{ os }}-{{ arch }}

setup-security-windows-x86:
    {{ python }} contrib/setup/orchestrator.py core,security --platform windows-x86
