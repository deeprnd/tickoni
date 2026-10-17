# ── Setup: Qt 6 installation (for Qt terminal) recipes ──────────────────────
# Credentials from .env file (local) or GitHub secrets (CI).
# Local: copy .env.example → .env and fill in QT_USERNAME and QT_PASSWORD
# CI: set QT_USERNAME and QT_PASSWORD as repository secrets
#   → they propagate to the runner env automatically.
# Note: orchestrator.py automatically loads .env when present.
#
# Bare dispatcher auto-detects platform and routes to the correct recipe.

setup-qt:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
      linux-x86) exec just setup-qt-linux-x86 ;;
      linux-arm) exec just setup-qt-linux-arm ;;
      macos-x86) exec just setup-qt-macos-x86 ;;
      macos-arm) exec just setup-qt-macos-arm ;;
      windows-x86) exec just setup-qt-windows-x86 ;;
      windows-arm) exec just setup-qt-windows-arm ;;
      *) echo "unsupported host platform for setup-qt: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

setup-qt-linux-x86:
    {{ python }} contrib/setup/orchestrator.py qt --platform linux-x86

setup-qt-linux-arm:
    {{ python }} contrib/setup/orchestrator.py qt --platform linux-arm

setup-qt-macos-x86:
    {{ python }} contrib/setup/orchestrator.py qt --platform macos-x86

setup-qt-macos-arm:
    {{ python }} contrib/setup/orchestrator.py qt --platform macos-arm

setup-qt-windows-x86:
    {{ python }} contrib/setup/orchestrator.py qt --platform windows-x86

setup-qt-windows-arm:
    {{ python }} contrib/setup/orchestrator.py qt --platform windows-arm
