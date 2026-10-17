# ── Security: ASan/UBSan ───────────────────────────────────────────────────

security-sanitize-check-fd:
    bash contrib/security/security.sh sanitize-check-fd

security-sanitize-check-tk:
    bash contrib/security/security.sh sanitize-check-tk

security-sanitize-check-fd-linux-x86: security-sanitize-check-fd
security-sanitize-check-tk-linux-x86: security-sanitize-check-tk

security-sanitize-check-linux-x86:
    @just security-sanitize-check-fd-linux-x86
    @just security-sanitize-check-tk-linux-x86

security-sanitize-check-all:
    @just security-sanitize-check-fd
    @just security-sanitize-check-tk
