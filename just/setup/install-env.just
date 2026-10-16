# ── Setup: Full developer environment ──────────────────────────────────────
# Auto-detect host platform/arch and route to the correct setup recipe.
# All setup is delegated to orchestrator.py — it detects the platform and
# resolves dependencies from tool-versions.json.

setup-env toolchain="":
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build,zig,ssl,fd,quality,secrets,coverage,security,ops
    just setup-git
