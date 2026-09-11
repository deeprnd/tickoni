# macOS build recipes

build-tk-macos-x86:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dfd-lib-dir={{ fd_tickoni_lib }}

build-tk-macos-arm:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dfd-lib-dir={{ fd_tickoni_lib }}

build-fd-macos-x86:
    env JUST_GMAKE="$(brew --prefix)/bin/gmake" PATH="$(brew --prefix)/opt/llvm/bin:$PATH" {{ python }} ../contrib/build/orchestrator.py --platform macos-x86 build-fd fd-tickoni-fd libs clang

build-fd-macos-arm:
    env JUST_GMAKE="$(brew --prefix)/bin/gmake" PATH="$(brew --prefix)/opt/llvm/bin:$PATH" {{ python }} ../contrib/build/orchestrator.py --platform macos-arm build-fd fd-tickoni-fd libs clang

# test-unit-fd-macos-x86/arm live in justfile (CI entry points).
test-unit-tk-macos-x86:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} test --summary all
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} run-tests

test-unit-tk-macos-arm:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} test --summary all
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} run-tests
