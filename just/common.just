# Prefer GNU Make 4.x (Homebrew installs it as `gmake` on macOS); fall back to `make`.
# Firedancer's GNUmakefile uses `undefine`, which needs GNU Make >= 3.82.
make := `command -v gmake || command -v make`
# Resolve one usable Python command for all recipes, including Windows CI.
python := `bash contrib/setup/python.sh`

# ── Justfile Recipe Alias Convention ───────────────────────────────────────────
# Every recipe category (build, test, setup, quality, security, etc.) has:
#   1. A bare dispatcher (e.g. `build-tk:`) with a bash `case` that routes
#      to the correct platform recipe based on `{{ os }}-{{ arch }}`.
#   2. One canonical implementation per platform (e.g. `build-tk-linux-x86:`).
#   3. Platform aliases that use make's `target: dependency` syntax to
#      forward to a single canonical implementation — e.g.
#        test-unit-tk-macos-x86: test-unit-tk-linux-x86
#      This relies on GNU make recipe inheritance (not `just` alias syntax).
#
# RULES:
#   - When adding a new platform, update the bare dispatcher's `case` AND
#     create aliases for every existing category that has platform variants.
#   - Only the canonical implementation has actual commands; aliases are
#     zero-body forwarding lines of the form `alias-name: canonical-name`.
#   - The `: alias` syntax here is make's target-dependency, NOT just's
#     `alias = recipe` syntax — the distinction matters for shellcheck.
#
# To list all aliases in a category: just --list | grep '<category>'
#

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

# ── Minimal CI setup recipes ─────────────────────────────────────────────────
# Each workflow calls the minimal recipe that installs only what it needs.
# This avoids over-installing tools like quality/lint/Go when only gitleaks
# or a build toolchain is required.

# Build-only: compilers + build infra (no zig, no ssl, no quality, no secrets)
setup-build-linux-x86-gcc:
    python3 contrib/setup/orchestrator.py build

setup-build-linux-x86-clang:
    python3 contrib/setup/orchestrator.py build

setup-build-macos-x86:
    python3 contrib/setup/orchestrator.py build

setup-build-macos-arm:
    python3 contrib/setup/orchestrator.py build

setup-build-linux-arm-gcc:
    python3 contrib/setup/orchestrator.py build

# Windows build-only setup: no llama.cpp; system-test setup owns the LLM.
setup-build-windows-x86:
    {{ python }} contrib/setup/orchestrator.py build,mvsc --platform windows-x86

setup-build-windows-arm:
    {{ python }} contrib/setup/orchestrator.py build,mvsc --platform windows-arm

# Engine build: full FD toolchain (build + zig + ssl + gcc)
setup-fd-linux-x86-gcc:
    python3 contrib/setup/orchestrator.py build
    python3 contrib/setup/orchestrator.py zig,ssl

setup-fd-linux-x86-clang:
    python3 contrib/setup/orchestrator.py build
    python3 contrib/setup/orchestrator.py zig,ssl

setup-fd-macos-x86:
    python3 contrib/setup/orchestrator.py build
    python3 contrib/setup/orchestrator.py zig,ssl

setup-fd-macos-arm:
    python3 contrib/setup/orchestrator.py build
    python3 contrib/setup/orchestrator.py zig,ssl

setup-fd-linux-arm-gcc:
    python3 contrib/setup/orchestrator.py build
    python3 contrib/setup/orchestrator.py zig,ssl

# Windows x86_64 — FD toolchain (zig + ssl)
setup-fd-windows-x86:
    {{ python }} contrib/setup/orchestrator.py build,mvsc,zig,ssl --platform windows-x86

# Windows ARM64 — FD toolchain (zig + ssl)
setup-fd-windows-arm:
    {{ python }} contrib/setup/orchestrator.py build,mvsc,zig,ssl --platform windows-arm

# Quality: build + quality tools (shellcheck, actionlint, yamllint, pre-commit, buf + go)
setup-quality-linux-x86:
    python3 contrib/setup/orchestrator.py quality

# Secrets-only: gitleaks (no quality, no build tools beyond what gitleaks needs)
setup-gitleaks-linux-x86:
    python3 contrib/setup/orchestrator.py secrets

# Full developer stack (unchanged)
# Auto-detect host platform/arch and route to the correct setup recipe.
# All setup is delegated to orchestrator.py — it detects the platform and
# resolves dependencies from tool-versions.json.
setup-env toolchain="":
    SKIP_IDEMPOTENCY=`echo ${SKIP_IDEMPOTENCY:-}` python3 contrib/setup/orchestrator.py dev
    just setup-git

# Activate tracked git hooks (commit-msg strips anthropic AI co-authors)
setup-git:
    git config core.hooksPath .githooks
    chmod +x .githooks/commit-msg

# All setup is delegated to orchestrator.py — it detects the platform and
# resolves dependencies from tool-versions.json.

# Linux x86_64 — GCC toolchain
setup-linux-x86-gcc:
    python3 contrib/setup/orchestrator.py build
    python3 contrib/setup/orchestrator.py zig,ssl,ops
    python3 contrib/setup/orchestrator.py quality,secrets

# Linux x86_64 — Clang toolchain
setup-linux-x86-clang:
    python3 contrib/setup/orchestrator.py build
    python3 contrib/setup/orchestrator.py zig,ssl,ops
    python3 contrib/setup/orchestrator.py quality,secrets

# Linux aarch64 — GCC toolchain
setup-linux-arm-gcc:
    python3 contrib/setup/orchestrator.py build
    python3 contrib/setup/orchestrator.py zig,ssl,ops
    python3 contrib/setup/orchestrator.py quality,secrets

# Linux aarch64 — Clang toolchain
setup-linux-arm-clang:
    python3 contrib/setup/orchestrator.py build
    python3 contrib/setup/orchestrator.py zig,ssl,ops
    python3 contrib/setup/orchestrator.py quality,secrets

# macOS x86_64
setup-macos-x86:
    python3 contrib/setup/orchestrator.py build
    python3 contrib/setup/orchestrator.py zig,ssl,ops
    python3 contrib/setup/orchestrator.py quality

# macOS ARM64
setup-macos-arm:
    python3 contrib/setup/orchestrator.py build
    python3 contrib/setup/orchestrator.py zig,ssl,ops
    python3 contrib/setup/orchestrator.py quality

# Windows x86_64 — dev mode (includes LLM tooling)
setup-windows-x86:
    {{ python }} contrib/setup/orchestrator.py build,mvsc,zig,ssl,quality,secrets --platform windows-x86

# Windows ARM64 — dev mode (includes LLM tooling)
setup-windows-arm:
    {{ python }} contrib/setup/orchestrator.py build,mvsc,zig,ssl,quality,secrets --platform windows-arm

setup-fd-deps-linux-x86-gcc:
    python3 contrib/setup/orchestrator.py fd

setup-fd-deps-linux-x86-clang:
    python3 contrib/setup/orchestrator.py fd

setup-fd-deps-linux-arm-gcc:
    python3 contrib/setup/orchestrator.py fd

setup-fd-deps-macos-x86:
    python3 contrib/setup/orchestrator.py fd

setup-fd-deps-macos-arm:
    python3 contrib/setup/orchestrator.py fd

setup-coverage-linux-x86-clang:
    python3 contrib/setup/orchestrator.py coverage,toolchain

# ── FD deps for platforms missing them ─────────────────────────────────────
setup-fd-deps-windows-x86:
    {{ python }} contrib/setup/orchestrator.py fd --platform windows-x86

setup-fd-deps-windows-arm:
    {{ python }} contrib/setup/orchestrator.py fd --platform windows-arm

# ── Quality setup for all platforms ─────────────────────────────────────────
setup-quality-macos-x86:
    python3 contrib/setup/orchestrator.py quality

setup-quality-macos-arm:
    python3 contrib/setup/orchestrator.py quality

setup-quality-windows-x86:
    {{ python }} contrib/setup/orchestrator.py quality --platform windows-x86

setup-quality-windows-arm:
    {{ python }} contrib/setup/orchestrator.py quality --platform windows-arm

# ── Secrets/gitleaks for all platforms ──────────────────────────────────────
setup-gitleaks-macos-x86:
    python3 contrib/setup/orchestrator.py secrets

setup-gitleaks-macos-arm:
    python3 contrib/setup/orchestrator.py secrets

setup-gitleaks-windows-x86:
    {{ python }} contrib/setup/orchestrator.py secrets --platform windows-x86

setup-gitleaks-windows-arm:
    {{ python }} contrib/setup/orchestrator.py secrets --platform windows-arm

# ── Coverage for macOS ──────────────────────────────────────────────────────
setup-coverage-macos-x86:
    python3 contrib/setup/orchestrator.py coverage

setup-coverage-macos-arm:
    python3 contrib/setup/orchestrator.py coverage

# ── Security/formal-verification (CBMC suite) ───────────────────────────────
setup-security-linux-x86:
    python3 contrib/setup/orchestrator.py security

setup-security-macos-x86:
    python3 contrib/setup/orchestrator.py security

setup-security-windows-x86:
    {{ python }} contrib/setup/orchestrator.py security --platform windows-x86

# ── Qt 6 installation (for Qt terminal) ──────────────────────────────────────
# Credentials from .env file (local) or GitHub secrets (CI).
# Local: copy .env.example → .env and fill in QT_USERNAME and QT_TOKEN
# CI: set QT_USERNAME and QT_TOKEN as repository secrets
#   → they propagate to the runner env automatically.
# Note: orchestrator.py automatically loads .env when present.

setup-qt-linux-x86:
    python3 contrib/setup/orchestrator.py qt --platform linux-x86

setup-qt-linux-arm:
    python3 contrib/setup/orchestrator.py qt --platform linux-arm

setup-qt-macos-x86:
    python3 contrib/setup/orchestrator.py qt --platform macos-x86

setup-qt-macos-arm:
    python3 contrib/setup/orchestrator.py qt --platform macos-arm

setup-qt-windows-x86:
    {{ python }} contrib/setup/orchestrator.py qt --platform windows-x86

setup-qt-windows-arm:
    {{ python }} contrib/setup/orchestrator.py qt --platform windows-arm

test-prep-linux-x86:
    # NO-OP — memory setup moved to workflow YAML where sudo is available.

# ── Cross-category dispatchers ────────────────────────────────────────────────

tests-all:
    @just build-all
    @just quality-check-all
    @just security-check-all
    @just security-engine-check-changes
    @just test-all

test-all:
    @just test-unit-all
    @just test-integration-all
    @just test-cov-all
    @just test-system-all
    @just test-e2e-all

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

# ── Kill test processes ──────────────────────────────────────────────────────

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
