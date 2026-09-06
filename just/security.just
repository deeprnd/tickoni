# ── Security: CodeQL ───────────────────────────────────────────────────────

security-codeql-check-fd:
    @true ## bash contrib/security/security.sh codeql-check-fd, opened issue https://github.com/firedancer-io/firedancer/issues/10058

security-codeql-check-tk:
    @true

security-codeql-check-fd-linux-x86: security-codeql-check-fd
security-codeql-check-tk-linux-x86: security-codeql-check-tk

# macOS stubs (CodeQL not installed on macOS runners)
security-codeql-check-fd-macos-x86:
    @true
security-codeql-check-fd-macos-arm:
    @true
security-codeql-check-tk-macos-x86:
    @true
security-codeql-check-tk-macos-arm:
    @true
security-codeql-check-qt-macos-x86:
    @true
security-codeql-check-qt-macos-arm:
    @true

# Windows stubs
security-codeql-check-fd-windows-x86:
    @true
security-codeql-check-fd-windows-arm:
    @true
security-codeql-check-tk-windows-x86:
    @true
security-codeql-check-tk-windows-arm:
    @true
security-codeql-check-qt-windows-x86:
    @true
security-codeql-check-qt-windows-arm:
    @true

security-codeql-check-all:
    @just security-codeql-check-fd
    @just security-codeql-check-tk
    @just security-codeql-check-qt

# ── Security: Gitleaks ─────────────────────────────────────────────────────

security-gitleaks-check-fd:
    bash contrib/security/security.sh gitleaks-check-fd

security-gitleaks-check-tk:
    bash contrib/security/security.sh gitleaks-check-tk

security-gitleaks-check-fd-linux-x86: security-gitleaks-check-fd
security-gitleaks-check-tk-linux-x86: security-gitleaks-check-tk

# macOS (gitleaks is a portable binary)
security-gitleaks-check-fd-macos-x86: security-gitleaks-check-fd
security-gitleaks-check-tk-macos-x86: security-gitleaks-check-tk
security-gitleaks-check-fd-macos-arm: security-gitleaks-check-fd
security-gitleaks-check-tk-macos-arm: security-gitleaks-check-tk

# Windows (gitleaks is a portable binary)
security-gitleaks-check-fd-windows-x86: security-gitleaks-check-fd
security-gitleaks-check-tk-windows-x86: security-gitleaks-check-tk
security-gitleaks-check-fd-windows-arm: security-gitleaks-check-fd
security-gitleaks-check-tk-windows-arm: security-gitleaks-check-tk

security-gitleaks-check-linux-x86:
    @just security-gitleaks-check-fd-linux-x86
    @just security-gitleaks-check-tk-linux-x86

security-gitleaks-check-all:
    @just security-gitleaks-check-fd
    @just security-gitleaks-check-tk
    @just security-gitleaks-check-qt

# ── Security: Gitleaks Qt ───────────────────────────────────────────────────

security-gitleaks-check-qt:
    bash contrib/security/security.sh gitleaks-check-qt

security-gitleaks-check-qt-linux-x86: security-gitleaks-check-qt

# macOS Qt
security-gitleaks-check-qt-macos-x86: security-gitleaks-check-qt
security-gitleaks-check-qt-macos-arm: security-gitleaks-check-qt

# Windows Qt
security-gitleaks-check-qt-windows-x86: security-gitleaks-check-qt
security-gitleaks-check-qt-windows-arm: security-gitleaks-check-qt

# ── Security: SecComp ──────────────────────────────────────────────────────

security-seccomp-check-fd:
    @bash contrib/security/security.sh seccomp-check-fd

security-seccomp-check-tk:
    @true

security-seccomp-check-fd-linux-x86: security-seccomp-check-fd
security-seccomp-check-tk-linux-x86: security-seccomp-check-tk

# macOS stubs (seccomp is Linux-only)
security-seccomp-check-fd-macos-x86:
    @true
security-seccomp-check-fd-macos-arm:
    @true
security-seccomp-check-tk-macos-x86:
    @true
security-seccomp-check-tk-macos-arm:
    @true
security-seccomp-check-qt-macos-x86:
    @true
security-seccomp-check-qt-macos-arm:
    @true

# Windows stubs
security-seccomp-check-fd-windows-x86:
    @true
security-seccomp-check-fd-windows-arm:
    @true
security-seccomp-check-tk-windows-x86:
    @true
security-seccomp-check-tk-windows-arm:
    @true
security-seccomp-check-qt-windows-x86:
    @true
security-seccomp-check-qt-windows-arm:
    @true

security-seccomp-check-linux-x86: security-seccomp-check-fd-linux-x86

security-seccomp-check-all:
    @just security-seccomp-check-fd
    @just security-seccomp-check-tk
    @just security-seccomp-check-qt

# ── Security: SecComp Qt (no-op) ───────────────────────────────────────────

security-seccomp-check-qt:
    @true ## N/A — Qt terminal is not in the financial event path

security-seccomp-check-qt-linux-x86: security-seccomp-check-qt

# ── Security: Proof ────────────────────────────────────────────────────────

security-proof-check-fd:
    bash contrib/security/security.sh proof-check-fd

security-proof-check-tk:
    @true

security-proof-check-fd-linux-x86: security-proof-check-fd
security-proof-check-tk-linux-x86: security-proof-check-tk

# macOS stubs (CBMC/proof is Linux-only)
security-proof-check-fd-macos-x86:
    @true
security-proof-check-fd-macos-arm:
    @true
security-proof-check-tk-macos-x86:
    @true
security-proof-check-tk-macos-arm:
    @true
security-proof-check-qt-macos-x86:
    @true
security-proof-check-qt-macos-arm:
    @true

# Windows stubs
security-proof-check-fd-windows-x86:
    @true
security-proof-check-fd-windows-arm:
    @true
security-proof-check-tk-windows-x86:
    @true
security-proof-check-tk-windows-arm:
    @true
security-proof-check-qt-windows-x86:
    @true
security-proof-check-qt-windows-arm:
    @true

security-proof-check-linux-x86:
    @just security-proof-check-fd-linux-x86
    @just security-proof-check-tk-linux-x86

security-proof-check-all:
    @just security-proof-check-fd
    @just security-proof-check-tk
    @just security-proof-check-qt

# ── Security: Proof Qt (no-op) ──────────────────────────────────────────────

security-proof-check-qt:
    @true ## N/A — no CBMC formal verification for Qt

security-proof-check-qt-linux-x86: security-proof-check-qt

# ── Security: ASan/UBSan ───────────────────────────────────────────────────

security-sanitize-check-fd:
    bash contrib/security/security.sh sanitize-check-fd

security-sanitize-check-tk:
    bash contrib/security/security.sh sanitize-check-tk

security-sanitize-check-fd-linux-x86: security-sanitize-check-fd
security-sanitize-check-tk-linux-x86: security-sanitize-check-tk

# macOS stubs (sanitize checks are Linux-only in CI)
security-sanitize-check-fd-macos-x86:
    @true
security-sanitize-check-fd-macos-arm:
    @true
security-sanitize-check-tk-macos-x86:
    @true
security-sanitize-check-tk-macos-arm:
    @true
security-sanitize-check-qt-macos-x86:
    @true
security-sanitize-check-qt-macos-arm:
    @true

# Windows stubs
security-sanitize-check-fd-windows-x86:
    @true
security-sanitize-check-fd-windows-arm:
    @true
security-sanitize-check-tk-windows-x86:
    @true
security-sanitize-check-tk-windows-arm:
    @true
security-sanitize-check-qt-windows-x86:
    @true
security-sanitize-check-qt-windows-arm:
    @true

security-sanitize-check-linux-x86:
    @just security-sanitize-check-fd-linux-x86
    @just security-sanitize-check-tk-linux-x86

security-sanitize-check-all:
    @just security-sanitize-check-fd
    @just security-sanitize-check-tk
    @just security-sanitize-check-qt

# ── Security: ASan/UBSan Qt ─────────────────────────────────────────────────

security-sanitize-check-qt:
    bash contrib/security/security.sh sanitize-check-qt

security-sanitize-check-qt-linux-x86: security-sanitize-check-qt

# ── Security: Engine ──────────────────────────────────────────────────────

security-engine-check-all:
    @just security-engine-check-changes
    @just security-engine-check-orchestration

security-engine-check-changes:
    {{ python }} contrib/quality/engine/engine_check_changes.py

security-engine-check-orchestration:
    {{ python }} contrib/quality/engine/linter.py contrib/quality/engine/checks/ --root {{ justfile_directory() }} --severity ERROR

security-engine-check-changes-linux-x86: security-engine-check-changes
security-engine-check-orchestration-linux-x86: security-engine-check-orchestration

# macOS/Windows stubs (engine checks reference Linux paths)
security-engine-check-changes-macos-x86:
    @true
security-engine-check-changes-macos-arm:
    @true
security-engine-check-orchestration-macos-x86:
    @true
security-engine-check-orchestration-macos-arm:
    @true
security-engine-check-changes-windows-x86:
    @true
security-engine-check-changes-windows-arm:
    @true
security-engine-check-orchestration-windows-x86:
    @true
security-engine-check-orchestration-windows-arm:
    @true

# ── Security: All ──────────────────────────────────────────────────────────

security-check-all:
    {{ python }} contrib/tool/readme/run-badged-command.py security bash -c "just security-engine-check-all && just security-codeql-check-all && just security-gitleaks-check-all && just security-seccomp-check-all && just security-proof-check-all && just security-sanitize-check-all"
