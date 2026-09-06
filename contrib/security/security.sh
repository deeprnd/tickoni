#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

# Source platform.sh for cross-platform OS/arch detection
source "${ROOT_DIR}/contrib/platform.sh"

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
  # Firedancer (clang + ASan/UBSan)
  sanitize-check-fd   Build fd with Clang ASan + UBSan

  # Tickoni (gcc + Zig ReleaseSafe)
  sanitize-check-tk   Build tk with ReleaseSafe (Zig built-in safety checks)

  # Qt terminal (cmake + clang + Qt6)
  sanitize-check-qt   Build Qt terminal with Clang ASan + UBSan via CMake

  # Convenience: runs all three sequentially
  sanitize-check-all  Runs sanitize-check-fd, sanitize-check-tk, sanitize-check-qt

  # Secret scanning
  gitleaks-check-fd   Secret scanning on fd source tree
  gitleaks-check-tk   Secret scanning on tk source tree
  seccomp-check-fd    Verify seccomp policies for fd tiles
  proof-check-fd      CBMC proof checks on C source
  sanitize-check-fd   Build fd with Clang ASan + UBSan
  sanitize-check-tk   Build tk with ReleaseSafe (Zig built-in safety checks)

  # Qt checks
  gitleaks-check-qt   Secret scanning on Qt terminal source tree
  sanitize-check-qt   Build Qt terminal with Clang ASan + UBSan
  seccomp-check-qt    N/A — Qt not in financial event path
  proof-check-qt      N/A — no CBMC for Qt
  codeql-check-qt     N/A — no CodeQL
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

# ── Qt Security Checks ────────────────────────────────────────────────────────

cmd_gitleaks_check_qt() {
  run_step "gitleaks qt" \
    gitleaks detect --no-git --verbose --source src/tickoni/terminal
}

cmd_sanitize_check_qt() {
  if ! command -v cmake >/dev/null 2>&1; then
    echo "sanitize-check-qt requires cmake on PATH" >&2
    return 1
  fi
  if ! command -v clang >/dev/null 2>&1; then
    echo "sanitize-check-qt requires clang on PATH" >&2
    return 1
  fi

  # Ensure Qt6 is installed (self-contained — CI no longer needs a separate setup step)
  local _os
  _os="$(tk_os)"
  local _arch
  _arch="$(tk_arch)"
  local qt_setup
  case "${_os}" in
    linux)   case "${_arch}" in x86) qt_setup="setup-qt-linux-x86" ;; arm) qt_setup="setup-qt-linux-arm" ;; *) echo "unsupported arch $_arch"; exit 1 ;; esac ;;
    macos)   case "${_arch}" in x86) qt_setup="setup-qt-macos-x86" ;; arm) qt_setup="setup-qt-macos-arm" ;; *) echo "unsupported arch $_arch"; exit 1 ;; esac ;;
    *) echo "unsupported OS $_os"; exit 1 ;;
  esac
  run_step "setup qt6" just "$qt_setup"

  rm -rf build/tickoni-terminal-sanitize
  run_step "qt cmake sanitize configure" \
    cmake -S src/tickoni/terminal -B build/tickoni-terminal-sanitize \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined -g" \
      -DCMAKE_C_FLAGS="-fsanitize=address,undefined -g"
  run_step "qt cmake build" \
    cmake --build build/tickoni-terminal-sanitize -j "$(nproc)"
}

cmd_seccomp_check_qt() {
  echo "N/A — Qt terminal is not in the financial event path"
}

cmd_proof_check_qt() {
  echo "N/A — no CBMC formal verification for Qt"
}

cmd_codeql_check_qt() {
  echo "N/A — no CodeQL"
}

case "${1:-}" in
  codeql-check-fd)   cmd_codeql_check_fd ;;
  codeql-check-qt)   cmd_codeql_check_qt ;;
  gitleaks-check-fd) cmd_gitleaks_check_fd ;;
  gitleaks-check-tk) cmd_gitleaks_check_tk ;;
  gitleaks-check-qt) cmd_gitleaks_check_qt ;;
  seccomp-check-fd)  cmd_seccomp_check_fd ;;
  seccomp-check-qt)  cmd_seccomp_check_qt ;;
  proof-check-fd)    cmd_proof_check_fd ;;
  proof-check-qt)    cmd_proof_check_qt ;;
  sanitize-check-fd) cmd_sanitize_check_fd ;;
  sanitize-check-tk) cmd_sanitize_check_tk ;;
  sanitize-check-qt) cmd_sanitize_check_qt ;;
  sanitize-check-all)
    cmd_sanitize_check_fd
    cmd_sanitize_check_tk
    cmd_sanitize_check_qt
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
