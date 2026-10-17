# ── Variable Definitions ─────────────────────────────────────────────────────
# Shared variable definitions for all justfile recipes.
# Included first so all categories have access to variables.

# Prefer GNU Make 4.x (Homebrew installs it as `gmake` on macOS); fall back to `make`.
# Firedancer's GNUmakefile uses `undefine`, which needs GNU Make >= 3.82.
make := `command -v gmake || command -v make`

# ── Justfile directory ────────────────────────────────────────────────────────
# Resolved at import time so all recipes get a stable repo-root path.
# Used by perf.just dispatchers and any recipe that cd's into the repo root.
justfile_dir := `git rev-parse --show-toplevel`

# Resolve one usable Python command for all recipes, including Windows CI.
python := `bash contrib/setup/python.sh`

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

# ── Firedancer build directories ──────────────────────────────────────────────
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

fd_cov_build := "fd-cov"
fd_cov_dir   := "build/fd-cov"
fd_cov_lib   := "build/fd-cov/lib"

# ── Zig caches ────────────────────────────────────────────────────────────────
ZIG_CACHE := "build/.zig-cache"
ZIG_GLOBAL_CACHE := "build/.zig-global-cache"
ZIG_PREFIX := "build/zig-out"
ZIG_PREFIX_REL := "build/zig-out"

# CI build artifacts are consumed on different Linux x86_64 hosts. Keep Zig
# code generation on the same Haswell baseline as the Firedancer archives.
zig_linux_x86_cpu := "-Dcpu=haswell"
