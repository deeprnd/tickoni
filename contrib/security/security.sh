#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

MAKE_RUNNER=(python3 ./contrib/build/orchestrator.py make)
# CODEQL_THRESHOLD_CHECK and CODEQL_HIGH_SECURITY_THRESHOLD were part of a
# previous codeql-threshold-check design that was never wired into a command.
# Kept as comments for future reference; remove if codeql-threshold-check
# is ever implemented and wired into a `cmd_codeql_threshold` entry point.

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
Usage: bash contrib/security/security.sh <command>

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
  run_step "codeql pack install" codeql pack install contrib/security/codeql/test
  run_step "codeql pack tests" codeql test run contrib/security/codeql/test
  run_step "codeql pack download" codeql pack download codeql/cpp-queries
  rm -rf build/codeql-db
  # Single quotes intentional: $(nproc) must expand inside the bash -c
  # subshell, not at script-definition time.
  # shellcheck disable=SC2016
  run_step "codeql database create" \
    bash -c 'BUILDDIR=codeql codeql database create --language=c-cpp --command="make -f contrib/build/GNUmakefile -j$(nproc) firedancer" build/codeql-db'
  run_step "codeql database analyze" \
    codeql database analyze \
      build/codeql-db \
      codeql/cpp-queries:codeql-suites/cpp-code-scanning.qls \
      contrib/security/codeql/src/nightly \
      --format=sarif-latest \
      --output=build/codeql-results.sarif
}

cmd_gitleaks_check_fd() {
  run_step "gitleaks fd" \
    gitleaks detect --no-git --verbose --source src/ \
      --config contrib/security/gitleaks-fd.toml
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
  if ! command -v clang >/dev/null 2>&1; then
    echo "sanitize-check-fd requires clang on PATH" >&2
    return 1
  fi

  # Use the shared FD builder so the Makefile path, Tickoni machine profile,
  # source scope, extras, and unit-test target stay in one place.
  run_step "clang asan+ubsan unit-test" \
    python3 contrib/build/orchestrator.py --ldflags="-Wl,-z,shstk" build-fd clang-asan-ubsan test \
      clang "asan ubsan blst zstd lz4"
}

cmd_sanitize_check_tk() {
  # Build the Firedancer C libs that Tickoni's Zig code depends on.
  # fd-build-lib.sh compiles the 5 libs (fd_tango, fd_util, fd_ballet,
  # fd_disco, fd_waltz) plus their third-party deps, then writes the
  # Windows Zig link-manifest files into the same lib dir.
  run_step "build fd-tickoni-fd libs" \
    python3 contrib/build/orchestrator.py build-fd fd-tickoni-fd test gcc "lz4 blst zstd nanopb"
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
