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

  if command -v python >/dev/null 2>&1 && python -c 'import sys' >/dev/null 2>&1; then
    command -v python
    return 0
  fi

  if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys' >/dev/null 2>&1; then
    command -v python3
    return 0
  fi

  printf 'error: no working Python interpreter found (tried py -3, python, python3)\n' >&2
  return 1
}

resolve_python "$@"
