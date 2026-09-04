#!/usr/bin/env bash
# Run FD C unit-test binaries sequentially.
# Usage: run_unit_tests.sh --tests <file> [--page-sz <sz>] [--page-cnt <cnt>] [-j <n>]
set -uo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 --tests <test-list> [--page-sz <sz>] [--page-cnt <cnt>] [-j <n>]" >&2
  exit 1
fi

TESTS_FILE=""
PAGE_SZ="normal"
PAGE_CNT=""
JOBS=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tests) TESTS_FILE="$2"; shift 2 ;;
    --page-sz) PAGE_SZ="$2"; shift 2 ;;
    --page-cnt) PAGE_CNT="$2"; shift 2 ;;
    -j) JOBS="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ ! -f "$TESTS_FILE" ]]; then
  echo "No test list file: $TESTS_FILE (no unit-test targets registered)"
  echo "All 0 tests passed."
  exit 0
fi

failures=0
passed=0
total=0

while IFS= read -r test_bin; do
  [[ -z "$test_bin" ]] && continue
  total=$((total + 1))
  echo -n "  $(basename "$test_bin")... "
  TEST_CMD="$test_bin --page-sz $PAGE_SZ -j $JOBS"
  if [[ -n "$PAGE_CNT" ]]; then
    TEST_CMD="$TEST_CMD --page-cnt $PAGE_CNT"
  fi
  if $TEST_CMD 2>/dev/null; then
    echo "OK"
    passed=$((passed + 1))
  else
    echo "FAILED"
    failures=$((failures + 1))
  fi
done < "$TESTS_FILE"

echo "$passed/$total tests passed${failures:+, $failures failed}."
[[ $failures -gt 0 ]] && exit 1
exit 0
