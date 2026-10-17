# ── Security: All ──────────────────────────────────────────────────────────

security-check-all:
    {{ python }} contrib/tool/readme/run-badged-command.py security bash -c "just security-engine-check-all && just security-codeql-check-all && just security-gitleaks-check-all && just security-seccomp-check-all && just security-proof-check-all && just security-sanitize-check-all"
