# ── Setup: Build toolchain ────────────────────────────────────────────────
# Build-only: compilers + build infra (no zig, no ssl, no quality, no secrets)

setup-build-linux-x86-gcc:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build

setup-build-linux-x86-clang:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build

setup-build-macos-x86:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build

setup-build-macos-arm:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build

setup-build-linux-arm-gcc:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build

# Windows build-only setup: no llama.cpp; system-test setup owns the LLM.
setup-build-windows-x86:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build,mvsc --platform windows-x86

setup-build-windows-arm:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build,mvsc --platform windows-arm
