"""Dynamic test resource detection.

Replicates the logic of run_unit_tests_dynamic.sh in pure Python
so orchestrator.py can compute TEST_OPTS and LDFLAGS_EXE without
a shell script or any uname calls.

Usage:
    python3 -c "from infra.dynamic_test_opts import run_dynamic_test_opts; run_dynamic_test_opts()"

Output format (source-friendly):
    TEST_OPTS="--page-sz normal --page-cnt NNNNNN -j NN"
    LDFLAGS_EXE="-Wl,-z,shstk"
"""
import os
import subprocess
import sys


def _detect_memory_bytes() -> int:
    """Detect available physical memory in bytes.

    Bounded: rejects values below 1 GB (1_073_741_824 bytes) to guard
    against misparse or poisoned output.
    """
    MIN_MEMORY = 1_073_741_824  # 1 GB

    # Try `free -b` (Linux)
    try:
        result = subprocess.run(
            ["free", "-b"], capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            for line in result.stdout.splitlines():
                if line.startswith("Mem:"):
                    parts = line.split()
                    # columns: total used free shared buff/cache available
                    if len(parts) >= 7:
                        val = int(parts[6])
                        if val >= MIN_MEMORY:
                            return val
    except (FileNotFoundError, ValueError, subprocess.TimeoutExpired):
        pass

    # macOS: sysctl -n hw.memsize
    try:
        result = subprocess.run(
            ["sysctl", "-n", "hw.memsize"],
            capture_output=True, text=True,
            timeout=10,
        )
        if result.returncode == 0:
            val = int(result.stdout.strip())
            if val >= MIN_MEMORY:
                return val
    except (FileNotFoundError, ValueError, subprocess.TimeoutExpired):
        pass

    # Fallback
    print("ERROR: cannot detect available memory", file=sys.stderr)
    sys.exit(1)


def _detect_cores() -> int:
    """Detect logical CPU core count."""
    # Try nproc (Linux, macOS, Windows WSL)
    try:
        result = subprocess.run(
            ["nproc"], capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            cores = int(result.stdout.strip())
            if cores >= 1:
                return cores
    except (FileNotFoundError, ValueError, subprocess.TimeoutExpired):
        pass

    # macOS: sysctl -n hw.ncpu
    try:
        result = subprocess.run(
            ["sysctl", "-n", "hw.ncpu"],
            capture_output=True, text=True,
            timeout=10,
        )
        if result.returncode == 0:
            cores = int(result.stdout.strip())
            if cores >= 1:
                return cores
    except (FileNotFoundError, ValueError, subprocess.TimeoutExpired):
        pass

    # Fallback
    return 4


def run_dynamic_test_opts() -> dict:
    """Compute TEST_OPTS and LDFLAGS_EXE from system resources.

    Returns:
        dict with keys "TEST_OPTS" and "LDFLAGS_EXE" (strings).
    """
    # ── Constants ──────────────────────────────────────────────────────
    page_sz_normal = 4096       # FD_SHMEM_NORMAL_PAGE_SZ
    os_reserve_gb = 16          # GB to reserve for OS + other processes
    overhead_mult = 8           # FD workspaces typically use 2-6x raw page space
    min_jobs = 1
    max_jobs = 6                # cap to avoid fork-bomb on many-core machines
    min_page_cnt = 65536        # minimum pages (256 MB workspace)

    # ── Detect resources ───────────────────────────────────────────────
    avail_bytes = _detect_memory_bytes()
    cores = _detect_cores()

    # Guard: if available < 4 GB, cap aggressively
    if avail_bytes < 4294967296:
        print(f"ERROR: available memory {avail_bytes} bytes (<4 GB)", file=sys.stderr)
        sys.exit(1)

    # ── Calculate optimal values ───────────────────────────────────────
    # Available bytes after reserving OS memory
    os_reserve_bytes = os_reserve_gb * 1073741824
    if avail_bytes > os_reserve_bytes:
        remaining_bytes = avail_bytes - os_reserve_bytes
    else:
        remaining_bytes = avail_bytes // 2

    # Safe budget for ONE test: half of remaining RAM
    safe_budget = remaining_bytes // 2

    # Max threads we want to use
    max_j = min(cores, max_jobs)

    # page_cnt = safe_budget / (page_sz * max_j * overhead_mult)
    page_cnt = safe_budget // (page_sz_normal * max_j * overhead_mult)

    # Round down to nearest 1024 (page boundary alignment)
    page_cnt = (page_cnt // 1024) * 1024

    # Enforce minimum
    if page_cnt < min_page_cnt:
        page_cnt = min_page_cnt
        max_j = min_jobs

    # ── Build output ───────────────────────────────────────────────────
    test_opts = f"--page-sz normal --page-cnt {page_cnt} -j {max_j}"
    ldflags_exe = "-Wl,-z,shstk"

    # ── Output (source-friendly: clean KEY=VALUE lines) ────────────────
    print(f"TEST_OPTS=\"{test_opts}\"")
    print(f"LDFLAGS_EXE=\"{ldflags_exe}\"")

    return {"TEST_OPTS": test_opts, "LDFLAGS_EXE": ldflags_exe}


if __name__ == "__main__":
    run_dynamic_test_opts()
