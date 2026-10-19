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
    #!/usr/bin/env bash
    set -euo pipefail
    timeout=600
    eval "$({{ python }} contrib/test/infra/dynamic_test_opts.py | grep -E '^TEST_OPTS=|^LDFLAGS_EXE=')"
    echo "Building unit tests with: $TEST_OPTS"
    {{ make }} -f contrib/build/GNUmakefile -j"{{ cpu_count }}" MACHINE=tickoni_fd BUILDDIR={{ fd_tickoni_build }} \
        LDFLAGS_EXE="$LDFLAGS_EXE" CC=gcc-12 LD=gcc-12 unit-test

build-test-unit-fd-linux-x86-clang:
    #!/usr/bin/env bash
    set -euo pipefail
    timeout=600
    eval "$({{ python }} contrib/test/infra/dynamic_test_opts.py | grep -E '^TEST_OPTS=|^LDFLAGS_EXE=')"
    echo "Building unit tests with: $TEST_OPTS"
    {{ make }} -f contrib/build/GNUmakefile -j"{{ cpu_count }}" MACHINE=tickoni_fd BUILDDIR={{ fd_tickoni_build }} \
        LDFLAGS_EXE="$LDFLAGS_EXE" CC=clang-18 LD=clang-18 unit-test

build-test-unit-fd-linux-arm-gcc:
    #!/usr/bin/env bash
    set -euo pipefail
    timeout=600
    eval "$({{ python }} contrib/test/infra/dynamic_test_opts.py | grep -E '^TEST_OPTS=|^LDFLAGS_EXE=')"
    echo "Building unit tests with: $TEST_OPTS"
    {{ make }} -f contrib/build/GNUmakefile -j"{{ cpu_count }}" MACHINE=tickoni_fd BUILDDIR={{ fd_tickoni_build }} \
        LDFLAGS_EXE="$LDFLAGS_EXE" CC=gcc-14 LD=gcc-14 unit-test

build-test-unit-fd-macos-x86:
    {{ make }} -f contrib/build/GNUmakefile -j"{{ cpu_count }}" MACHINE=tickoni_fd BUILDDIR={{ fd_tickoni_build }} unit-test

build-test-unit-fd-macos-arm:
    {{ make }} -f contrib/build/GNUmakefile -j"{{ cpu_count }}" MACHINE=tickoni_fd BUILDDIR={{ fd_tickoni_build }} unit-test

build-test-unit-fd-windows-x86:
    {{ make }} -f contrib/build/GNUmakefile -j"{{ cpu_count }}" MACHINE=tickoni_fd BUILDDIR={{ fd_tickoni_build }} unit-test

build-test-unit-fd-windows-arm:
    {{ make }} -f contrib/build/GNUmakefile -j"{{ cpu_count }}" MACHINE=tickoni_fd BUILDDIR={{ fd_tickoni_build }} unit-test

# ── FD test run recipes (run existing test executables only) ──────────────

test-unit-fd-linux-x86-gcc:
    #!/usr/bin/env bash
    set -euo pipefail
    timeout=600
    eval "$({{ python }} contrib/test/infra/dynamic_test_opts.py | grep -E '^TEST_OPTS=|^LDFLAGS_EXE=')"
    echo "Running unit tests with: $TEST_OPTS"
    contrib/test/run_unit_tests.sh --tests $(OBJDIR)/unit-test/automatic.txt $(TEST_OPTS)

test-unit-fd-linux-x86-clang:
    #!/usr/bin/env bash
    set -euo pipefail
    timeout=600
    eval "$({{ python }} contrib/test/infra/dynamic_test_opts.py | grep -E '^TEST_OPTS=|^LDFLAGS_EXE=')"
    echo "Running unit tests with: $TEST_OPTS"
    contrib/test/run_unit_tests.sh --tests $(OBJDIR)/unit-test/automatic.txt $(TEST_OPTS)

test-unit-fd-linux-arm-gcc:
    #!/usr/bin/env bash
    set -euo pipefail
    timeout=600
    eval "$({{ python }} contrib/test/infra/dynamic_test_opts.py | grep -E '^TEST_OPTS=|^LDFLAGS_EXE=')"
    echo "Running unit tests with: $TEST_OPTS"
    contrib/test/run_unit_tests.sh --tests $(OBJDIR)/unit-test/automatic.txt $(TEST_OPTS)

test-unit-fd-macos-x86:
    contrib/test/run_unit_tests.sh --tests $(OBJDIR)/unit-test/automatic.txt --page-sz normal --page-cnt 131072

test-unit-fd-macos-arm:
    contrib/test/run_unit_tests.sh --tests $(OBJDIR)/unit-test/automatic.txt --page-sz normal --page-cnt 131072

test-unit-fd-windows-x86:
    contrib/test/run_unit_tests.sh --tests $(OBJDIR)/unit-test/automatic.txt --page-sz normal --page-cnt 131072

test-unit-fd-windows-arm:
    contrib/test/run_unit_tests.sh --tests $(OBJDIR)/unit-test/automatic.txt --page-sz normal --page-cnt 131072

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
    pip install -e contrib/test/

test-setup-install-linux-arm:
    pip install -e contrib/test/

test-setup-install-macos-x86:
    pip3 install -e contrib/test/

test-setup-install-macos-arm:
    pip3 install -e contrib/test/

test-setup-install-windows-x86:
    pip install -e contrib/test/

test-setup-install-windows-arm:
    pip install -e contrib/test/

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
