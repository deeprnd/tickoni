# ── Test: Dynamic test options ─────────────────────────────────────────────
# Compute TEST_OPTS and LDFLAGS_EXE from system resources.

# ── Test: Dynamic test options ─────────────────────────────────────────────
# Compute TEST_OPTS and LDFLAGS_EXE from system resources.

dynamic-test-opts:
    @{{ python }} contrib/test/infra/dynamic_test_opts.py

# ── Test: Include helper ──────────────────────────────────────────────────

import "../vars.just"

test-include:
    @echo "os={{ os }}, arch={{ arch }}"