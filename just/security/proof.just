# ── Security: Proof ────────────────────────────────────────────────────────

security-proof-check-fd:
    bash contrib/security/security.sh proof-check-fd

security-proof-check-tk:
    @true

security-proof-check-fd-linux-x86: security-proof-check-fd
security-proof-check-tk-linux-x86: security-proof-check-tk

security-proof-check-linux-x86:
    @just security-proof-check-fd-linux-x86
    @just security-proof-check-tk-linux-x86

security-proof-check-all:
    @just security-proof-check-fd
    @just security-proof-check-tk
