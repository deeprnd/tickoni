#!/usr/bin/env just

default:
    @just --list

help:
    @just --list

set export

import "just/common.just"

import "just/build/linux.just"
import "just/build/macos.just"
import "just/build/windows.just"
import "just/build/all.just"

import "just/test/unit.just"
import "just/test/e2e.just"
import "just/test/integration.just"
import "just/test/demo.just"
import "just/test/system.just"
import "just/test/coverage.just"
import "just/test/perf.just"

# ── Build ──────────────────────────────────────────────────────────────────

# Native Firedancer C unit-test recipes — intentional entry points for CI.
# Bodies delegate to orchestrator.py; CI callers invoke exact platform recipes.

test-unit-fd-linux-x86-gcc:
    #!/usr/bin/env bash
    set -euo pipefail
    ulimit -l 2097152 || true
    timeout=600
    python3 contrib/build/orchestrator.py --platform linux-x86 build-fd {{ fd_tickoni_build }} test gcc-12
    eval "$(python3 contrib/test/orchestrator.py dynamic-test-opts | grep -E '^TEST_OPTS=|^LDFLAGS_EXE=')"
    echo "Running unit tests with: $TEST_OPTS"
    {{ make }} -f contrib/build/GNUmakefile -j"{{ cpu_count }}" MACHINE=tickoni_fd BUILDDIR={{ fd_tickoni_build }} \
        LDFLAGS_EXE="$LDFLAGS_EXE" CC=gcc-12 LD=gcc-12 run-unit-test TEST_OPTS="$TEST_OPTS"

test-unit-fd-linux-x86-clang:
    #!/usr/bin/env bash
    set -euo pipefail
    ulimit -l 2097152 || true
    timeout=600
    python3 contrib/build/orchestrator.py --platform linux-x86 build-fd {{ fd_tickoni_build }} test clang-18
    eval "$(python3 contrib/test/orchestrator.py dynamic-test-opts | grep -E '^TEST_OPTS=|^LDFLAGS_EXE=')"
    echo "Running unit tests with: $TEST_OPTS"
    {{ make }} -f contrib/build/GNUmakefile -j"{{ cpu_count }}" MACHINE=tickoni_fd BUILDDIR={{ fd_tickoni_build }} \
        LDFLAGS_EXE="$LDFLAGS_EXE" CC=clang-18 LD=clang-18 run-unit-test TEST_OPTS="$TEST_OPTS"

test-unit-fd-linux-arm-gcc:
    #!/usr/bin/env bash
    set -euo pipefail
    ulimit -l 2097152 || true
    timeout=600
    python3 contrib/build/orchestrator.py --platform linux-arm build-fd {{ fd_tickoni_build }} test gcc-14
    eval "$(python3 contrib/test/orchestrator.py dynamic-test-opts | grep -E '^TEST_OPTS=|^LDFLAGS_EXE=')"
    echo "Running unit tests with: $TEST_OPTS"
    {{ make }} -f contrib/build/GNUmakefile -j"{{ cpu_count }}" MACHINE=tickoni_fd BUILDDIR={{ fd_tickoni_build }} \
        EXTRAS="zstd lz4" LDFLAGS_EXE="$LDFLAGS_EXE" CC=gcc-14 LD=gcc-14 run-unit-test TEST_OPTS="$TEST_OPTS"

test-unit-fd-macos-x86:
    # DISABLED: lz4 needs more porting before macOS can run.
    # python3 contrib/build/orchestrator.py --platform macos-x86 build-fd {{ fd_tickoni_build }} test clang
    # JUST_GMAKE="$(brew --prefix)/bin/gmake" {{ make }} -f contrib/build/GNUmakefile -j"{{ cpu_count }}" MACHINE=tickoni_fd BUILDDIR={{ fd_tickoni_build }} run-unit-test TEST_OPTS="--page-sz normal --page-cnt 131072"
    @echo "SKIPPED: test-unit-fd-macos-x86 — lz4 needs more porting"

test-unit-fd-macos-arm:
    # BLOCKED: the scoped Firedancer suite still relies on Linux-only runtime
    # facilities, and vendored blst has no macOS ARM64 assembly implementation.
    # python3 contrib/build/orchestrator.py --platform macos-arm build-fd {{ fd_tickoni_build }} test clang
    # JUST_GMAKE="$(brew --prefix)/bin/gmake" {{ make }} -f contrib/build/GNUmakefile -j"{{ cpu_count }}" MACHINE=tickoni_fd BUILDDIR={{ fd_tickoni_build }} run-unit-test TEST_OPTS="--page-sz normal --page-cnt 131072"
    @echo "BLOCKED: test-unit-fd-macos-arm — macOS ARM64 support is incomplete (Linux-only runtime tests and no vendored blst assembly)"
    @true

test-unit-fd-windows-x86:
    @echo "BLOCKED: test-unit-fd-windows-x86 — Windows fmemopen support is required"
    @true

test-unit-fd-windows-arm:
    @echo "BLOCKED: test-unit-fd-windows-arm — Windows fmemopen support is required"
    @true

test-unit-fd:
    #!/usr/bin/env bash
    set -euo pipefail
    # macOS FD unit tests are stubbed where native support is incomplete.
    # Windows FD unit tests are stubbed until fmemopen support is available.
    case "{{ os }}-{{ arch }}" in
      linux-x86) exec just test-unit-fd-linux-x86-gcc ;;
      linux-arm) exec just test-unit-fd-linux-arm-gcc ;;
      macos-x86) echo "test-unit-fd on macos-x86 is disabled — lz4 needs more porting" >&2; exit 1 ;;
      macos-arm) exec just test-unit-fd-macos-arm ;;
      windows-x86) exec just test-unit-fd-windows-x86 ;;
      windows-arm) exec just test-unit-fd-windows-arm ;;
      *) echo "unsupported host platform for test-unit-fd: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

# Tickoni unit lane: pure logic and fixture/mock-backed tests only.
# No running servers belong here. Canonical platform recipes are the
# implementation; the bare recipe below is only a host router.
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

# ── Platform-specific Qt terminal build recipes (self-contained: setup + build).
build-qt-linux-x86:
    #!/usr/bin/env bash
    set -euo pipefail
    REPO_ROOT="$(git rev-parse --show-toplevel)"
    cd "$REPO_ROOT"
    just setup-qt-linux-x86
    QT6_DIR=$(find ~/Qt -name Qt6Config.cmake 2>/dev/null | head -1 | xargs dirname | xargs dirname)
    CMAKE_PREFIX_PATH="$QT6_DIR" cmake -S "$REPO_ROOT/src/tickoni/terminal" -B "$REPO_ROOT/build/tickoni-terminal" && cmake --build "$REPO_ROOT/build/tickoni-terminal" -j {{ cpu_count }}

build-qt-linux-arm:
    #!/usr/bin/env bash
    set -euo pipefail
    REPO_ROOT="$(git rev-parse --show-toplevel)"
    cd "$REPO_ROOT"
    just setup-qt-linux-arm
    QT6_DIR=$(find ~/Qt -name Qt6Config.cmake 2>/dev/null | head -1 | xargs dirname | xargs dirname)
    CMAKE_PREFIX_PATH="$QT6_DIR" cmake -S "$REPO_ROOT/src/tickoni/terminal" -B "$REPO_ROOT/build/tickoni-terminal" && cmake --build "$REPO_ROOT/build/tickoni-terminal" -j {{ cpu_count }}

build-qt-macos-x86:
    #!/usr/bin/env bash
    set -euo pipefail
    REPO_ROOT="$(git rev-parse --show-toplevel)"
    cd "$REPO_ROOT"
    just setup-qt-macos-x86
    QT6_DIR=$(find ~/Qt -name Qt6Config.cmake 2>/dev/null | head -1 | xargs dirname | xargs dirname)
    CMAKE_PREFIX_PATH="$QT6_DIR" cmake -S "$REPO_ROOT/src/tickoni/terminal" -B "$REPO_ROOT/build/tickoni-terminal" && cmake --build "$REPO_ROOT/build/tickoni-terminal" -j {{ cpu_count }}

build-qt-macos-arm:
    #!/usr/bin/env bash
    set -euo pipefail
    REPO_ROOT="$(git rev-parse --show-toplevel)"
    cd "$REPO_ROOT"
    just setup-qt-macos-arm
    QT6_DIR=$(find ~/Qt -name Qt6Config.cmake 2>/dev/null | head -1 | xargs dirname | xargs dirname)
    CMAKE_PREFIX_PATH="$QT6_DIR" cmake -S "$REPO_ROOT/src/tickoni/terminal" -B "$REPO_ROOT/build/tickoni-terminal" && cmake --build "$REPO_ROOT/build/tickoni-terminal" -j {{ cpu_count }}

build-qt-windows-x86:
    #!/usr/bin/env bash
    set -euo pipefail
    REPO_ROOT="$(git rev-parse --show-toplevel)"
    cd "$REPO_ROOT"
    just setup-qt-windows-x86
    QT6_DIR=$(find ~/Qt -name Qt6Config.cmake 2>/dev/null | head -1 | xargs dirname | xargs dirname)
    CMAKE_PREFIX_PATH="$QT6_DIR" cmake -S "$REPO_ROOT/src/tickoni/terminal" -B "$REPO_ROOT/build/tickoni-terminal" && cmake --build "$REPO_ROOT/build/tickoni-terminal" -j {{ cpu_count }}

build-qt-windows-arm:
    #!/usr/bin/env bash
    set -euo pipefail
    REPO_ROOT="$(git rev-parse --show-toplevel)"
    cd "$REPO_ROOT"
    just setup-qt-windows-arm
    QT6_DIR=$(find ~/Qt -name Qt6Config.cmake 2>/dev/null | head -1 | xargs dirname | xargs dirname)
    CMAKE_PREFIX_PATH="$QT6_DIR" cmake -S "$REPO_ROOT/src/tickoni/terminal" -B "$REPO_ROOT/build/tickoni-terminal" && cmake --build "$REPO_ROOT/build/tickoni-terminal" -j {{ cpu_count }}



import "just/quality.just"
import "just/security.just"
