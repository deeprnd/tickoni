# ── Variables ──────────────────────────────────────────────────────────────
import "just/vars.just"

# ── Setup ─────────────────────────────────────────────────────────────────
import "just/setup/install-build.just"
import "just/setup/install-fd.just"
import "just/setup/install-coverage.just"
import "just/setup/install-zig.just"
import "just/setup/install-just.just"
import "just/setup/install-env.just"
import "just/setup/install-git.just"
import "just/setup/install-qt.just"
import "just/setup/install-quality.just"
import "just/setup/install-secrets.just"
import "just/setup/install-security.just"
import "just/setup/install-dev-env.just"

# ── Build ─────────────────────────────────────────────────────────────────
import "just/build/all.just"
import "just/build/build-fd.just"
import "just/build/build-qt.just"
import "just/build/build-tk.just"

# ── Test ───────────────────────────────────────────────────────────────────
import "just/test/all.just"
import "just/test/coverage.just"
import "just/test/demo.just"
import "just/test/e2e.just"
import "just/test/integration.just"
import "just/test/perf.just"
import "just/test/system.just"
import "just/test/test-include.just"
import "just/test/unit.just"

# ── Quality and Security ──────────────────────────────────────────────────
import "just/quality.just"
import "just/security.just"

# ── System ─────────────────────────────────────────────────────────────────
import "just/system/system.just"

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
