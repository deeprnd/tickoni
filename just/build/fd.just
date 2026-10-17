# ── Build: Firedancer ──────────────────────────────────────────────────────
# Dispatcher, platform-specific Firedancer build recipes, and compatibility aliases.

# Bare dispatcher
build-fd:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
      linux-x86) exec just build-fd-linux-x86-gcc ;;
      linux-arm) exec just build-fd-linux-arm-gcc ;;
      macos-x86) exec just build-fd-macos-x86 ;;
      macos-arm) exec just build-fd-macos-arm ;;
      windows-x86) exec just build-fd-windows-x86 ;;
      windows-arm) exec just build-fd-windows-arm ;;
      *) echo "unsupported host platform for build-fd: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

# tickoni_fd machine profile: builds only the 5 Firedancer libraries
# Tickoni reuses (tango, util, ballet, disco, waltz). Excludes
# Solana validator tiles, RPC schemas, unrelated source, unit-test bins,
# fuzz-test bins, and other binaries (RocksDB, io_uring, etc.).
#
# NOTE: Firedancer's everything.mk compiles all sources regardless of
# requested .a targets. We list only the 5 libraries Tickoni needs as
# the final archive targets.
#
# CI alias — .github/actions/build-fd-tk-libs/action.yml delegates to this.
build-fd-tk-libs: build-fd

# Linux — GCC
build-fd-linux-x86-gcc:
    {{ python }} contrib/build/orchestrator.py --platform linux-x86 build-fd fd-tickoni-fd libs gcc-12

# Linux — Clang
build-fd-linux-x86-clang:
    {{ python }} contrib/build/orchestrator.py --platform linux-x86 build-fd fd-clang libs clang-18

# Linux — ARM GCC
build-fd-linux-arm-gcc:
    {{ python }} contrib/build/orchestrator.py --platform linux-arm build-fd fd-tickoni-fd libs gcc-14

# macOS
build-fd-macos-x86:
    env JUST_GMAKE="$(brew --prefix)/bin/gmake" {{ python }} contrib/build/orchestrator.py --platform macos-x86 build-fd fd-tickoni-fd libs clang "lz4 blst zstd"

build-fd-macos-arm:
    env JUST_GMAKE="$(brew --prefix)/bin/gmake" {{ python }} contrib/build/orchestrator.py --platform macos-arm build-fd fd-tickoni-fd libs clang "lz4 blst zstd"

# Windows
build-fd-windows-x86:
    {{ python }} contrib/build/orchestrator.py --platform windows-x86 build-fd fd-tickoni-fd libs clang --arch x86_64

build-fd-windows-arm:
    {{ python }} contrib/build/orchestrator.py --platform windows-arm build-fd fd-tickoni-fd libs clang --arch arm64

# ── Compatibility aliases ──────────────────────────────────────────────────
build-fd-gcc: build-fd-linux-x86-gcc

build-fd-clang: build-fd-linux-x86-clang

build-fd-arm: build-fd-linux-arm-gcc
