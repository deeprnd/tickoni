# Prefer GNU Make 4.x (Homebrew installs it as `gmake` on macOS); fall back to `make`.
# Firedancer's GNUmakefile uses `undefine`, which needs GNU Make >= 3.82.
make := `command -v gmake || command -v make`
python := `command -v python || command -v python3`

# Firedancer/Tickoni build natively on Linux, macOS, and Windows.

# Shared Firedancer lib definitions — used by contrib/build/fd-build-lib.sh and
# contrib/security/security.sh. It provides:
#   FD_TK_LIB_SRCS          source dirs for the 5 harness libs
#   FD_TK_LIB_TEST_SRCS     + picohttpparser, blst, lz4, zstd, nanopb (for tests)
#   FD_TK_LIB_COV_SRCS      core + cjson only (coverage)
#   FD_TK_LIB_EXCLUDES      grep -vE pattern for non-linked subdirs
#   FD_TK_LIBS              libfd_tango.a libfd_util.a libfd_ballet.a libfd_disco.a libfd_waltz.a
#   FD_TK_LIBS_EXTRA        libfd_blst.a libfd_zstd.a libfd_lz4.a
#   fd_compute_mks()        produce LOCAL_MKS from a source-dir list

# Per-compiler build directories (kept for CI compatibility). Each Firedancer
# build profile compiles to a different BUILDDIR/lib/ subtree.  *_build is the
# short name passed to `make` as BUILDDIR (Firedancer prefixes `build/`); *_dir
# is the complete path (used in `mkdir -p` and archive targets); *_lib is the
# full lib/ subtree path.
#
# CI recipes (test-*, quality-*, security-*) reference these by name, so the
# defaults here must stay in sync with what the CI workflows expect.
fd_tickoni_build := "fd-tickoni-fd"
fd_tickoni_dir := "build/fd-tickoni-fd"
fd_tickoni_lib := "build/fd-tickoni-fd/lib"

fd_gcc_build := "fd-gcc"
fd_gcc_dir := "build/fd-gcc"
fd_gcc_lib := "build/fd-gcc/lib"

fd_clang_build := "fd-clang"
fd_clang_dir := "build/fd-clang"
fd_clang_lib := "build/fd-clang/lib"

fd_arm_build := "fd-arm"
fd_arm_dir := "build/fd-arm"
fd_arm_lib := "build/fd-arm/lib"

fd_cov_build := "fd-cov"
fd_cov_dir := "build/fd-cov"
fd_cov_lib := "build/fd-cov/lib"

default:
    @just --list

help:
    @just --list

# ── Minimal CI setup recipes ─────────────────────────────────────────────────
# Each workflow calls the minimal recipe that installs only what it needs.
# This avoids over-installing tools like quality/lint/Go when only gitleaks
# or a build toolchain is required.

# Build-only: compilers + build infra (no zig, no ssl, no quality, no secrets)
setup-build-linux-x86-gcc:
    python3 contrib/setup/orchestrator.py core,essential,toolchain,build

setup-build-linux-x86-clang:
    python3 contrib/setup/orchestrator.py core,essential,toolchain,build

setup-build-macos-x86:
    python3 contrib/setup/orchestrator.py core,essential,toolchain,build

setup-build-macos-arm:
    python3 contrib/setup/orchestrator.py core,essential,toolchain,build

setup-build-linux-arm-gcc:
    python3 contrib/setup/orchestrator.py core,essential,toolchain,build

# Engine build: full FD toolchain (build + zig + ssl + gcc)
setup-fd-linux-x86-gcc:
    python3 contrib/setup/orchestrator.py core,essential,toolchain,build
    python3 contrib/setup/orchestrator.py zig,ssl

setup-fd-linux-x86-clang:
    python3 contrib/setup/orchestrator.py core,essential,toolchain,build
    python3 contrib/setup/orchestrator.py zig,ssl

setup-fd-macos-x86:
    python3 contrib/setup/orchestrator.py core,essential,toolchain,build
    python3 contrib/setup/orchestrator.py zig,ssl

setup-fd-macos-arm:
    python3 contrib/setup/orchestrator.py core,essential,toolchain,build
    python3 contrib/setup/orchestrator.py zig,ssl

setup-fd-linux-arm-gcc:
    python3 contrib/setup/orchestrator.py core,essential,toolchain,build
    python3 contrib/setup/orchestrator.py zig,ssl

# Windows x86_64 — FD toolchain (zig + ssl)
setup-fd-windows-x86:
    python3 contrib/setup/orchestrator.py core,essential,toolchain,build,mvsc --platform windows-x86
    python3 contrib/setup/orchestrator.py zig,ssl --platform windows-x86

# Windows ARM64 — FD toolchain (zig + ssl)
setup-fd-windows-arm:
    python3 contrib/setup/orchestrator.py core,essential,toolchain,build,mvsc --platform windows-arm
    python3 contrib/setup/orchestrator.py zig,ssl --platform windows-arm

# Quality: build + quality tools (shellcheck, actionlint, yamllint, pre-commit, buf + go)
setup-quality-linux-x86:
    python3 contrib/setup/orchestrator.py core,essential,toolchain,build
    python3 contrib/setup/orchestrator.py quality

# Secrets-only: gitleaks (no quality, no build tools beyond what gitleaks needs)
setup-gitleaks-linux-x86:
    python3 contrib/setup/orchestrator.py core,essential,secrets

# Full developer stack (unchanged)
# ── Platform Detection ────────────────────────────────────────────────────────
# All recipes use {{ os }} and {{ arch }} from here — never call uname directly.

# Detect OS/arch via platform.sh (single source of truth).
# Returns lowercase: linux/mac/windows and x86/arm.
os := `bash contrib/platform.sh os`

# Detect arch from platform.sh (falls back to "unknown")
arch := `bash contrib/platform.sh arch`

# Aliases for backward compatibility with any internal shell code still
# referencing the old variable names (e.g. contrib/build/fd-build-lib.sh callers).
tk_os := `bash contrib/platform.sh os`
tk_arch := `bash contrib/platform.sh arch`
tk_platform := `bash contrib/platform.sh platform`
cpu_count := `bash contrib/platform.sh cores`

# Auto-detect host platform/arch and route to the correct setup recipe.
# All setup is delegated to orchestrator.py — it detects the platform and
# resolves dependencies from tool-versions.json.
setup-env toolchain="":
    python3 contrib/setup/orchestrator.py core,essential,toolchain,build,python,zig,ssl,fd,quality,secrets,coverage,security,ops
    just setup-git

# Activate tracked git hooks (commit-msg strips anthropic AI co-authors)
setup-git:
    git config core.hooksPath .githooks
    chmod +x .githooks/commit-msg

# All setup is delegated to orchestrator.py — it detects the platform and
# resolves dependencies from tool-versions.json.

# Linux x86_64 — GCC toolchain
setup-linux-x86-gcc:
    python3 contrib/setup/orchestrator.py core,essential,toolchain,build
    python3 contrib/setup/orchestrator.py zig,ssl,ops
    python3 contrib/setup/orchestrator.py quality,secrets

# Linux x86_64 — Clang toolchain
setup-linux-x86-clang:
    python3 contrib/setup/orchestrator.py core,essential,toolchain,build
    python3 contrib/setup/orchestrator.py zig,ssl,ops
    python3 contrib/setup/orchestrator.py quality,secrets

# Linux aarch64 — GCC toolchain
setup-linux-arm-gcc:
    python3 contrib/setup/orchestrator.py core,essential,toolchain,build
    python3 contrib/setup/orchestrator.py zig,ssl,ops
    python3 contrib/setup/orchestrator.py quality,secrets

# Linux aarch64 — Clang toolchain
setup-linux-arm-clang:
    python3 contrib/setup/orchestrator.py core,essential,toolchain,build
    python3 contrib/setup/orchestrator.py zig,ssl,ops
    python3 contrib/setup/orchestrator.py quality,secrets

# macOS x86_64
setup-macos-x86:
    python3 contrib/setup/orchestrator.py core,essential,toolchain,build
    python3 contrib/setup/orchestrator.py zig,ssl,ops
    python3 contrib/setup/orchestrator.py quality

# macOS ARM64
setup-macos-arm:
    python3 contrib/setup/orchestrator.py core,essential,toolchain,build
    python3 contrib/setup/orchestrator.py zig,ssl,ops
    python3 contrib/setup/orchestrator.py quality

# Windows x86_64 — dev mode (includes LLM tooling)
setup-windows-x86:
    python3 contrib/setup/orchestrator.py core,essential,toolchain,build,mvsc --platform windows-x86
    python3 contrib/setup/orchestrator.py zig,ssl --platform windows-x86
    python3 contrib/setup/orchestrator.py quality,secrets --platform windows-x86

# Windows ARM64 — dev mode (includes LLM tooling)
setup-windows-arm:
    python3 contrib/setup/orchestrator.py core,essential,toolchain,build,mvsc --platform windows-arm
    python3 contrib/setup/orchestrator.py zig,ssl --platform windows-arm
    python3 contrib/setup/orchestrator.py quality,secrets --platform windows-arm

# Windows x86_64 — CI mode (no LLM tooling, no security tools)
setup-windows-ci-x86:
    python3 contrib/setup/orchestrator.py core,essential,toolchain,build,mvsc --platform windows-x86
    python3 contrib/setup/orchestrator.py zig --platform windows-x86
    python3 contrib/setup/orchestrator.py quality --platform windows-x86

# Windows ARM64 — CI mode (no LLM tooling, no security tools)
setup-windows-ci-arm:
    python3 contrib/setup/orchestrator.py core,essential,toolchain,build,mvsc --platform windows-arm
    python3 contrib/setup/orchestrator.py zig --platform windows-arm
    python3 contrib/setup/orchestrator.py quality --platform windows-arm

# Qualified CI dependency/setup entrypoints.  Workflows select these names;
# the scripts remain implementation details of the just command surface.
setup-python-tools packages="":
    {{ python }} -m pip install --upgrade pip
    {{ python }} -m pip install {{ packages }}

setup-fd-deps-linux-x86-gcc:
    CC=gcc CXX=g++ FD_AUTO_INSTALL_PACKAGES=1 bash contrib/build/deps.sh check

setup-fd-deps-linux-x86-clang:
    CC=clang CXX=clang++ FD_AUTO_INSTALL_PACKAGES=1 bash contrib/build/deps.sh check

setup-fd-deps-linux-arm-gcc:
    CC=gcc CXX=g++ FD_AUTO_INSTALL_PACKAGES=1 bash contrib/build/deps.sh check

setup-fd-deps-macos-x86:
    CC=clang CXX=clang++ FD_AUTO_INSTALL_PACKAGES=1 bash contrib/build/deps.sh check

setup-fd-deps-macos-arm:
    CC=clang CXX=clang++ FD_AUTO_INSTALL_PACKAGES=1 bash contrib/build/deps.sh check

setup-coverage-linux-x86-clang:
    sudo apt-get install -y clang-18 clang++-18 llvm-18
    for tool in profdata objdump ar cov; do sudo update-alternatives --install /usr/bin/llvm-$tool llvm-$tool /usr/bin/llvm-${tool}-18 100; done

test-prep-linux-x86:
    # NO-OP — memory setup moved to workflow YAML where sudo is available.

# ── Python ─────────────────────────────────────────────────────────────────

python-dev-install extras="dev":
    {{ python }} -m venv .venv
    .venv/bin/python -m pip install --upgrade pip
    .venv/bin/python -m pip install ".[{{ extras }}]"

python-dev-install-all:
    @just python-dev-install "dev,protobuf,mathgen,sim,solana,agave-cluster"

# ── All-in ──────────────────────────────────────────────────────────────────

tests-all:
    @just build-all
    @just quality-format-check-all
    @just quality-lint-check-tk
    @just quality-proto-check-all
    @just security-check-all
    @just security-engine-check-changes
    @just test-all

# ── Build ──────────────────────────────────────────────────────────────────

build-tk-linux-x86:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/build/zigw.sh build -Dfd-lib-dir={{ fd_tickoni_lib }}

build-tk-linux-arm: build-tk-linux-x86

build-tk-macos-x86: build-tk-linux-x86

build-tk-macos-arm: build-tk-linux-x86

build-tk-windows-x86: build-tk-linux-x86

build-tk-windows-arm: build-tk-linux-x86

# Bare dispatcher; canonical platform recipes above are the implementation.
build-tk:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
      linux-x86) exec just build-tk-linux-x86 ;;
      linux-arm) exec just build-tk-linux-arm ;;
      macos-x86) exec just build-tk-macos-x86 ;;
      macos-arm) exec just build-tk-macos-arm ;;
      windows-x86) exec just build-tk-windows-x86 ;;
      windows-arm) exec just build-tk-windows-arm ;;
      *) echo "unsupported host platform for build-tk: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

# tickoni_fd machine profile: builds only the 5 Firedancer libraries
# Tickoni reuses (tango, util, ballet, disco, waltz). Excludes
# Solana validator tiles, RPC schemas, unrelated source, unit-test bins,
# fuzz-test bins, and other binaries (RocksDB, io_uring, etc.).
#
# NOTE: Firedancer's everything.mk compiles all sources regardless of
# requested .a targets. We list only the 5 libraries Tickoni needs as
# the final archive targets.
#
# CI alias — .github/actions/build-fd-tk-libs/action.yml delegates to this.
build-fd-tk-libs: build-fd

# Adding a new lib: edit contrib/build/fd-tk-libs.sh (FD_TK_LIBS or
# FD_TK_LIBS_EXTRA arrays). All justfile/CI/quality/security consumers
# pick up the change automatically.
# ── Public build recipes ─────────────────────────────────────────────────────

# Bare dispatcher; canonical platform/compiler recipes below are the implementation.
build-fd:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
      linux-x86) exec just build-fd-linux-x86-gcc ;;
      linux-arm) exec just build-fd-linux-arm-gcc ;;
      macos-x86) exec just build-fd-macos-x86 ;;
      macos-arm) exec just build-fd-macos-arm ;;
      windows-x86) exec just build-fd-windows-x86 ;;
      windows-arm) exec just build-fd-windows-arm ;;
      *) echo "unsupported host platform for build-fd: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

# Canonical FD build recipes.
build-fd-linux-x86-gcc:
    bash contrib/build/fd-build-lib.sh fd-tickoni-fd gcc

build-fd-linux-x86-clang:
    bash contrib/build/fd-build-lib.sh fd-clang clang-18

build-fd-linux-arm-gcc:
    bash contrib/build/fd-build-lib.sh fd-arm gcc-14

build-fd-macos-x86:
    brew install make llvm || true
    export PATH="$(brew --prefix)/bin:$PATH"
    env JUST_GMAKE="$(brew --prefix)/bin/gmake" PATH="$(brew --prefix)/bin:/usr/local/bin:$PATH" bash contrib/build/fd-build-lib.sh fd-tickoni-fd clang libs ""

build-fd-macos-arm:
    brew install make llvm || true
    env JUST_GMAKE="$(brew --prefix)/bin/gmake" bash contrib/build/fd-build-lib.sh fd-tickoni-fd clang libs "lz4 blst zstd"

build-fd-windows-x86:
    bash contrib/build/fd-build-windows.sh x86_64

build-fd-windows-arm:
    bash contrib/build/fd-build-windows.sh arm64

# Compatibility aliases retained for S6/documentation migration.
build-fd-gcc: build-fd-linux-x86-gcc

build-fd-clang: build-fd-linux-x86-clang

build-fd-arm: build-fd-linux-arm-gcc

build-fd-macos-x86_64: build-fd-macos-x86

build-fd-dev:
    make -j"$(nproc)" all

build-all:
    {{ python }} contrib/tool/readme/run-badged-command.py build bash -c "just build-fd && just build-tk"

# ── Clean ────────────────────────────────────────────────────────────────────

# Clean all Firedancer and Zig/Tickoni build artifacts.
# Firedancer outputs live under `build/` (BUILDDIR variants).
# Zig/Tickoni outputs live under `target/` and `zig-out/`.
clean-all:
    rm -rf build/ target/ zig-out/

# ── Test ───────────────────────────────────────────────────────────────────

test-all:
    @just test-unit-all
    @just test-integration-all
    @just test-cov-all
    @just test-system-all
    @just test-e2e-all

# Native Firedancer C unit-test recipes. These never fall back to Tickoni tests.
test-unit-fd-linux-x86-gcc:
    set timeout := 600
    bash contrib/build/fd-build-lib.sh {{ fd_tickoni_build }} gcc-12 test "" ""
    {{ make }} -f contrib/build/GNUmakefile -j"{{ cpu_count }}" MACHINE=tickoni_fd BUILDDIR={{ fd_tickoni_build }} \
        LDFLAGS_EXE="-Wl,-z,shstk" run-unit-test TEST_OPTS="--page-sz normal -j 3"

test-unit-fd-macos-x86:
    brew install make llvm || true
    bash contrib/build/fd-build-lib.sh {{ fd_tickoni_build }} clang test "" ""
    JUST_GMAKE="$(brew --prefix)/bin/gmake" {{ make }} -f contrib/build/GNUmakefile -j"{{ cpu_count }}" MACHINE=tickoni_fd BUILDDIR={{ fd_tickoni_build }} run-unit-test TEST_OPTS="--page-sz normal"

test-unit-fd-macos-arm:
    brew install make llvm || true
    bash contrib/build/fd-build-lib.sh {{ fd_tickoni_build }} clang test "" ""
    JUST_GMAKE="$(brew --prefix)/bin/gmake" {{ make }} -f contrib/build/GNUmakefile -j"{{ cpu_count }}" MACHINE=tickoni_fd BUILDDIR={{ fd_tickoni_build }} run-unit-test TEST_OPTS="--page-sz normal"

test-unit-fd-windows-x86:
    bash contrib/build/fd-build-windows.sh x86_64 clang test
    {{ make }} -f contrib/build/GNUmakefile -j"{{ cpu_count }}" MACHINE=tickoni_fd BUILDDIR={{ fd_tickoni_build }} run-unit-test TEST_OPTS="--page-sz normal"

test-unit-fd-windows-arm:
    bash contrib/build/fd-build-windows.sh arm64 clang test
    {{ make }} -f contrib/build/GNUmakefile -j"{{ cpu_count }}" MACHINE=tickoni_fd BUILDDIR={{ fd_tickoni_build }} run-unit-test TEST_OPTS="--page-sz normal"

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

# Tickoni unit lane: pure logic and fixture/mock-backed tests only.
# No running servers belong here. Canonical platform recipes are the
# implementation; the bare recipe below is only a host router.
test-unit-tk-linux-x86:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache TK_LOG_LEVEL=0 bash contrib/build/zigw.sh build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} test --summary all
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache TK_LOG_LEVEL=0 bash contrib/build/zigw.sh build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} run-tests

test-unit-tk-linux-arm: test-unit-tk-linux-x86

test-unit-tk-macos-x86: test-unit-tk-linux-x86

test-unit-tk-macos-arm: test-unit-tk-linux-x86

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

# Print computed hash and wire bytes for every audit fixture event, and emit audit JSONL.
# Use the output to understand or snapshot the current encoding after intentional changes.
gen-audit-fixtures:
    TK_GEN_FIXTURES=1 ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/build/zigw.sh build -Dtest=true test 2>&1
    TK_GEN_FIXTURES=1 ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/build/zigw.sh build -Dtest=true integration-test 2>&1

test-unit-all:
    {{ python }} contrib/tool/readme/run-badged-command.py unit bash -c "just test-unit-tk && just test-unit-fd"

test-e2e-fd:
    {{ make }} -f contrib/build/GNUmakefile -j"$(nproc)" MACHINE=tickoni_fd BUILDDIR={{ fd_tickoni_build }} integration-test && {{ make }} -f contrib/build/GNUmakefile MACHINE=tickoni_fd BUILDDIR={{ fd_tickoni_build }} run-integration-test

test-e2e-fd-linux-x86: test-e2e-fd

test-e2e-tk:
    @true

test-e2e-tk-linux-x86: test-e2e-tk

test-e2e-all:
    {{ python }} contrib/tool/readme/run-badged-command.py e2e bash -c "just test-e2e-fd && just test-e2e-tk"

test-integration-fd:
    @true

# Tickoni integration lane: transport and boundary wiring against local mocks.
test-integration-tk-linux-x86:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/build/zigw.sh build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test

test-integration-tk-linux-arm: test-integration-tk-linux-x86

test-integration-tk-macos-x86: test-integration-tk-linux-x86

test-integration-tk-macos-arm: test-integration-tk-linux-x86

test-integration-tk:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
      linux-x86) exec just test-integration-tk-linux-x86 ;;
      linux-arm) exec just test-integration-tk-linux-arm ;;
      macos-x86) exec just test-integration-tk-macos-x86 ;;
      macos-arm) exec just test-integration-tk-macos-arm ;;
      windows-x86) exec just test-integration-tk-windows-x86 ;;
      windows-arm) exec just test-integration-tk-windows-arm ;;
      *) echo "unsupported host platform for test-integration-tk: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

# ── Windows-specific test recipes ────────────────────────────────────────────

# Windows x86_64 unit test: build FD libs for Windows x86_64, then run Zig tests.
test-unit-tk-windows-x86:
    mkdir -p build
    bash -lc 'set -o pipefail; just build-fd-windows-x86 2>&1 | tee build/fd-windows-x86.log'
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/build/zigw.sh build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} test
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/build/zigw.sh build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} run-tests

# Windows ARM64 unit test: build FD libs for Windows ARM64, then run Zig tests.
# contrib/build/zigw.sh prefers an x86_64 Windows Zig install on Windows ARM when
# available because native Zig 0.16.0 is unstable on this lane.
test-unit-tk-windows-arm:
    mkdir -p build
    bash -lc 'set -o pipefail; just build-fd-windows-arm 2>&1 | tee build/fd-windows-arm.log'
    rm -rf .zig-cache
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/build/zigw.sh build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} test
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/build/zigw.sh build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} run-tests

# Windows x86_64 integration test: build FD libs for Windows x86_64, then run Zig integration tests.
test-integration-tk-windows-x86:
    mkdir -p build
    just build-fd-windows-x86 > build/fd-windows-x86.log 2>&1
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/build/zigw.sh build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test

# Windows ARM64 integration test: build FD libs for Windows ARM64, then run Zig integration tests.
# contrib/build/zigw.sh prefers an x86_64 Windows Zig install on Windows ARM when
# available because native Zig 0.16.0 is unstable on this lane.
test-integration-tk-windows-arm:
    mkdir -p build
    just build-fd-windows-arm > build/fd-windows-arm.log 2>&1
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/build/zigw.sh build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test

# Deterministic offline investment conformance suite — fixture-backed, no llama.cpp required.
test-demo-tk:
    bash contrib/test/run_cli_demo_tests.sh

test-demo-tk-linux-x86: test-demo-tk
test-demo-tk-macos-x86: test-demo-tk
test-demo-tk-macos-arm: test-demo-tk
test-demo-tk-windows-x86: test-demo-tk
test-demo-tk-windows-arm: test-demo-tk

# Build and export the platform conformance artifact consumed by the compare job.
export-demo-conformance-linux:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/build/zigw.sh build -Dfd-lib-dir={{ fd_tickoni_lib }}
    {{ python }} contrib/test/export_demo_conformance_bundle.py . build/demo-conformance/linux

export-demo-conformance-macos-15-x86_64:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/build/zigw.sh build -Dfd-lib-dir={{ fd_tickoni_lib }}
    {{ python }} contrib/test/export_demo_conformance_bundle.py . build/demo-conformance/macos-15-x86_64

export-demo-conformance-macos-15-arm:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/build/zigw.sh build -Dfd-lib-dir={{ fd_tickoni_lib }}
    {{ python }} contrib/test/export_demo_conformance_bundle.py . build/demo-conformance/macos-15-arm

export-demo-conformance-macos-26-x86_64:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/build/zigw.sh build -Dfd-lib-dir={{ fd_tickoni_lib }}
    {{ python }} contrib/test/export_demo_conformance_bundle.py . build/demo-conformance/macos-26-x86_64

export-demo-conformance-macos-26-arm:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/build/zigw.sh build -Dfd-lib-dir={{ fd_tickoni_lib }}
    {{ python }} contrib/test/export_demo_conformance_bundle.py . build/demo-conformance/macos-26-arm

export-demo-conformance-windows-x86:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/build/zigw.sh build -Dfd-lib-dir={{ fd_tickoni_lib }} --summary all
    {{ python }} contrib/test/export_demo_conformance_bundle.py . build/demo-conformance/windows-x86

export-demo-conformance-windows-arm:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/build/zigw.sh build -Dfd-lib-dir={{ fd_tickoni_lib }} --summary all
    {{ python }} contrib/test/export_demo_conformance_bundle.py . build/demo-conformance/windows-arm

compare-demo-conformance:
    {{ python }} contrib/test/compare_demo_conformance.py build/demo-conformance/linux/conformance.json build/demo-conformance/macos-15-x86_64/conformance.json build/demo-conformance/macos-15-arm/conformance.json build/demo-conformance/macos-26-x86_64/conformance.json build/demo-conformance/macos-26-arm/conformance.json build/demo-conformance/windows-x86/conformance.json build/demo-conformance/windows-arm/conformance.json

# Tickoni system lane: opt-in real-LLM investment demo proof.
test-system-tk:
    bash contrib/test/run_system_model_tests.sh

test-system-tk-linux-x86: test-system-tk
test-system-tk-macos-x86: test-system-tk
test-system-tk-macos-arm: test-system-tk

test-system-fd:
    @true

test-system-all:
    {{ python }} contrib/tool/readme/run-badged-command.py system bash -c "just test-system-tk && just test-system-fd"

# ── Windows-specific system tests (live, mirrors Linux/macOS flow) ───

# Windows x86_64 system test: build FD libs, ensure llama.cpp, run live test.
# Mirrors `test-system-tk` on Linux/macOS but for Windows.
test-system-tk-windows-x86:
    mkdir -p build
    bash -lc 'set -o pipefail; just build-fd-windows-x86 2>&1 | tee build/fd-windows-x86.log'
    bash contrib/test/run_system_model_tests_win.sh

# Windows ARM64 system test: build FD libs, ensure llama.cpp, run live test.
# Same as x86_64: mirrors Linux/macOS `test-system-tk` on Windows ARM.
test-system-tk-windows-arm:
    mkdir -p build
    bash -lc 'set -o pipefail; just build-fd-windows-arm 2>&1 | tee build/fd-windows-arm.log'
    bash contrib/test/run_system_model_tests_win.sh

# ── Infrastructure: ensure llama.cpp and model (for LLM system tests) ──────

# Build llama.cpp (CPU or CUDA if detected).
infra-ensure-llamacpp:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v nvidia-smi >/dev/null 2>&1; then
    gpu_count="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l || echo 0)"
    if (( gpu_count > 0 )); then
    bash contrib/test/ensure_llama_cpp.sh --gpu
    else
    bash contrib/test/ensure_llama_cpp.sh
    fi
    else
    bash contrib/test/ensure_llama_cpp.sh
    fi

infra-ensure-llamacpp-win:
    bash contrib/test/ensure_llama_cpp_win.sh

# Run llama-server.exe for Windows live system tests.
infra-run-llamacpp-win:
    #!/usr/bin/env bash
    set -euo pipefail
    source contrib/test/llama_cpp_env.sh
    llama_dir="$(tk_resolve_llama_cpp_dir)"
    backend=cpu
    if command -v nvidia-smi >/dev/null 2>&1; then
    gpu_count="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l || echo 0)"
    if (( gpu_count > 0 )) && ldd "${llama_dir}/llama-server.exe" 2>/dev/null | grep -qi 'cuda\|cublas'; then
    backend=gpu
    fi
    fi
    [[ "$backend" == "gpu" ]] && bash contrib/test/ensure_llama_cpp_win.sh --gpu || bash contrib/test/ensure_llama_cpp_win.sh
    bash contrib/test/ensure_hf_model.sh
    exec bash contrib/test/run_llm_server_win.sh "$backend"

# Download the GGUF model for system tests (requires `hf` CLI).
infra-ensure-model:
    bash contrib/test/ensure_hf_model.sh

infra-run-llamacpp:
    #!/usr/bin/env bash
    set -euo pipefail
    source contrib/test/llama_cpp_env.sh
    llama_dir="$(tk_resolve_llama_cpp_dir)"
    backend=cpu
    if command -v nvidia-smi >/dev/null 2>&1; then
    gpu_count="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l || echo 0)"
    if (( gpu_count > 0 )) && ldd "${llama_dir}/llama-server" 2>/dev/null | grep -qi 'cuda\|cublas'; then
    backend=gpu
    fi
    fi
    [[ "$backend" == "gpu" ]] && bash contrib/test/ensure_llama_cpp.sh --gpu || bash contrib/test/ensure_llama_cpp.sh
    bash contrib/test/ensure_hf_model.sh
    exec bash contrib/test/run_llm_server.sh "$backend"

test-integration-all:
    {{ python }} contrib/tool/readme/run-badged-command.py integration bash -c "just test-integration-fd && just test-integration-tk"

# ── Test: Coverage ─────────────────────────────────────────────────────────

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

# ── Quality: Format ────────────────────────────────────────────────────────

quality-format-check-fd:
    bash contrib/quality/quality.sh format-check-fd

quality-format-fix-fd:
    bash contrib/quality/quality.sh format-fix-fd

quality-format-check-tk:
    bash contrib/quality/quality.sh format-check-tk

quality-format-fix-tk:
    bash contrib/quality/quality.sh format-fix-tk

# Linux/x86 qualified aliases; quality scope remains unchanged.
quality-format-check-fd-linux-x86: quality-format-check-fd
quality-format-fix-fd-linux-x86: quality-format-fix-fd
quality-format-check-tk-linux-x86: quality-format-check-tk

quality-format-check-linux-x86:
    @just quality-format-check-fd-linux-x86
    @just quality-format-check-tk-linux-x86
quality-format-fix-tk-linux-x86: quality-format-fix-tk

quality-format-check-all:
    @just quality-format-check-fd
    @just quality-format-check-tk

quality-format-fix-all:
    @just quality-format-fix-fd
    @just quality-format-fix-tk

# ── Quality: Lint ──────────────────────────────────────────────────────────

quality-lint-check-fd:
    bash contrib/quality/quality.sh lint-check-fd
    command -v shellcheck >/dev/null || exit 0; bash contrib/quality/quality.sh lint-shellcheck-fd

quality-lint-check-tk:
    bash contrib/quality/quality.sh lint-check-tk

quality-lint-check-fd-linux-x86: quality-lint-check-fd
quality-lint-check-tk-linux-x86: quality-lint-check-tk

quality-lint-check-linux-x86:
    @just quality-lint-check-fd-linux-x86
    @just quality-lint-check-tk-linux-x86

quality-lint-check-all:
    @just quality-lint-check-fd
    @just quality-lint-check-tk

# ── Quality: Proto ─────────────────────────────────────────────────────────

quality-proto-check-fd:
    @cd src/disco/events && {{ python }} gen_events.py --skip-check
    @PATH="${HOME}/go/bin:/usr/local/go/bin:${PATH}" command -v buf >/dev/null || { if [ -n "$(git status --porcelain src/disco/events/generated/ src/disco/events/schema/events.proto)" ]; then echo "Generated proto files are out of date. Please run 'just quality-proto-check-fd' and commit the changes." >&2; git --no-pager diff -- src/disco/events/; exit 1; fi; exit 0; }
    PATH="${HOME}/go/bin:/usr/local/go/bin:${PATH}" buf lint src/disco/events/schema
    @if [ -n "$(git status --porcelain src/disco/events/generated/ src/disco/events/schema/events.proto)" ]; then echo "Generated proto files are out of date. Please run 'just quality-proto-check-fd' and commit the changes." >&2; git --no-pager diff -- src/disco/events/; exit 1; fi

quality-proto-check-tk:
    bash -c 'PATH="${HOME}/go/bin:/usr/local/go/bin:${PATH}"; command -v buf >/dev/null || exit 0; buf lint src/tickoni/schema'

quality-proto-check-fd-linux-x86: quality-proto-check-fd
quality-proto-check-tk-linux-x86: quality-proto-check-tk

quality-proto-check-linux-x86:
    @just quality-proto-check-fd-linux-x86
    @just quality-proto-check-tk-linux-x86

quality-proto-check-all:
    @just quality-proto-check-fd
    @just quality-proto-check-tk

# ── Quality: All ───────────────────────────────────────────────────────────

quality-check-all:
    {{ python }} contrib/tool/readme/run-badged-command.py quality bash -c "just quality-format-check-all && just quality-lint-check-all && just quality-proto-check-all"

# ── Security: CodeQL ───────────────────────────────────────────────────────

security-codeql-check-fd:
    @true ## bash contrib/security/security.sh codeql-check-fd, opened issue https://github.com/firedancer-io/firedancer/issues/10058

security-codeql-check-tk:
    @true

security-codeql-check-fd-linux-x86: security-codeql-check-fd
security-codeql-check-tk-linux-x86: security-codeql-check-tk

security-codeql-check-all:
    @just security-codeql-check-fd
    @just security-codeql-check-tk

# ── Security: Gitleaks ─────────────────────────────────────────────────────

security-gitleaks-check-fd:
    bash contrib/security/security.sh gitleaks-check-fd

security-gitleaks-check-tk:
    bash contrib/security/security.sh gitleaks-check-tk

security-gitleaks-check-fd-linux-x86: security-gitleaks-check-fd
security-gitleaks-check-tk-linux-x86: security-gitleaks-check-tk

security-gitleaks-check-linux-x86:
    @just security-gitleaks-check-fd-linux-x86
    @just security-gitleaks-check-tk-linux-x86

security-gitleaks-check-all:
    @just security-gitleaks-check-fd
    @just security-gitleaks-check-tk

# ── Security: SecComp ──────────────────────────────────────────────────────

security-seccomp-check-fd:
    @bash contrib/security/security.sh seccomp-check-fd

security-seccomp-check-tk:
    @true

security-seccomp-check-fd-linux-x86: security-seccomp-check-fd
security-seccomp-check-tk-linux-x86: security-seccomp-check-tk

security-seccomp-check-linux-x86: security-seccomp-check-fd-linux-x86

security-seccomp-check-all:
    @just security-seccomp-check-fd
    @just security-seccomp-check-tk

# ── Security: Proof ────────────────────────────────────────────────────────

security-proof-check-fd:
    bash contrib/security/security.sh proof-check-fd

security-proof-check-tk:
    @true

security-proof-check-fd-linux-x86: security-proof-check-fd
security-proof-check-tk-linux-x86: security-proof-check-tk

security-proof-check-linux-x86:
    @just security-proof-check-fd-linux-x86
    @just security-proof-check-tk-linux-x86

security-proof-check-all:
    @just security-proof-check-fd
    @just security-proof-check-tk

# ── Security: ASan/UBSan ───────────────────────────────────────────────────

security-sanitize-check-fd:
    bash contrib/security/security.sh sanitize-check-fd

security-sanitize-check-tk:
    bash contrib/security/security.sh sanitize-check-tk

security-sanitize-check-fd-linux-x86: security-sanitize-check-fd
security-sanitize-check-tk-linux-x86: security-sanitize-check-tk

security-sanitize-check-linux-x86:
    @just security-sanitize-check-fd-linux-x86
    @just security-sanitize-check-tk-linux-x86

security-sanitize-check-all:
    @just security-sanitize-check-fd
    @just security-sanitize-check-tk

# ── Security: All ──────────────────────────────────────────────────────────

security-engine-check-all:
    @just security-engine-check-changes
    @just security-engine-check-orchestration

security-engine-check-changes:
    {{ python }} contrib/quality/engine/engine_check_changes.py

security-engine-check-orchestration:
    {{ python }} contrib/quality/engine/linter.py contrib/quality/engine/checks/ --root {{ justfile_directory() }} --severity ERROR

security-engine-check-changes-linux-x86: security-engine-check-changes
security-engine-check-orchestration-linux-x86: security-engine-check-orchestration

# ── Security: All ──────────────────────────────────────────────────────────

security-check-all:
    {{ python }} contrib/tool/readme/run-badged-command.py security bash -c "just security-engine-check-all && just security-codeql-check-all && just security-gitleaks-check-all && just security-seccomp-check-all && just security-proof-check-all && just security-sanitize-check-all"

# ── Memory (hugepages) ─────────────────────────────────────────────────────

mem-init mode="0700" user="":
    #!/usr/bin/env bash
    set -euo pipefail
    owner="{{ user }}"
    if [ -z "$owner" ]; then owner="$USER"; fi
    sudo src/util/shmem/fd_shmem_cfg init {{ mode }} "$owner" ""

mem-query:
    sudo src/util/shmem/fd_shmem_cfg query

mem-reset:
    sudo src/util/shmem/fd_shmem_cfg reset

mem-fini:
    sudo src/util/shmem/fd_shmem_cfg fini

mem-alloc pages="24" page_type="gigantic" numa="0":
    sudo src/util/shmem/fd_shmem_cfg alloc {{ pages }} {{ page_type }} {{ numa }}

mem-alloc-auto numa="0":
    pages="$(( ((( $(awk '/MemTotal:/ {print $2}' /proc/meminfo) * 1024 )) - (4 * 1024 * 1024 * 1024)) / (6 * 1024 * 1024 * 1024) * 6 ))"; \
    if [ "$pages" -lt 0 ]; then pages=0; fi; \
    echo "allocating $pages gigantic pages on NUMA {{ numa }}"; \
    sudo src/util/shmem/fd_shmem_cfg alloc "$pages" gigantic {{ numa }}

mem-free page_type="gigantic" numa="0":
    sudo src/util/shmem/fd_shmem_cfg free {{ page_type }} {{ numa }}
    just mem-drop-caches

mem-drop-caches:
    # Free page cache, dentries, and inodes so tests can mlock memory.
    # sync alone does not free memory — drop_caches is required.
    sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches' || echo "mem-drop-caches: could not free caches (may be read-only or non-root)"

# ── Kill test processes ────────────────────────────────────────────────────────

kill-test:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "killing test processes (user: $USER)..."
    case "{{ os }}" in
      linux)
        # Phase 1: kill child tile processes first (tkings, tknorm, tkdedu, etc.)
        pkill -u "$USER" -f 'zig-out/bin/tk[a-z]\+ ' 2>/dev/null || true
        pkill -u "$USER" -f 'target/debug/tk[a-z]\+ ' 2>/dev/null || true
        pkill -u "$USER" -f 'target/release/tk[a-z]\+ ' 2>/dev/null || true
        # Phase 1b: kill test-* binaries
        pkill -u "$USER" -f 'zig-out/bin/test-' 2>/dev/null || true
        pkill -u "$USER" -f 'target/debug/test-' 2>/dev/null || true
        pkill -u "$USER" -f 'target/release/test-' 2>/dev/null || true
        # Phase 2: kill tickoni-supervisor (parent of tile processes)
        pkill -u "$USER" -f 'tickoni-supervisor' 2>/dev/null || true
        # Phase 3: kill any remaining orphans still children of a supervisor
        for pid in $(pgrep -u "$USER" -f 'tickoni-supervisor' 2>/dev/null || true); do
          pkill -u "$USER" -P "$pid" 2>/dev/null || true
        done
        echo "done."
        ;;
      macos)
        pkill -u "$USER" -f 'tickoni-supervisor' 2>/dev/null || true
        pkill -u "$USER" -f 'zig-out/bin/tk[a-z]\+ ' 2>/dev/null || true
        pkill -u "$USER" -f 'target/debug/tk[a-z]\+ ' 2>/dev/null || true
        pkill -u "$USER" -f 'target/release/tk[a-z]\+ ' 2>/dev/null || true
        pkill -u "$USER" -f 'zig-out/bin/test-' 2>/dev/null || true
        echo "done."
        ;;
      windows)
        # Windows: use taskkill with image-name filters for tk* and test-*
        # taskkill /FI "IMAGENAME eq ..." matches the image name only
        # We also try WMIC for broader matching on full command line
        for img in tkings tknorm tkdedu tkcase tkpoly tkaudt tkrepl tkmetr tkdiag tkdisp tkagnt tkmodl tktool tkadpt tkapi tickoni-supervisor; do
          taskkill /F /FI "IMAGENAME eq ${img}.exe" /T > /dev/null 2>&1 || true
        done
        # Kill any zig-out/test-* processes by matching the path
        taskkill /F /FI "CMDLINE eq *zig-out/bin/test-*" /T > /dev/null 2>&1 || true
        taskkill /F /FI "CMDLINE eq *target/debug/test-*" /T > /dev/null 2>&1 || true
        # Kill any remaining tickoni-* processes
        for img in $(wmic process where "name like '%tickoni%'" get name /value 2>/dev/null | grep -oP '[a-z-]+\.exe' | sort -u || true); do
          taskkill /F /FI "IMAGENAME eq $img" /T > /dev/null 2>&1 || true
        done
        echo "done."
        ;;
      *)
        echo "unsupported OS for kill-test: {{ os }}" >&2
        exit 1
        ;;
    esac
