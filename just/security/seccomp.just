# ── Security: SecComp ──────────────────────────────────────────────────────

security-seccomp-check-fd:
    @bash contrib/security/security.sh seccomp-check-fd

security-seccomp-check-tk:
    @true

security-seccomp-check-fd-linux-x86: security-seccomp-check-fd
security-seccomp-check-tk-linux-x86: security-seccomp-check-tk

security-seccomp-check-linux-x86: security-seccomp-check-fd-linux-x86

security-seccomp-check-all:
    @just security-seccomp-check-fd
    @just security-seccomp-check-tk
