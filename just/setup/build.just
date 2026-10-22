# ── Setup: Build toolchain ────────────────────────────────────────────────
# Build-only: compilers + build infra (no zig, no ssl, no quality, no secrets)
#
# Bare dispatcher auto-detects platform and routes to the correct recipe.

setup-build:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
      linux-x86) exec just setup-build-linux-x86-gcc ;;
      linux-arm) exec just setup-build-linux-arm-gcc ;;
      macos-x86) exec just setup-build-macos-x86 ;;
      macos-arm) exec just setup-build-macos-arm ;;
      windows-x86) exec just setup-build-windows-x86 ;;
      windows-arm) exec just setup-build-windows-arm ;;
      *) echo "unsupported host platform for setup-build: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

setup-build-linux-x86-gcc:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build --platform {{ os }}-{{ arch }}

setup-build-linux-x86-clang:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build --platform {{ os }}-{{ arch }}

setup-build-macos-x86:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build --platform macos-x86

setup-build-macos-arm:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build --platform macos-arm

setup-build-linux-arm-gcc:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build --platform linux-arm

# Windows build-only setup: no llama.cpp; system-test setup owns the LLM.
setup-build-windows-x86:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build,mvsc --platform windows-x86

setup-build-windows-arm:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build,mvsc --platform windows-arm
