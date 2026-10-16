# ── Setup: Platform dev stacks ─────────────────────────────────────────────

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
