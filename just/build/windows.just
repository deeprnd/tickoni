# Windows build recipes

build-tk-windows-x86:
    mkdir -p {{ justfile_dir }}/build
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dfd-lib-dir=build/fd-tickoni-fd/lib)

build-tk-windows-arm:
    mkdir -p {{ justfile_dir }}/build
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dfd-lib-dir=build/fd-tickoni-fd/lib)

build-fd-windows-x86:
    {{ python }} {{ justfile_dir }}/contrib/build/orchestrator.py --platform windows-x86 build-fd fd-tickoni-fd libs clang --arch x86_64

build-fd-windows-arm:
    {{ python }} {{ justfile_dir }}/contrib/build/orchestrator.py --platform windows-arm build-fd fd-tickoni-fd libs clang --arch arm64

# test-unit-fd-windows-x86/arm live in justfile (CI entry points).
test-unit-tk-windows-x86:
    mkdir -p {{ justfile_dir }}/build
    bash -c 'set -o pipefail; just build-fd-windows-x86 2>&1 | tee {{ justfile_dir }}/build/fd-windows-x86.log'
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir=build/fd-tickoni-fd/lib test)
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir=build/fd-tickoni-fd/lib run-tests)

test-unit-tk-windows-arm:
    mkdir -p {{ justfile_dir }}/build
    bash -c 'set -o pipefail; just build-fd-windows-arm 2>&1 | tee {{ justfile_dir }}/build/fd-windows-arm.log'
    (cd {{ justfile_dir }} && rm -rf {{ ZIG_CACHE }})
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir=build/fd-tickoni-fd/lib test)
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir=build/fd-tickoni-fd/lib run-tests)

test-integration-tk-windows-x86:
    mkdir -p {{ justfile_dir }}/build
    just build-fd-windows-x86 > {{ justfile_dir }}/build/fd-windows-x86.log 2>&1
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir=build/fd-tickoni-fd/lib integration-test)

test-integration-tk-windows-arm:
    mkdir -p {{ justfile_dir }}/build
    just build-fd-windows-arm > {{ justfile_dir }}/build/fd-windows-arm.log 2>&1
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir=build/fd-tickoni-fd/lib integration-test)

test-system-tk-windows-x86:
    mkdir -p {{ justfile_dir }}/build
    bash -c 'set -o pipefail; just build-fd-windows-x86 2>&1 | tee {{ justfile_dir }}/build/fd-windows-x86.log'
    bash {{ justfile_dir }}/contrib/test/run_live_investment_demo_win.sh windows-x86

test-system-tk-windows-arm:
    mkdir -p {{ justfile_dir }}/build
    bash -c 'set -o pipefail; just build-fd-windows-arm 2>&1 | tee {{ justfile_dir }}/build/fd-windows-arm.log'
    bash {{ justfile_dir }}/contrib/test/run_live_investment_demo_win.sh windows-arm
