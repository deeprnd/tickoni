# ── Security: Engine ───────────────────────────────────────────────────────

security-engine-check-all:
    @just security-engine-check-changes
    @just security-engine-check-orchestration

security-engine-check-changes:
    {{ python }} contrib/quality/engine/engine_check_changes.py

security-engine-check-orchestration:
    {{ python }} contrib/quality/engine/linter.py --root {{ justfile_directory() }} --severity ERROR contrib/quality/engine/checks

security-engine-check-changes-linux-x86: security-engine-check-changes
security-engine-check-orchestration-linux-x86: security-engine-check-orchestration
