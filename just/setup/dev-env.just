# ── Setup: CI-compatible bare aliases ──────────────────────────────────────
# These aliases let tests-dev-setup.yml call just setup-linux-x86-gcc etc.
# Each assembles build + fd + quality + zig for the platform.
# They are NOT bare dispatchers — they target one platform only.

setup-linux-x86-gcc:
    @just setup-build-linux-x86-gcc
    @just setup-fd-linux-x86-gcc
    @just setup-quality-linux-x86
    @just setup-zig-linux-x86

setup-linux-arm-gcc:
    @just setup-build-linux-arm-gcc
    @just setup-fd-linux-arm-gcc
    @just setup-quality-linux-x86
    @just setup-zig-linux-arm

setup-macos-x86:
    @just setup-build-macos-x86
    @just setup-fd-macos-x86
    @just setup-quality-macos-x86
    @just setup-zig-macos-x86

setup-macos-arm:
    @just setup-build-macos-arm
    @just setup-fd-macos-arm
    @just setup-quality-macos-arm
    @just setup-zig-macos-arm

setup-windows-x86:
    @just setup-build-windows-x86
    @just setup-fd-windows-x86
    @just setup-quality-windows-x86
    @just setup-zig-windows-x86

setup-windows-arm:
    @just setup-build-windows-arm
    @just setup-fd-windows-arm
    @just setup-quality-windows-arm
    @just setup-zig-windows-arm

# ── Setup: Platform dev stacks ──────────────────────────────────────────────
# (setup-all lives in env.just; setup-git lives in git.just)
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
