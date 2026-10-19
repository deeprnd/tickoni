# ── Quality: All ───────────────────────────────────────────────────────────

quality-check-all:
    {{ python }} contrib/tool/readme/run-badged-command.py quality bash -c "just quality-format-check-all && just quality-lint-check-all && just quality-proto-check-all && just quality-yaml-check-all && just quality-spell-check-all"
