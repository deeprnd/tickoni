# ── Setup: Security/formal-verification (CBMC suite) recipes ───────────────

# Security/formal-verification (CBMC suite)
setup-security-linux-x86:
    {{ python }} contrib/setup/orchestrator.py core,security

setup-security-macos-x86:
    {{ python }} contrib/setup/orchestrator.py core,security

setup-security-windows-x86:
    {{ python }} contrib/setup/orchestrator.py core,security --platform windows-x86
