# ── Security: CodeQL ───────────────────────────────────────────────────────

security-codeql-check-fd:
    @true ## bash contrib/security/security.sh codeql-check-fd, opened issue https://github.com/firedancer-io/firedancer/issues/10058

security-codeql-check-tk:
    @true

security-codeql-check-fd-linux-x86: security-codeql-check-fd
security-codeql-check-tk-linux-x86: security-codeql-check-tk

security-codeql-check-all:
    @just security-codeql-check-fd
    @just security-codeql-check-tk
