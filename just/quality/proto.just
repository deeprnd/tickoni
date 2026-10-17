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
