# ── Quality: Lint ──────────────────────────────────────────────────────────

quality-lint-check-fd:
    bash contrib/quality/quality.sh lint-check-fd
    command -v shellcheck >/dev/null || exit 0; bash contrib/quality/quality.sh lint-shellcheck-fd

quality-lint-check-tk:
    bash contrib/quality/quality.sh lint-check-tk

quality-lint-check-fd-linux-x86: quality-lint-check-fd
quality-lint-check-tk-linux-x86: quality-lint-check-tk

quality-lint-check-linux-x86:
    @just quality-lint-check-fd-linux-x86
    @just quality-lint-check-tk-linux-x86

quality-lint-check-all:
    @just quality-lint-check-fd
    @just quality-lint-check-tk
