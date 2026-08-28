#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MAKE_RUNNER=(./contrib/make-j)
CODEQL_THRESHOLD_CHECK=(python3 ./contrib/codeql-threshold-check.py)
CODEQL_HIGH_SECURITY_THRESHOLD=4.0

log() {
  printf '\n[%s] %s\n' "$1" "$2"
}

run_step() {
  local name="$1"
  shift
  log "run" "$name"
  "$@"
}

usage() {
  cat <<'EOF'
Usage: bash contrib/security.sh <command>

Commands:
  codeql-check-fd     CodeQL analysis on C source
  gitleaks-check-fd   Secret scanning on fd source tree
  gitleaks-check-tk   Secret scanning on tk source tree
  seccomp-check-fd    Verify seccomp policies for fd tiles
  proof-check-fd      CBMC proof checks on C source
  sanitize-check-fd   Build fd with Clang ASan + UBSan
  sanitize-check-tk   Build tk with ReleaseSafe (Zig built-in safety checks)
EOF
}

cmd_codeql_check_fd() {
  run_step "codeql pack install" codeql pack install contrib/codeql/test
  run_step "codeql pack tests" codeql test run contrib/codeql/test
  run_step "codeql pack download" codeql pack download codeql/cpp-queries
  rm -rf build/codeql-db
  run_step "codeql database create" \
    bash -c 'BUILDDIR=codeql codeql database create --language=c-cpp --command="make -j$(nproc) firedancer" build/codeql-db'
  run_step "codeql database analyze" \
    codeql database analyze \
      build/codeql-db \
      codeql/cpp-queries:codeql-suites/cpp-code-scanning.qls \
      contrib/codeql/src/nightly \
      --format=sarif-latest \
      --output=build/codeql-results.sarif
}

cmd_gitleaks_check_fd() {
  run_step "gitleaks fd" \
    gitleaks detect --no-git --verbose --source src/ \
      --config contrib/gitleaks-fd.toml
}

cmd_gitleaks_check_tk() {
  run_step "gitleaks tk" \
    gitleaks detect --no-git --verbose --source src/tickoni
  run_step "gitleaks app/tickoni" \
    gitleaks detect --no-git --verbose --source src/app/tickoni
}

cmd_seccomp_check_fd() {
  run_step "seccomp policies" "${MAKE_RUNNER[@]}" seccomp-policies
  _seccomp_diff="$(git status --porcelain | grep seccomp || true)"
  if [ -n "$_seccomp_diff" ]; then
    echo "Generated seccomp files are out of date. Please run 'just security-seccomp-check-fd' and commit the changes." >&2
    git --no-pager diff -- '*_seccomp.h' '*.seccomppolicy'
    exit 1
  fi
}

cmd_proof_check_fd() {
  run_step "proof checks" "${MAKE_RUNNER[@]}" proof
}

cmd_sanitize_check_fd() {
  # Source the shared FD lib definitions so the 5-lib scope stays in one place.
  # contrib/fd-tk-libs.sh defines FD_TK_LIB_SRCS, FD_TK_LIB_EXCLUDES, etc.
  source contrib/fd-tk-libs.sh
  local _local_mks
  _local_mks=$(fd_compute_mks "${FD_TK_LIB_TEST_SRCS[@]}")
  # Always rebuild libs first (they depend on EXTRAS flags), then build unit tests.
  # Use -B to force rebuild: if EXTRAS changed the FD_HAS_* defs, stale .a files
  # from a previous build with different EXTRAS would silently link wrong code.
  run_step "clang asan+ubsan lib" \
    make -B -j"$(nproc)" BUILDDIR=clang-asan-ubsan CC=clang EXTRAS="asan ubsan blst zstd lz4" \
      "LOCAL_MKS=$_local_mks" "LDFLAGS_EXE=-Wl,-z,shstk" \
      lib
  run_step "clang asan+ubsan unit-test" \
    make -j"$(nproc)" BUILDDIR=clang-asan-ubsan CC=clang EXTRAS="asan ubsan blst zstd lz4" \
      "LOCAL_MKS=$_local_mks" "LDFLAGS_EXE=-Wl,-z,shstk" \
      unit-test
}

cmd_sanitize_check_tk() {
  run_step "zig releasesafe" \
    zig build -Dtest=true test -Dfd-lib-dir=build/fd-tickoni-fd/lib -Doptimize=ReleaseSafe
}

case "${1:-}" in
  codeql-check-fd)   cmd_codeql_check_fd ;;
  gitleaks-check-fd) cmd_gitleaks_check_fd ;;
  gitleaks-check-tk) cmd_gitleaks_check_tk ;;
  seccomp-check-fd)  cmd_seccomp_check_fd ;;
  proof-check-fd)    cmd_proof_check_fd ;;
  sanitize-check-fd)  cmd_sanitize_check_fd ;;
  sanitize-check-tk)  cmd_sanitize_check_tk ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
