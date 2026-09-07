# FD/Tickoni build dispatcher and aggregate recipes

# Bare dispatcher; canonical platform/compiler recipes are in dispatch map.
build-tk:
    python3 scripts/dispatch build-tk

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

# Bare dispatcher; canonical platform/compiler recipes are in dispatch map.
build-fd:
    python3 scripts/dispatch build-fd

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
