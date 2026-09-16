# Linux build recipes

build-tk-linux-x86:
    (cd {{ justfile_dir }} && mkdir -p build && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dfd-lib-dir=build/fd-tickoni-fd/lib)

build-tk-linux-arm:
    (cd {{ justfile_dir }} && mkdir -p build && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dfd-lib-dir=build/fd-tickoni-fd/lib)

build-fd-linux-x86-gcc:
    python3 {{ justfile_dir }}/contrib/build/orchestrator.py --platform linux-x86 build-fd fd-tickoni-fd libs

build-fd-linux-x86-clang:
    python3 {{ justfile_dir }}/contrib/build/orchestrator.py --platform linux-x86 build-fd fd-tickoni-fd libs clang-18

build-fd-linux-arm-gcc:
    python3 {{ justfile_dir }}/contrib/build/orchestrator.py --platform linux-arm build-fd fd-tickoni-fd libs gcc-14

# test-unit-fd-linux-x86-gcc lives in justfile (CI entry point).
test-unit-tk-linux-x86:
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir=build/fd-tickoni-fd/lib test --summary all)
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir=build/fd-tickoni-fd/lib run-tests)

test-unit-tk-linux-arm:
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir=build/fd-tickoni-fd/lib test --summary all)
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir=build/fd-tickoni-fd/lib run-tests)
