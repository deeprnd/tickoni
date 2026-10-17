# ── Setup: Platform dev stacks ──────────────────────────────────────────────
# (setup-env lives in install-env.just; setup-git lives in install-git.just)
# Recipes: setup-dev-env-{platform}
# Linux — dev mode (GCC or Clang, toolchain-agnostic)
setup-dev-env-linux-x86:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build
    {{ python }} contrib/setup/orchestrator.py zig,ssl,ops
    {{ python }} contrib/setup/orchestrator.py quality

setup-dev-env-linux-arm: setup-dev-env-linux-x86

# macOS — dev mode
setup-dev-env-macos-x86:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build
    {{ python }} contrib/setup/orchestrator.py zig,ssl,ops
    {{ python }} contrib/setup/orchestrator.py quality

setup-dev-env-macos-arm: setup-dev-env-macos-x86

# Windows x86_64 — dev mode (includes LLM tooling)
setup-dev-env-windows-x86:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build,mvsc,zig,ssl,quality,secrets --platform windows-x86

# Windows ARM64 — dev mode (includes LLM tooling)
setup-dev-env-windows-arm:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build,mvsc,zig,ssl,quality,secrets --platform windows-arm

# ── Test preparation ─────────────────────────────────────────────────────
test-prep-linux-x86:
    # NO-OP — memory setup moved to workflow YAML where sudo is available.
