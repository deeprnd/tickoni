#!/usr/bin/env bash
# Dynamically detect system resources and compute optimal test parameters.
# Outputs shell-exportable variables: TEST_OPTS LDFLAGS_EXE
#
# Algorithm:
#   - Tests run SEQUENTIALLY (run_unit_tests.sh processes one at a time)
#   - Within each test, -j controls threads per test
#   - FD workspaces use ~2-6x raw page space (metadata, alignment, etc.)
#   - Safe budget: (available_ram - os_reserve) / 2
#   - page_cnt = safe_budget / (page_sz * j * overhead_multiplier)
#
# Formula:
#   j = min(nproc, MAX_JOBS)
#   safe_budget = (avail_bytes - os_reserve) / 2
#   page_cnt = safe_budget / (page_sz * j * OVERHEAD_MULT)
#   page_cnt = floor(page_cnt / 1024) * 1024  # round to page boundary
#   page_cnt = max(page_cnt, MIN_PAGE_CNT)

set -euo pipefail

# Source platform.sh for cross-platform OS detection
# Redirect stdout to /dev/null — platform.sh prints TK_OS/TK_ARCH/TK_PLATFORM
# when sourced, but we only need the functions here.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../platform.sh" >/dev/null

# ── Detect available memory (bytes) ──────────────────────────────────────────
if command -v free &>/dev/null; then
  avail_bytes=$(free -b | awk '/Mem:/ {print $7}')
elif [[ "$(tk_os)" == "macos" ]] && command -v sysctl &>/dev/null; then
  avail_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
else
  echo "ERROR: cannot detect available memory" >&2
  exit 1
fi

# Guard: if available < 4 GB, cap aggressively
if [ "$avail_bytes" -lt 4294967296 ]; then
  echo "ERROR: available memory ${avail_bytes} bytes (<4 GB)" >&2
  exit 1
fi

# ── Detect CPU cores ─────────────────────────────────────────────────────────
if command -v nproc &>/dev/null; then
  cores=$(nproc)
elif [[ "$(tk_os)" == "macos" ]] && command -v sysctl &>/dev/null; then
  cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
else
  cores=4
fi

# ── Constants ────────────────────────────────────────────────────────────────
PAGE_SZ_NORMAL=4096       # FD_SHMEM_NORMAL_PAGE_SZ
OS_RESERVE_GB=16          # GB to reserve for OS + other processes
OVERHEAD_MULT=8           # FD workspaces typically use 2-6x raw page space;
                          # use 8 to leave headroom for peak workloads
MIN_JOBS=1
MAX_JOBS=6                # cap to avoid fork-bomb on many-core machines
MIN_PAGE_CNT=65536        # minimum pages (256 MB workspace)

# ── Calculate optimal values ─────────────────────────────────────────────────

# Available bytes after reserving OS memory
os_reserve_bytes=$((OS_RESERVE_GB * 1073741824))
if [ "$avail_bytes" -gt "$os_reserve_bytes" ]; then
  remaining_bytes=$((avail_bytes - os_reserve_bytes))
else
  remaining_bytes=$((avail_bytes / 2))
fi

# Safe budget for ONE test: half of remaining RAM
# (the other half stays for OS + other processes while test is running)
safe_budget=$((remaining_bytes / 2))

# Max threads we want to use
max_j=$cores
if [ "$max_j" -gt "$MAX_JOBS" ]; then
  max_j=$MAX_JOBS
fi

# page_cnt = safe_budget / (page_sz * max_j * overhead_mult)
# This ensures: page_cnt * page_sz * max_j * overhead_mult <= safe_budget
page_cnt=$((safe_budget / (PAGE_SZ_NORMAL * max_j * OVERHEAD_MULT)))

# Round down to nearest 1024 (page boundary alignment)
page_cnt=$(( (page_cnt / 1024) * 1024 ))

# Enforce minimum
if [ "$page_cnt" -lt "$MIN_PAGE_CNT" ]; then
  page_cnt=$MIN_PAGE_CNT
  max_j=1
fi

# ── Build TEST_OPTS ──────────────────────────────────────────────────────────
TEST_OPTS="--page-sz normal --page-cnt $page_cnt -j $max_j"
LDFLAGS_EXE="-Wl,-z,shstk"

# ── Output ───────────────────────────────────────────────────────────────────
# Source-friendly: set variables in the caller's environment.
# Also echoes them for visibility (with "  " prefix for human-readable output).
#
# For justfile consumption, also emit clean KEY=VALUE lines (no prefix)
# so they can be extracted with:
#   eval "$(bash script.sh | grep -E '^TEST_OPTS=|^LDFLAGS_EXE=')"
export TEST_OPTS="$TEST_OPTS"
export LDFLAGS_EXE="$LDFLAGS_EXE"

echo "  TEST_OPTS=   $TEST_OPTS"
echo "  LDFLAGS_EXE= $LDFLAGS_EXE"
# Clean exportable lines for justfile eval
echo "TEST_OPTS=\"$TEST_OPTS\""
echo "LDFLAGS_EXE=\"$LDFLAGS_EXE\""
