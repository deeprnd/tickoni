#!/usr/bin/env bash
# Run FD C unit-test binaries sequentially.
# Usage: run_unit_tests.sh --tests <file> [--page-sz <sz>] [-j <n>]
set -uo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 --tests <test-list> [--page-sz <sz>] [-j <n>]" >&2
  exit 1
fi

TESTS_FILE=""
PAGE_SZ="normal"
JOBS=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tests) TESTS_FILE="$2"; shift 2 ;;
    --page-sz) PAGE_SZ="$2"; shift 2 ;;
    -j) JOBS="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ ! -f "$TESTS_FILE" ]]; then
  echo "Test list file not found: $TESTS_FILE" >&2
  exit 1
fi

failures=0
passed=0
total=0

while IFS= read -r test_bin; do
  [[ -z "$test_bin" ]] && continue
  total=$((total + 1))
  echo -n "  $(basename "$test_bin")... "
  if "$test_bin" --page-sz "$PAGE_SZ" -j "$JOBS" 2>/dev/null; then
    echo "OK"
    passed=$((passed + 1))
  else
    echo "FAILED"
    failures=$((failures + 1))
  fi
done < "$TESTS_FILE"

echo "All $total tests passed."
[[ $failures -gt 0 ]] && exit 1
exit 0
