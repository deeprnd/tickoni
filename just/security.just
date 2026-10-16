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

# ── Security: Engine ───────────────────────────────────────────────────────

security-engine-check-all:
    @just security-engine-check-changes
    @just security-engine-check-orchestration

security-engine-check-changes:
    {{ python }} contrib/quality/engine/engine_check_changes.py

security-engine-check-orchestration:
    {{ python }} contrib/quality/engine/linter.py --root {{ justfile_directory() }} --severity ERROR

security-engine-check-changes-linux-x86: security-engine-check-changes
security-engine-check-orchestration-linux-x86: security-engine-check-orchestration

# ── Security: All ──────────────────────────────────────────────────────────

security-check-all:
    {{ python }} contrib/tool/readme/run-badged-command.py security bash -c "just security-engine-check-all && just security-codeql-check-all && just security-gitleaks-check-all && just security-seccomp-check-all && just security-proof-check-all && just security-sanitize-check-all"
