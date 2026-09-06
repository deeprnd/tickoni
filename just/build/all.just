# FD/Tickoni build dispatcher and aggregate recipes

# Bare dispatcher; canonical platform/compiler recipes above are the implementation.
build-tk:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
      linux-x86) exec just build-tk-linux-x86 ;;
      linux-arm) exec just build-tk-linux-arm ;;
      macos-x86) exec just build-tk-macos-x86 ;;
      macos-arm) exec just build-tk-macos-arm ;;
      windows-x86) exec just build-tk-windows-x86 ;;
      windows-arm) exec just build-tk-windows-arm ;;
      *) echo "unsupported host platform for build-tk: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

# tickoni_fd machine profile: builds only the 5 Firedancer libraries
# Tickoni reuses (tango, util, ballet, disco, waltz). Excludes
# Solana validator tiles, RPC schemas, unrelated source, unit-test bins,
# fuzz-test bins, and other binaries (RocksDB, io_uring, etc.).
#
# CI alias — .github/actions/build-fd-tk-libs/action.yml delegates to this.
build-fd-tk-libs: build-fd

# Adding a new lib: edit contrib/build/fd-tk-libs.sh (FD_TK_LIBS or
# FD_TK_LIBS_EXTRA arrays). All justfile/CI/quality/security consumers
# pick up the change automatically.
# ── Public build recipes ─────────────────────────────────────────────────────

# Bare dispatcher; canonical platform/compiler recipes above are the implementation.
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

# Compatibility aliases retained for S6/documentation migration.
build-fd-gcc: build-fd-linux-x86-gcc

build-fd-clang: build-fd-linux-x86-clang

build-fd-arm: build-fd-linux-arm-gcc

build-fd-macos-x86_64: build-fd-macos-x86

build-fd-dev:
    make -j"$(nproc)" all

build-all:
    {{ python }} contrib/tool/readme/run-badged-command.py build bash -c "just build-fd && just build-tk"

# Qt terminal — CMake-based, independent of build.zig
build-qt:
    cmake -S src/tickoni/terminal -B build/tickoni-terminal
    cmake --build build/tickoni-terminal -j {{ cpu_count }}

# ── Clean ────────────────────────────────────────────────────────────────────

# Clean all Firedancer and Zig/Tickoni build artifacts.
# Firedancer outputs live under `build/` (BUILDDIR variants).
# Zig/Tickoni outputs live under `target/` and `zig-out/`.
clean-all:
    rm -rf build/ target/ zig-out/
