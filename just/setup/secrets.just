# ── Setup: Secrets/gitleaks recipes ──────────────────────────────────────
# Gitleaks installation (no quality, no build tools beyond what gitleaks needs).

# Secrets-only: gitleaks
setup-gitleaks-linux-x86:
    {{ python }} contrib/setup/orchestrator.py core,essential,secrets

setup-gitleaks-macos-x86:
    {{ python }} contrib/setup/orchestrator.py core,essential,secrets

setup-gitleaks-macos-arm:
    {{ python }} contrib/setup/orchestrator.py core,essential,secrets

setup-gitleaks-windows-x86:
    {{ python }} contrib/setup/orchestrator.py core,essential,secrets --platform windows-x86

setup-gitleaks-windows-arm:
    {{ python }} contrib/setup/orchestrator.py core,essential,secrets --platform windows-arm
