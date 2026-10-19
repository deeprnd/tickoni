# ── Test: Unit recipes ────────────────────────────────────────────────────
# Platform-specific FD unit-test build and run recipes, separated.
#
# build-test-unit-fd-{platform} — builds test executables only
# test-unit-fd-{platform}       — runs existing test executables only

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

test-unit-fd-linux-x86-gcc:
    #!/usr/bin/env bash
    set -euo pipefail
    timeout=600
    eval "$({{ python }} contrib/test/infra/dynamic_test_opts.py | grep -E '^TEST_OPTS=|^LDFLAGS_EXE=')"
    echo "Running unit tests with: $TEST_OPTS"
    contrib/test/run_unit_tests.sh --tests {{ OBJDIR }}/unit-test/automatic.txt $(TEST_OPTS)

test-unit-fd-linux-x86-clang:
    #!/usr/bin/env bash
    set -euo pipefail
    timeout=600
    eval "$({{ python }} contrib/test/infra/dynamic_test_opts.py | grep -E '^TEST_OPTS=|^LDFLAGS_EXE=')"
    echo "Running unit tests with: $TEST_OPTS"
    contrib/test/run_unit_tests.sh --tests {{ OBJDIR }}/unit-test/automatic.txt $(TEST_OPTS)

test-unit-fd-linux-arm-gcc:
    #!/usr/bin/env bash
    set -euo pipefail
    timeout=600
    eval "$({{ python }} contrib/test/infra/dynamic_test_opts.py | grep -E '^TEST_OPTS=|^LDFLAGS_EXE=')"
    echo "Running unit tests with: $TEST_OPTS"
    contrib/test/run_unit_tests.sh --tests {{ OBJDIR }}/unit-test/automatic.txt $(TEST_OPTS)

test-unit-fd-macos-x86:
    contrib/test/run_unit_tests.sh --tests {{ OBJDIR }}/unit-test/automatic.txt --page-sz normal --page-cnt 131072

test-unit-fd-macos-arm:
    contrib/test/run_unit_tests.sh --tests {{ OBJDIR }}/unit-test/automatic.txt --page-sz normal --page-cnt 131072

test-unit-fd-windows-x86:
    contrib/test/run_unit_tests.sh --tests {{ OBJDIR }}/unit-test/automatic.txt --page-sz normal --page-cnt 131072

test-unit-fd-windows-arm:
    contrib/test/run_unit_tests.sh --tests {{ OBJDIR }}/unit-test/automatic.txt --page-sz normal --page-cnt 131072

# ── FD test all recipes (build + run) ─────────────────────────────────────

test-unit-fd-linux-x86-gcc-all: build-test-unit-fd-linux-x86-gcc test-unit-fd-linux-x86-gcc

test-unit-fd-linux-x86-clang-all: build-test-unit-fd-linux-x86-clang test-unit-fd-linux-x86-clang

test-unit-fd-linux-arm-gcc-all: build-test-unit-fd-linux-arm-gcc test-unit-fd-linux-arm-gcc

test-unit-fd-macos-x86-all: build-test-unit-fd-macos-x86 test-unit-fd-macos-x86

test-unit-fd-macos-arm-all: build-test-unit-fd-macos-arm test-unit-fd-macos-arm

test-unit-fd-windows-x86-all: build-test-unit-fd-windows-x86 test-unit-fd-windows-x86

test-unit-fd-windows-arm-all: build-test-unit-fd-windows-arm test-unit-fd-windows-arm

# Print computed hash and wire bytes for every audit fixture event, and emit audit JSONL.
gen-audit-fixtures:
    TK_GEN_FIXTURES=1 ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dtest=true test 2>&1
    TK_GEN_FIXTURES=1 ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dtest=true integration-test 2>&1

# Bare dispatcher; canonical platform/compiler recipes below are the implementation.
test-unit-tk:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
    linux-x86) exec just test-unit-tk-linux-x86 ;;
    linux-arm) exec just test-unit-tk-linux-arm ;;
    *) echo "unsupported host platform for test-unit-tk: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

# Tickoni unit lane: pure logic and fixture/mock-backed tests only.
# No running servers belong here.
test-unit-tk-linux-x86:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} test --summary all
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} run-tests

test-unit-tk-linux-arm: test-unit-tk-linux-x86

test-unit-tk-macos-x86:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} test --summary all
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} run-tests

test-unit-tk-macos-arm: test-unit-tk-macos-x86

test-unit-tk-windows-x86:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} test --summary all
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} run-tests

test-unit-tk-windows-arm: test-unit-tk-windows-x86

test-unit-all:
    {{ python }} contrib/tool/readme/run-badged-command.py unit bash -c "just test-unit-tk && just test-unit-fd"

# ── Test: Pytest setup recipes (CI) ────────────────────────────────────────
# Platform-specific pytest installation and execution for CI matrix entries.

test-setup-install-linux-x86:
    {{ python }} contrib/setup/orchestrator.py test-tools --platform linux-x86

test-setup-install-linux-arm:
    {{ python }} contrib/setup/orchestrator.py test-tools --platform linux-arm

test-setup-install-macos-x86:
    {{ python }} contrib/setup/orchestrator.py test-tools --platform macos-x86

test-setup-install-macos-arm:
    {{ python }} contrib/setup/orchestrator.py test-tools --platform macos-arm

test-setup-install-windows-x86:
    {{ python }} contrib/setup/orchestrator.py test-tools --platform windows-x86

test-setup-install-windows-arm:
    {{ python }} contrib/setup/orchestrator.py test-tools --platform windows-arm

test-setup-run-linux-x86:
    {{ python }} -m pytest contrib/test/ -v --tb=short

test-setup-run-linux-arm:
    {{ python }} -m pytest contrib/test/ -v --tb=short

test-setup-run-macos-x86:
    {{ python }} -m pytest contrib/test/ -v --tb=short

test-setup-run-macos-arm:
    {{ python }} -m pytest contrib/test/ -v --tb=short

test-setup-run-windows-x86:
    {{ python }} -m pytest contrib/test/ -v --tb=short

test-setup-run-windows-arm:
    {{ python }} -m pytest contrib/test/ -v --tb=short
