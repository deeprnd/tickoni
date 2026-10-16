# ── Setup: Developer recipes ──────────────────────────────────────────────
# Full developer stack: setup-env, setup-git, platform-specific dev setups, test-prep.

# Full developer stack (unchanged)
# Auto-detect host platform/arch and route to the correct setup recipe.
# All setup is delegated to orchestrator.py — it detects the platform and
# resolves dependencies from tool-versions.json.
setup-env toolchain="":
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build,zig,ssl,fd,quality,secrets,coverage,security,ops
    just setup-git

# Activate tracked git hooks (commit-msg strips anthropic AI co-authors)
setup-git:
    git config core.hooksPath .githooks
    chmod +x .githooks/commit-msg

# Linux — dev mode (GCC or Clang, toolchain-agnostic)
setup-linux-x86:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build
    {{ python }} contrib/setup/orchestrator.py zig,ssl,ops
    {{ python }} contrib/setup/orchestrator.py quality

setup-linux-arm: setup-linux-x86

# macOS — dev mode
setup-macos-x86:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build
    {{ python }} contrib/setup/orchestrator.py zig,ssl,ops
    {{ python }} contrib/setup/orchestrator.py quality

setup-macos-arm: setup-macos-x86

# Windows x86_64 — dev mode (includes LLM tooling)
setup-windows-x86:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build,mvsc,zig,ssl,quality,secrets --platform windows-x86

# Windows ARM64 — dev mode (includes LLM tooling)
setup-windows-arm:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build,mvsc,zig,ssl,quality,secrets --platform windows-arm

# ── Test preparation ─────────────────────────────────────────────────────
test-prep-linux-x86:
    # NO-OP — memory setup moved to workflow YAML where sudo is available.
