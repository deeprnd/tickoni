# Linux build recipes

build-tk-linux-x86:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dfd-lib-dir={{ fd_tickoni_lib }}

build-tk-linux-arm:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dfd-lib-dir={{ fd_tickoni_lib }}

build-fd-linux-x86-gcc:
    python3 contrib/build/orchestrator.py --platform linux-x86 build-fd fd-tickoni-fd libs

build-fd-linux-x86-clang:
    python3 contrib/build/orchestrator.py --platform linux-x86 build-fd fd-tickoni-fd libs clang-18

build-fd-linux-arm-gcc:
    python3 contrib/build/orchestrator.py --platform linux-arm build-fd fd-tickoni-fd libs gcc-14

# test-unit-fd-linux-x86-gcc lives in justfile (CI entry point).
test-unit-tk-linux-x86:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} test --summary all
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} run-tests

test-unit-tk-linux-arm:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} test --summary all
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} run-tests
