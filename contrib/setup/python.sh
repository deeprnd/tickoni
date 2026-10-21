#!/usr/bin/env bash
# Resolve the Python interpreter used by justfile recipes.
#
# Windows runners can expose Microsoft Store aliases named python/python3.
# Validate each candidate by executing it instead of trusting PATH resolution.
set -euo pipefail

resolve_python() {
  if command -v py >/dev/null 2>&1 && py -3 -c 'import sys' >/dev/null 2>&1; then
    printf 'py -3\n'
    return 0
  fi

  # On Windows, `python` and `python3` may be MS Store aliases that pass
  # `command -v` but fail when invoked. Detect the alias by running with
  # --version (alias shows the store message; real Python prints x.y.z).
  for _candidate in python python3; do
    if command -v "$_candidate" >/dev/null 2>&1; then
      # Capture stdout; MS Store alias prints to stdout, not stderr.
      _ver="$($_candidate --version 2>/dev/null)" || continue
      # Real Python: "Python X.Y.Z …". MS Store alias: "Python was not found …"
      if printf '%s\n' "$_ver" | grep -q '^Python [0-9]'; then
        command -v "$_candidate"
        return 0
      fi
    fi
  done

  printf 'error: no working Python interpreter found (tried py -3, python, python3)\n' >&2
  return 1
}

resolve_python "$@"
