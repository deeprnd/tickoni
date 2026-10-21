# ── Test: Dispatch and aggregate recipes ─────────────────────────────────
# test-all is the only dispatcher that lives here; per-lane dispatchers
# live in their respective files (unit.just, integration.just, etc.).

test-all:
    @just test-unit-all
    @just test-integration-all
    @just test-system-all
    @just test-e2e-all
    @just test-cli-all
    @just test-cov-all
