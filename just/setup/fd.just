# ── Setup: Firedancer toolchain ────────────────────────────────────────────
# FD toolchain: build + zig + ssl
#
# Bare dispatcher auto-detects platform and routes to the correct recipe.

setup-fd:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
      linux-x86) exec just setup-fd-linux-x86-gcc ;;
      linux-arm) exec just setup-fd-linux-arm-gcc ;;
      macos-x86) exec just setup-fd-macos-x86 ;;
      macos-arm) exec just setup-fd-macos-arm ;;
      windows-x86) exec just setup-fd-windows-x86 ;;
      windows-arm) exec just setup-fd-windows-arm ;;
      *) echo "unsupported host platform for setup-fd: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

# Linux — GCC
setup-fd-linux-x86-gcc:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build
    {{ python }} contrib/setup/orchestrator.py zig,ssl

# Linux — Clang
setup-fd-linux-x86-clang:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build
    {{ python }} contrib/setup/orchestrator.py zig,ssl

# Linux — ARM GCC
setup-fd-linux-arm-gcc:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build
    {{ python }} contrib/setup/orchestrator.py zig,ssl

# macOS
setup-fd-macos-x86:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build
    {{ python }} contrib/setup/orchestrator.py zig,ssl

setup-fd-macos-arm:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build
    {{ python }} contrib/setup/orchestrator.py zig,ssl

# Windows x86_64 — FD toolchain (zig + ssl)
setup-fd-windows-x86:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build,mvsc,zig,ssl --platform windows-x86

# Windows ARM64 — FD toolchain (zig + ssl)
setup-fd-windows-arm:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build,mvsc,zig,ssl --platform windows-arm

# ── Firedancer deps ──────────────────────────────────────────────────────────
setup-fd-deps-linux-x86-gcc:
    {{ python }} contrib/setup/orchestrator.py fd

setup-fd-deps-linux-x86-clang:
    {{ python }} contrib/setup/orchestrator.py fd

setup-fd-deps-linux-arm-gcc:
    {{ python }} contrib/setup/orchestrator.py fd

setup-fd-deps-macos-x86:
    {{ python }} contrib/setup/orchestrator.py fd

setup-fd-deps-macos-arm:
    {{ python }} contrib/setup/orchestrator.py fd

setup-fd-deps-windows-x86:
    {{ python }} contrib/setup/orchestrator.py fd --platform windows-x86

setup-fd-deps-windows-arm:
    {{ python }} contrib/setup/orchestrator.py fd --platform windows-arm
