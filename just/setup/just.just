# ── Setup: Just (idempotent — no-op if already installed) ──────────────────
# Used by CI test workflows that download build artifacts.

setup-just:
    {{ python }} contrib/setup/orchestrator.py just --platform {{ os }}-{{ arch }}
