# Linux build recipes

build-tk-linux-x86:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dfd-lib-dir={{ fd_tickoni_lib }}

build-tk-linux-arm:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dfd-lib-dir={{ fd_tickoni_lib }}

build-fd-linux-x86-gcc:
    python3 ../../contrib/build/orchestrator.py --platform linux-x86 build-fd fd-tickoni-fd libs

build-fd-linux-x86-clang:
    python3 ../../contrib/build/orchestrator.py --platform linux-x86 build-fd fd-tickoni-fd libs clang-18

build-fd-linux-arm-gcc:
    python3 ../../contrib/build/orchestrator.py --platform linux-arm build-fd fd-tickoni-fd libs gcc-14

test-unit-fd-linux-x86-gcc:
    #!/usr/bin/env bash
    set -euo pipefail
    # Raised memlock limit — FD workspaces need mlock() for ~256MB+ workspace memory.
    # Default RLIMIT_MEMLOCK is 64KB which causes wksp allocation failures.
    # Use 2GB (2097152 KB) — works inside containers where `unlimited` is rejected.
    ulimit -l 2097152
    timeout=600
    python3 ../../contrib/build/orchestrator.py --platform linux-x86 build-fd {{ fd_tickoni_build }} test gcc-12
    # Source dynamic resource detection via orchestrator (eliminates uname)
    eval "$(python3 ../../contrib/test/orchestrator.py dynamic-test-opts | grep -E '^TEST_OPTS=|^LDFLAGS_EXE=')"
    echo "Running unit tests with: $TEST_OPTS"
    {{ make }} -f ../../contrib/build/GNUmakefile -j"{{ cpu_count }}" MACHINE=tickoni_fd BUILDDIR={{ fd_tickoni_build }} \
        LDFLAGS_EXE="$LDFLAGS_EXE" CC=gcc-12 LD=gcc-12 run-unit-test TEST_OPTS="$TEST_OPTS"

test-unit-tk-linux-x86:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} test --summary all
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} run-tests

test-unit-tk-linux-arm:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} test --summary all
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} run-tests
