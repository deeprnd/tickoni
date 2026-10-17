# ── Test: Unit recipes ────────────────────────────────────────────────────
# Platform-specific unit test implementations, bare dispatchers, and platform aliases.

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

# Native Firedancer C unit-test recipes.
test-unit-fd-linux-x86-gcc:
    #!/usr/bin/env bash
    set -euo pipefail
    timeout=600
    {{ python }} contrib/build/orchestrator.py --platform linux-x86 build-fd {{ fd_tickoni_build }} test gcc-12
    # Source dynamic resource detection to compute safe --page-cnt and -j
    eval "$({{ python }} contrib/test/infra/dynamic_test_opts.py | grep -E '^TEST_OPTS=|^LDFLAGS_EXE=')"
    echo "Running unit tests with: $TEST_OPTS"
    {{ make }} -f contrib/build/GNUmakefile -j"{{ cpu_count }}" MACHINE=tickoni_fd BUILDDIR={{ fd_tickoni_build }} \
        LDFLAGS_EXE="$LDFLAGS_EXE" CC=gcc-12 LD=gcc-12 run-unit-test TEST_OPTS="$TEST_OPTS"

test-unit-fd-macos-x86:
    {{ python }} contrib/build/orchestrator.py --platform macos-x86 build-fd {{ fd_tickoni_build }} test clang --build-target unit-test
    just test-unit-tk

test-unit-fd-macos-arm:
    {{ python }} contrib/build/orchestrator.py --platform macos-arm build-fd {{ fd_tickoni_build }} test clang --build-target unit-test
    just test-unit-tk

test-unit-fd-windows-x86:
    {{ python }} contrib/build/orchestrator.py --platform windows-x86 build-fd {{ fd_tickoni_build }} test clang --arch x86_64
    {{ make }} -f contrib/build/GNUmakefile -j"{{ cpu_count }}" MACHINE=tickoni_fd BUILDDIR={{ fd_tickoni_build }} run-unit-test TEST_OPTS="--page-sz normal --page-cnt 131072"

test-unit-fd-windows-arm:
    {{ python }} contrib/build/orchestrator.py --platform windows-arm build-fd {{ fd_tickoni_build }} test clang --arch arm64
    {{ make }} -f contrib/build/GNUmakefile -j"{{ cpu_count }}" MACHINE=tickoni_fd BUILDDIR={{ fd_tickoni_build }} run-unit-test TEST_OPTS="--page-sz normal --page-cnt 131072"

# Print computed hash and wire bytes for every audit fixture event, and emit audit JSONL.
gen-audit-fixtures:
    TK_GEN_FIXTURES=1 ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dtest=true test 2>&1
    TK_GEN_FIXTURES=1 ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dtest=true integration-test 2>&1

# Tickoni unit lane: pure logic and fixture/mock-backed tests only.
# No running servers belong here.
test-unit-tk-linux-x86:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} test --summary all
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} run-tests

test-unit-tk-linux-arm: test-unit-tk-linux-x86

test-unit-all:
    {{ python }} contrib/tool/readme/run-badged-command.py unit bash -c "just test-unit-tk && just test-unit-fd"
