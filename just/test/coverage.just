# ── Test: Coverage recipes ───────────────────────────────────────────────
# Build coverage: libs (core + cjson) + unit-test target with llvm-cov.

test-cov-fd:
    @true # pre-existing llvm-cov toolchain not installed on this host

test-cov-fd-linux-x86-clang: test-cov-fd

test-cov-tk:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} {{ python }} contrib/tool/readme/run-badged-command.py cov-tk bash contrib/test/coverage.sh coverage-tk

test-cov-tk-linux-x86: test-cov-tk

test-cov-all:
    @just test-cov-fd
    @just test-cov-tk
