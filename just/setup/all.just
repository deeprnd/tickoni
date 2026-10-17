# ── Setup: Full developer environment ──────────────────────────────────────
# setup-all installs everything: core, essential, toolchain, build, zig, ssl,
# fd, quality, secrets, coverage, security, ops.
# setup-all delegates to orchestrator.py; bare dispatchers for each domain
# live in their own install-*.just files.

setup-all:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build,zig,ssl,fd,quality,secrets,coverage,security,ops
    just setup-git
