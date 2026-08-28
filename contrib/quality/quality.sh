#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

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
Usage: bash contrib/quality.sh <command>

Commands:
  format-check-fd   Check C source formatting (trailing whitespace)
  format-fix-fd     Fix C source formatting (trailing whitespace)
  format-check-tk   Check Zig source formatting (zig fmt)
  format-fix-tk     Fix Zig source formatting (zig fmt)
  lint-check-fd        Lint C source (style, include guards)
  lint-shellcheck-fd   Shellcheck shell scripts in changed files
  lint-check-tk        Lint Zig source (compilation check)
EOF
}


run_include_guard_check() {
  local out
  out="$(mktemp)"
  python3 contrib/lint/check_include_guards.py "$@" >"$out"
  if [ -s "$out" ]; then
    cat "$out"
    rm -f "$out"
    return 1
  fi
  rm -f "$out"
}

run_shellcheck() {
  local scripts=()
  local f
  for f in "$@"; do
    [[ -f "$f" ]] && grep -qE '^#!.*\b(sh|bash)\b' "$f" && scripts+=("$f")
  done
  [ "${#scripts[@]}" -gt 0 ] || return 0
  shellcheck "${scripts[@]}"
}

run_style_grep() {
  local fail=0

  # Control flow keywords must not have a space before the paren (CONTRIBUTING.md §3.2)
  if grep -n 'if (' "$@"; then fail=1; fi
  if grep -n 'for (' "$@"; then fail=1; fi
  if grep -n 'while (' "$@"; then fail=1; fi
  if grep -n 'switch (' "$@"; then fail=1; fi

  # #pragma once is forbidden; use #ifndef include guards (CONTRIBUTING.md §1.4)
  if grep -n '#pragma once' "$@"; then fail=1; fi

  # Use fd_util_base.h integer types; stdint.h types are forbidden (CONTRIBUTING.md §4.1)
  if grep -nwE '(u?int(8|16|32|64)_t|size_t|ptrdiff_t)' "$@"; then fail=1; fi
  if grep -n '#include <stdint.h>' "$@"; then fail=1; fi

  # Use int instead of bool; stdbool.h is forbidden (CONTRIBUTING.md §4.2)
  # Exclude macro invocations like CFG_POP( bool, ...) where bool is a token
  # argument used for function-name concatenation, not the C bool type.
  if grep -nw 'bool' "$@" | grep -Ev '[[:upper:]_]+[[:space:]]*\([[:space:]]*bool'; then fail=1; fi
  if grep -n '#include <stdbool.h>' "$@"; then fail=1; fi

  return "$fail"
}

our_changed_files() {
  { git log --first-parent --no-merges --diff-filter=AM --name-only --format="" main..HEAD
    git diff --diff-filter=AM --name-only
    git diff --cached --diff-filter=AM --name-only
    git ls-files --others --exclude-standard; } | sort -u
}

# Return only the 5 FD tree dirs that the tickoni_fd scope covers.
fd_scope_files() {
  our_changed_files | grep -E '^src/(tango|util|ballet|disco|waltz)/'
}

cmd_format_check_fd() {
  mapfile -t files < <(fd_scope_files)
  [ "${#files[@]}" -gt 0 ] || return 0
  run_step "trailing whitespace" pre-commit run trailing-whitespace --files "${files[@]}"
}

cmd_format_fix_fd() {
  mapfile -t files < <(fd_scope_files)
  [ "${#files[@]}" -gt 0 ] || return 0
  run_step "trailing whitespace fix" pre-commit run trailing-whitespace --files "${files[@]}"
}

cmd_format_check_tk() {
  run_step "zig fmt check" zig fmt --check src/app/tickoni src/tickoni
}

cmd_format_fix_tk() {
  run_step "zig fmt" zig fmt src/app/tickoni src/tickoni
}

cmd_lint_check_fd() {
  local files
  mapfile -t files < <(fd_scope_files)
  [ "${#files[@]}" -gt 0 ] || return 0

  local ch_files=()
  mapfile -t ch_files < <(printf '%s\n' "${files[@]}" | grep -E '\.(c|h)$')
  if [ "${#ch_files[@]}" -gt 0 ]; then
    run_step "style grep" run_style_grep "${ch_files[@]}"
    run_step "include guards" run_include_guard_check "${ch_files[@]}"
  fi

}

cmd_lint_shellcheck_fd() {
  local files
  mapfile -t files < <(fd_scope_files)
  [ "${#files[@]}" -gt 0 ] || return 0
  run_step "shellcheck" run_shellcheck "${files[@]}"
}

cmd_lint_check_tk() {
  run_step "zig build check" zig build -Dfd-lib-dir=build/fd-tickoni-fd/lib
}

case "${1:-}" in
  format-check-fd) cmd_format_check_fd ;;
  format-fix-fd)   cmd_format_fix_fd ;;
  format-check-tk) cmd_format_check_tk ;;
  format-fix-tk)   cmd_format_fix_tk ;;
  lint-check-fd)      cmd_lint_check_fd ;;
  lint-shellcheck-fd) cmd_lint_shellcheck_fd ;;
  lint-check-tk)      cmd_lint_check_tk ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
