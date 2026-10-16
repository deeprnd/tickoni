# ── Setup: Qt 6 installation (for Qt terminal) recipes ──────────────────────
# Credentials from .env file (local) or GitHub secrets (CI).
# Local: copy .env.example → .env and fill in QT_USERNAME and QT_PASSWORD
# CI: set QT_USERNAME and QT_PASSWORD as repository secrets
#   → they propagate to the runner env automatically.
# Note: orchestrator.py automatically loads .env when present.

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
