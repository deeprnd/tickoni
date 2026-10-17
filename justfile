# ── Variables ──────────────────────────────────────────────────────────────
import "just/vars.just"

# ── Setup ─────────────────────────────────────────────────────────────────
import "just/setup/all.just"
import "just/setup/build.just"
import "just/setup/coverage.just"
import "just/setup/fd.just"
import "just/setup/git.just"
import "just/setup/gitleaks.just"
import "just/setup/just.just"
import "just/setup/qt.just"
import "just/setup/quality.just"
import "just/setup/security.just"
import "just/setup/zig.just"

# ── Build ─────────────────────────────────────────────────────────────────
import "just/build/all.just"
import "just/build/fd.just"
import "just/build/qt.just"
import "just/build/tk.just"

# ── Test ───────────────────────────────────────────────────────────────────
import "just/test/all.just"
import "just/test/coverage.just"
import "just/test/demo.just"
import "just/test/e2e.just"
import "just/test/integration.just"
import "just/test/perf.just"
import "just/test/system.just"
import "just/test/unit.just"
import "just/test/utils.just"

# ── Quality and Security ──────────────────────────────────────────────────
import "just/quality/all.just"
import "just/quality/format.just"
import "just/quality/lint.just"
import "just/quality/proto.just"
import "just/quality/yaml.just"
import "just/quality/spell.just"
import "just/security/all.just"
import "just/security/codeql.just"
import "just/security/engine.just"
import "just/security/gitleaks.just"
import "just/security/proof.just"
import "just/security/sanitize.just"
import "just/security/seccomp.just"

# ── System ─────────────────────────────────────────────────────────────────
import "just/system/system.just"

# ── Default ────────────────────────────────────────────────────────────────
default:
    @just --list

# ── Super-aggregator ───────────────────────────────────────────────────────
tests-all:
    @just build-all
    @just test-all
    @just quality-check-all
    @just security-check-all
