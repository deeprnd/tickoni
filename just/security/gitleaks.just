# ── Security: Gitleaks ─────────────────────────────────────────────────────

security-gitleaks-check-fd:
    bash contrib/security/security.sh gitleaks-check-fd

security-gitleaks-check-tk:
    bash contrib/security/security.sh gitleaks-check-tk

security-gitleaks-check-fd-linux-x86: security-gitleaks-check-fd
security-gitleaks-check-tk-linux-x86: security-gitleaks-check-tk

security-gitleaks-check-linux-x86:
    @just security-gitleaks-check-fd-linux-x86
    @just security-gitleaks-check-tk-linux-x86

security-gitleaks-check-all:
    @just security-gitleaks-check-fd
    @just security-gitleaks-check-tk
