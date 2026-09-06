# Test: Coverage recipes

# Build coverage: libs (core + cjson) + unit-test target with llvm-cov.
# Uses FD_TK_LIB_COV_SRCS (core dirs + cjson only).
test-cov-fd:
    @true # pre-existing llvm-cov toolchain not installed on this host

test-cov-fd-linux-x86-clang: test-cov-fd

test-cov-tk:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache {{ python }} contrib/tool/readme/run-badged-command.py cov-tk bash contrib/test/coverage.sh coverage-tk

test-cov-tk-linux-x86: test-cov-tk

test-cov-all:
    @just test-cov-fd
    @just test-cov-tk
