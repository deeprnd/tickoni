# macOS build recipes

build-tk-macos-x86:
    (cd {{ justfile_dir }} && mkdir -p build && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dfd-lib-dir=build/fd-tickoni-fd/lib)

build-tk-macos-arm:
    (cd {{ justfile_dir }} && mkdir -p build && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dfd-lib-dir=build/fd-tickoni-fd/lib)

build-fd-macos-x86:
    env JUST_GMAKE="$(brew --prefix)/bin/gmake" PATH="$(brew --prefix)/opt/llvm/bin:$PATH" {{ python }} {{ justfile_dir }}/contrib/build/orchestrator.py --platform macos-x86 build-fd fd-tickoni-fd libs clang

build-fd-macos-arm:
    env JUST_GMAKE="$(brew --prefix)/bin/gmake" PATH="$(brew --prefix)/opt/llvm/bin:$PATH" {{ python }} {{ justfile_dir }}/contrib/build/orchestrator.py --platform macos-arm build-fd fd-tickoni-fd libs clang

# test-unit-fd-macos-x86/arm live in justfile (CI entry points).
test-unit-tk-macos-x86:
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir=build/fd-tickoni-fd/lib test --summary all)
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir=build/fd-tickoni-fd/lib run-tests)

test-unit-tk-macos-arm:
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir=build/fd-tickoni-fd/lib test --summary all)
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir=build/fd-tickoni-fd/lib run-tests)
