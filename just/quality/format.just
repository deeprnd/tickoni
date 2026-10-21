# ── Quality: Format ────────────────────────────────────────────────────────

quality-format-check-fd:
    bash contrib/quality/quality.sh format-check-fd

quality-format-fix-fd:
    bash contrib/quality/quality.sh format-fix-fd

quality-format-check-tk:
    bash contrib/quality/quality.sh format-check-tk

quality-format-fix-tk:
    bash contrib/quality/quality.sh format-fix-tk

# Linux/x86 qualified aliases
quality-format-check-fd-linux-x86: quality-format-check-fd
quality-format-fix-fd-linux-x86: quality-format-fix-fd
quality-format-check-tk-linux-x86: quality-format-check-tk
quality-format-fix-tk-linux-x86: quality-format-fix-tk

quality-format-check-linux-x86:
    @just quality-format-check-fd-linux-x86
    @just quality-format-check-tk-linux-x86

quality-format-check-all:
    @just quality-format-check-fd
    @just quality-format-check-tk

quality-format-fix-all:
    @just quality-format-fix-fd
    @just quality-format-fix-tk
