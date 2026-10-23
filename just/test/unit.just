# ── Test: Unit recipes ────────────────────────────────────────────────────
# Platform-specific FD unit-test build and run recipes.
#
# test-unit-fd dispatches to platform-specific recipes that do:
#   build-test-unit-fd-{platform} → test-unit-fd-{platform}-run

# Bare dispatcher; canonical platform/compiler recipes below are the implementation.
test-unit-fd:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
    linux-x86) exec just test-unit-fd-linux-x86-gcc ;;
    macos-x86) exec just test-unit-fd-macos-x86 ;;
    macos-arm) exec just test-unit-fd-macos-arm ;;
    windows-x86) exec just test-unit-fd-windows-x86 ;;
    windows-arm) exec just test-unit-fd-windows-arm ;;
    *) echo "unsupported host platform for test-unit-fd: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

# ── FD test build recipes (build test executables only) ───────────────────

build-test-unit-fd-linux-x86-gcc:
    env JUST_GMAKE={{ make }} {{ python }} contrib/build/orchestrator.py --platform linux-x86 build-fd fd-tickoni-fd test gcc-12 "lz4 blst zstd" --build-target unit-test

build-test-unit-fd-linux-x86-clang:
    env JUST_GMAKE={{ make }} {{ python }} contrib/build/orchestrator.py --platform linux-x86 build-fd fd-tickoni-fd test clang-18 "lz4 blst zstd" --build-target unit-test

build-test-unit-fd-linux-arm-gcc:
    env JUST_GMAKE={{ make }} {{ python }} contrib/build/orchestrator.py --platform linux-arm build-fd fd-tickoni-fd test gcc-14 "lz4 blst zstd" --build-target unit-test

build-test-unit-fd-macos-x86:
    env JUST_GMAKE="$(brew --prefix)/bin/gmake" {{ python }} contrib/build/orchestrator.py --platform macos-x86 build-fd fd-tickoni-fd test clang "lz4 blst zstd" --build-target unit-test

build-test-unit-fd-macos-arm:
    env JUST_GMAKE="$(brew --prefix)/bin/gmake" {{ python }} contrib/build/orchestrator.py --platform macos-arm build-fd fd-tickoni-fd test clang "lz4 blst zstd" --build-target unit-test

build-test-unit-fd-windows-x86:
    env JUST_GMAKE={{ make }} {{ python }} contrib/build/orchestrator.py --platform windows-x86 build-fd fd-tickoni-fd test clang --arch x86_64 "lz4 blst zstd" --build-target unit-test

build-test-unit-fd-windows-arm:
    env JUST_GMAKE={{ make }} {{ python }} contrib/build/orchestrator.py --platform windows-arm build-fd fd-tickoni-fd test clang --arch arm64 "lz4 blst zstd" --build-target unit-test

# ── FD test run recipes (run existing test executables only) ──────────────

test-unit-fd-linux-x86-gcc: build-test-unit-fd-linux-x86-gcc test-unit-fd-linux-x86-gcc-run

test-unit-fd-linux-x86-clang: build-test-unit-fd-linux-x86-clang test-unit-fd-linux-x86-clang-run

test-unit-fd-linux-arm-gcc: build-test-unit-fd-linux-arm-gcc test-unit-fd-linux-arm-gcc-run

test-unit-fd-macos-x86:
    @echo "SKIPPED: test-unit-fd-macos-x86 — lz4 needs more porting"

test-unit-fd-macos-arm:
    @echo "BLOCKED: test-unit-fd-macos-arm — macOS ARM64 support is incomplete (Linux-only runtime tests and no vendored blst assembly)"
    @true

test-unit-fd-windows-x86:
    @echo "BLOCKED: test-unit-fd-windows-x86 — Windows fmemopen support is required"
    @true

test-unit-fd-windows-arm:
    @echo "BLOCKED: test-unit-fd-windows-arm — Windows fmemopen support is required"
    @true

# ── FD test run implementations (run existing test executables only) ──────

test-unit-fd-linux-x86-gcc-run:
    #!/usr/bin/env bash
    set -euo pipefail
    timeout=600
    eval "$({{ python }} contrib/infra/dynamic_test_opts.py | grep -E '^TEST_OPTS=|^LDFLAGS_EXE=')"
    echo "Running unit tests with: $TEST_OPTS"
    contrib/test/run_unit_tests.sh --tests {{ OBJDIR }}/unit-test/automatic.txt $(TEST_OPTS)

test-unit-fd-linux-x86-clang-run:
    #!/usr/bin/env bash
    set -euo pipefail
    timeout=600
    eval "$({{ python }} contrib/infra/dynamic_test_opts.py | grep -E '^TEST_OPTS=|^LDFLAGS_EXE=')"
    echo "Running unit tests with: $TEST_OPTS"
    contrib/test/run_unit_tests.sh --tests {{ OBJDIR }}/unit-test/automatic.txt $(TEST_OPTS)

test-unit-fd-linux-arm-gcc-run:
    #!/usr/bin/env bash
    set -euo pipefail
    timeout=600
    eval "$({{ python }} contrib/infra/dynamic_test_opts.py | grep -E '^TEST_OPTS=|^LDFLAGS_EXE=')"
    echo "Running unit tests with: $TEST_OPTS"
    contrib/test/run_unit_tests.sh --tests {{ OBJDIR }}/unit-test/automatic.txt $(TEST_OPTS)

# ── Unit test dispatchers ────────────────────────────────────────────────
# test-unit-tk runs TK Zig unit tests on the host platform.

test-unit-tk:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
    linux-x86) exec just test-unit-tk-linux-x86 ;;
    linux-arm) exec just test-unit-tk-linux-arm ;;
    macos-x86) exec just test-unit-tk-macos-x86 ;;
    macos-arm) exec just test-unit-tk-macos-arm ;;
    windows-x86) exec just test-unit-tk-windows-x86 ;;
    windows-arm) exec just test-unit-tk-windows-arm ;;
    *) echo "unsupported host platform for test-unit-tk: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

test-unit-tk-linux-x86:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} test-unit-tk

test-unit-tk-linux-arm: test-unit-tk-linux-x86

test-unit-tk-macos-x86: test-unit-tk-linux-x86

test-unit-tk-macos-arm: test-unit-tk-macos-x86

test-unit-tk-windows-x86:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} test-unit-tk

test-unit-tk-windows-arm: test-unit-tk-windows-x86

# ── TK CLI unit test dispatcher ──────────────────────────────────────────

test-unit-cli:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
    linux-x86) exec just test-unit-cli-linux-x86 ;;
    linux-arm) exec just test-unit-cli-linux-arm ;;
    macos-x86) exec just test-unit-cli-macos-x86 ;;
    macos-arm) exec just test-unit-cli-macos-arm ;;
    windows-x86) exec just test-unit-cli-windows-x86 ;;
    windows-arm) exec just test-unit-cli-windows-arm ;;
    *) echo "unsupported host platform for test-unit-cli: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

# ── Unit test aggregate ──────────────────────────────────────────────────
# test-unit-all runs pytest + FD unit + CLI unit across all platforms.

test-unit-all:
    {{ python }} contrib/tool/readme/run-badged-command.py unit bash -c "just test-unit-tk && just test-unit-fd && just test-unit-cli"

# ── TK CLI unit test recipes (zig build test) ────────────────────────────
# CLI lane runs `test-unit-cli` which compiles and runs doctor + CLI tests sequentially.

test-unit-cli-linux-x86:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} test-unit-cli

test-unit-cli-linux-arm: test-unit-cli-linux-x86

test-unit-cli-macos-x86: test-unit-cli-linux-x86

test-unit-cli-macos-arm: test-unit-cli-linux-x86

test-unit-cli-windows-x86: test-unit-cli-linux-x86

test-unit-cli-windows-arm: test-unit-cli-linux-x86