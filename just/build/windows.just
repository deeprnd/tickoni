# Windows build recipes

build-tk-windows-x86:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dfd-lib-dir={{ fd_tickoni_lib }}

build-tk-windows-arm:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dfd-lib-dir={{ fd_tickoni_lib }}

build-fd-windows-x86:
    {{ python }} ../../contrib/build/orchestrator.py --platform windows-x86 build-fd fd-tickoni-fd libs clang --arch x86_64

build-fd-windows-arm:
    {{ python }} ../../contrib/build/orchestrator.py --platform windows-arm build-fd fd-tickoni-fd libs clang --arch arm64

test-unit-fd-windows-x86:
    python3 ../../contrib/build/orchestrator.py --platform windows-x86 build-fd {{ fd_tickoni_build }} test clang --arch x86_64
    {{ make }} -f ../../contrib/build/GNUmakefile -j"{{ cpu_count }}" MACHINE=tickoni_fd BUILDDIR={{ fd_tickoni_build }} run-unit-test TEST_OPTS="--page-sz normal --page-cnt 131072"

test-unit-fd-windows-arm:
    python3 ../../contrib/build/orchestrator.py --platform windows-arm build-fd {{ fd_tickoni_build }} test clang --arch arm64
    {{ make }} -f ../../contrib/build/GNUmakefile -j"{{ cpu_count }}" MACHINE=tickoni_fd BUILDDIR={{ fd_tickoni_build }} run-unit-test TEST_OPTS="--page-sz normal --page-cnt 131072"

test-unit-tk-windows-x86:
    mkdir -p build
    bash -c 'set -o pipefail; just build-fd-windows-x86 2>&1 | tee build/fd-windows-x86.log'
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} test
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} run-tests

test-unit-tk-windows-arm:
    mkdir -p build
    bash -c 'set -o pipefail; just build-fd-windows-arm 2>&1 | tee build/fd-windows-arm.log'
    rm -rf .zig-cache
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} test
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} run-tests

test-integration-tk-windows-x86:
    mkdir -p build
    just build-fd-windows-x86 > build/fd-windows-x86.log 2>&1
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test

test-integration-tk-windows-arm:
    mkdir -p build
    just build-fd-windows-arm > build/fd-windows-arm.log 2>&1
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test

test-system-tk-windows-x86:
    mkdir -p build
    bash -c 'set -o pipefail; just build-fd-windows-x86 2>&1 | tee build/fd-windows-x86.log'
    bash ../../contrib/test/run_live_investment_demo_win.sh windows-x86

test-system-tk-windows-arm:
    mkdir -p build
    bash -c 'set -o pipefail; just build-fd-windows-arm 2>&1 | tee build/fd-windows-arm.log'
    bash ../../contrib/test/run_live_investment_demo_win.sh windows-arm
