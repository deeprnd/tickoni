# ── Quality: Format ────────────────────────────────────────────────────────

quality-format-check-fd:
    bash contrib/quality/quality.sh format-check-fd

quality-format-fix-fd:
    bash contrib/quality/quality.sh format-fix-fd

quality-format-check-tk:
    bash contrib/quality/quality.sh format-check-tk

quality-format-fix-tk:
    bash contrib/quality/quality.sh format-fix-tk

# Linux/x86 qualified aliases; quality scope remains unchanged.
quality-format-check-fd-linux-x86: quality-format-check-fd
quality-format-fix-fd-linux-x86: quality-format-fix-fd
quality-format-check-tk-linux-x86: quality-format-check-tk
quality-format-fix-tk-linux-x86: quality-format-fix-tk

# macOS aliases (text-based, platform-independent)
quality-format-check-fd-macos-x86: quality-format-check-fd
quality-format-fix-fd-macos-x86: quality-format-fix-fd
quality-format-check-fd-macos-arm: quality-format-check-fd
quality-format-fix-fd-macos-arm: quality-format-fix-fd
quality-format-check-tk-macos-x86: quality-format-check-tk
quality-format-fix-tk-macos-x86: quality-format-fix-tk
quality-format-check-tk-macos-arm: quality-format-check-tk
quality-format-fix-tk-macos-arm: quality-format-fix-tk

# Windows aliases (text-based, platform-independent)
quality-format-check-fd-windows-x86: quality-format-check-fd
quality-format-fix-fd-windows-x86: quality-format-fix-fd
quality-format-check-fd-windows-arm: quality-format-check-fd
quality-format-fix-fd-windows-arm: quality-format-fix-fd
quality-format-check-tk-windows-x86: quality-format-check-tk
quality-format-fix-tk-windows-x86: quality-format-fix-tk
quality-format-check-tk-windows-arm: quality-format-check-tk
quality-format-fix-tk-windows-arm: quality-format-fix-tk

# Linux alias for combined check
quality-format-check-linux-x86:
    @just quality-format-check-fd-linux-x86
    @just quality-format-check-tk-linux-x86

quality-format-check-all:
    @just quality-format-check-fd
    @just quality-format-check-tk
    @just quality-format-check-qt

quality-format-fix-all:
    @just quality-format-fix-fd
    @just quality-format-fix-tk
    @just quality-format-fix-qt

# ── Quality: Format Qt ──────────────────────────────────────────────────────

quality-format-check-qt:
    bash contrib/quality/quality.sh format-check-qt

quality-format-fix-qt:
    bash contrib/quality/quality.sh format-fix-qt

quality-format-check-qt-linux-x86: quality-format-check-qt
quality-format-fix-qt-linux-x86: quality-format-fix-qt

# macOS Qt aliases
quality-format-check-qt-macos-x86: quality-format-check-qt
quality-format-fix-qt-macos-x86: quality-format-fix-qt
quality-format-check-qt-macos-arm: quality-format-check-qt
quality-format-fix-qt-macos-arm: quality-format-fix-qt

# Windows Qt aliases
quality-format-check-qt-windows-x86: quality-format-check-qt
quality-format-fix-qt-windows-x86: quality-format-fix-qt
quality-format-check-qt-windows-arm: quality-format-check-qt
quality-format-fix-qt-windows-arm: quality-format-fix-qt

# ── Quality: Lint ──────────────────────────────────────────────────────────

quality-lint-check-fd:
    bash contrib/quality/quality.sh lint-check-fd
    command -v shellcheck >/dev/null || exit 0; bash contrib/quality/quality.sh lint-shellcheck-fd

quality-lint-check-actions:
    @command -v actionlint >/dev/null || exit 0; actionlint -ignore 'label "windows-11-vs2026-arm" is unknown' .github/workflows/*.yml

quality-lint-check-tk:
    bash contrib/quality/quality.sh lint-check-tk

quality-lint-check-fd-linux-x86: quality-lint-check-fd
quality-lint-check-tk-linux-x86: quality-lint-check-tk

# macOS lint aliases
quality-lint-check-fd-macos-x86: quality-lint-check-fd
quality-lint-check-tk-macos-x86: quality-lint-check-tk
quality-lint-check-fd-macos-arm: quality-lint-check-fd
quality-lint-check-tk-macos-arm: quality-lint-check-tk

# Windows lint aliases
quality-lint-check-fd-windows-x86: quality-lint-check-fd
quality-lint-check-tk-windows-x86: quality-lint-check-tk
quality-lint-check-fd-windows-arm: quality-lint-check-fd
quality-lint-check-tk-windows-arm: quality-lint-check-tk

quality-lint-check-linux-x86:
    @just quality-lint-check-fd-linux-x86
    @just quality-lint-check-tk-linux-x86

quality-lint-check-all:
    @just quality-lint-check-fd
    @just quality-lint-check-tk
    @just quality-lint-check-actions
    @just quality-lint-check-qt

# ── Quality: Lint Qt ────────────────────────────────────────────────────────

quality-lint-check-qt:
    bash contrib/quality/quality.sh lint-check-qt

quality-lint-check-qt-linux-x86: quality-lint-check-qt

# macOS Qt lint alias
quality-lint-check-qt-macos-x86: quality-lint-check-qt
quality-lint-check-qt-macos-arm: quality-lint-check-qt

# Windows Qt lint alias
quality-lint-check-qt-windows-x86: quality-lint-check-qt
quality-lint-check-qt-windows-arm: quality-lint-check-qt

quality-yaml-check-linux:
    find . -name '*.yaml' -o -name '*.yml' | grep -vE '^(./opt|./node_modules|./.zig-global-cache|./build|./target|./zig-out|\\.git)/' | xargs yamllint -f parsable

quality-spell-check-linux:
    cspell lint --no-progress .

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

# macOS proto aliases
quality-proto-check-fd-macos-x86: quality-proto-check-fd
quality-proto-check-tk-macos-x86: quality-proto-check-tk
quality-proto-check-fd-macos-arm: quality-proto-check-fd
quality-proto-check-tk-macos-arm: quality-proto-check-tk

# Windows proto aliases
quality-proto-check-fd-windows-x86: quality-proto-check-fd
quality-proto-check-tk-windows-x86: quality-proto-check-tk
quality-proto-check-fd-windows-arm: quality-proto-check-fd
quality-proto-check-tk-windows-arm: quality-proto-check-tk

quality-proto-check-linux-x86:
    @just quality-proto-check-fd-linux-x86
    @just quality-proto-check-tk-linux-x86

quality-proto-check-all:
    @just quality-proto-check-fd
    @just quality-proto-check-tk

# ── Quality: All ───────────────────────────────────────────────────────────

quality-check-all:
    {{ python }} contrib/tool/readme/run-badged-command.py quality bash -c "just quality-format-check-all && just quality-lint-check-all && just quality-proto-check-all && just quality-yaml-check-linux && just quality-spell-check-linux"
