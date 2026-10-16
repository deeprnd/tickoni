# ── Setup: Zig (idempotent — no-op if already installed) ───────────────────
# Used by CI test workflows that download build artifacts.

setup-zig:
    {{ python }} contrib/setup/orchestrator.py zig
