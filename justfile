# ── Variables ──────────────────────────────────────────────────────────────
include "just/vars.just"

# ── Setup ─────────────────────────────────────────────────────────────────
include "just/setup/install-build.just"
include "just/setup/install-fd.just"
include "just/setup/install-coverage.just"
include "just/setup/install-zig.just"
include "just/setup/install-just.just"
include "just/setup/install-env.just"
include "just/setup/install-git.just"
include "just/setup/dev-setup.just"
include "just/setup/qt.just"
include "just/setup/quality.just"
include "just/setup/secrets.just"
include "just/setup/security.just"

# ── Build ─────────────────────────────────────────────────────────────────
include "just/build/all.just"
include "just/build/build-fd.just"
include "just/build/build-qt.just"
include "just/build/build-tk.just"

# ── Test ───────────────────────────────────────────────────────────────────
include "just/test/all.just"
include "just/test/coverage.just"
include "just/test/demo.just"
include "just/test/e2e.just"
include "just/test/integration.just"
include "just/test/perf.just"
include "just/test/system.just"
include "just/test/unit.just"

# ── Quality and Security ──────────────────────────────────────────────────
include "just/quality.just"
include "just/security.just"

# ── System ─────────────────────────────────────────────────────────────────
include "just/system.mem.just"

# ── Default ────────────────────────────────────────────────────────────────
default:
    @just --list

# ── Super-aggregator ───────────────────────────────────────────────────────
tests-all:
    @just build-all
    @just quality-format-check-all
    @just quality-lint-check-tk
    @just quality-proto-check-all
    @just security-check-all
    @just security-engine-check-changes
    @just test-all
