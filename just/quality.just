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

# ── Quality: Proto ─────────────────────────────────────────────────────────

quality-proto-check-fd:
    @cd src/disco/events && {{ python }} gen_events.py --skip-check
    @PATH="${HOME}/go/bin:/usr/local/go/bin:${PATH}" command -v buf >/dev/null || { if [ -n "$(git status --porcelain src/disco/events/generated/ src/disco/events/schema/events.proto)" ]; then echo "Generated proto files are out of date. Please run 'just quality-proto-check-fd' and commit the changes." >&2; git --no-pager diff -- src/disco/events/; exit 1; fi; exit 0; }
    PATH="${HOME}/go/bin:/usr/local/go/bin:${PATH}" buf lint src/disco/events/schema
    @if [ -n "$(git status --porcelain src/disco/events/generated/ src/disco/events/schema/events.proto)" ]; then echo "Generated proto files are out of date. Please run 'just quality-proto-check-fd' and commit the changes." >&2; git --no-pager diff -- src/disco/events/; exit 1; fi

quality-proto-check-tk:
    bash -c 'PATH="${HOME}/go/bin:/usr/local/go/bin:${PATH}"; command -v buf >/dev/null || exit 0; buf lint src/tickoni/schema'

quality-proto-check-fd-linux-x86: quality-proto-check-fd
quality-proto-check-tk-linux-x86: quality-proto-check-tk

quality-proto-check-linux-x86:
    @just quality-proto-check-fd-linux-x86
    @just quality-proto-check-tk-linux-x86

quality-proto-check-all:
    @just quality-proto-check-fd
    @just quality-proto-check-tk

# ── Quality: YAML ──────────────────────────────────────────────────────────

quality-yaml-check-linux:
    find . -name '*.yaml' -o -name '*.yml' | grep -vE '^(./opt|./node_modules|./build/.zig-global-cache|./build|./target|./zig-out|\\.git)/' | xargs -r yamllint -f parsable

# ── Quality: Spell ─────────────────────────────────────────────────────────

quality-spell-check-linux:
    cspell lint --no-progress .

# ── Quality: All ───────────────────────────────────────────────────────────

quality-check-all:
    {{ python }} contrib/tool/readme/run-badged-command.py quality bash -c "just quality-format-check-all && just quality-lint-check-all && just quality-proto-check-all && just quality-yaml-check-linux && just quality-spell-check-linux"
