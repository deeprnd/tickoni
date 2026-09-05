"""Unit tests for infra.dynamic_test_opts (resource detection).

Mocks subprocess.run so the page_cnt formula can be verified
for known system configurations without requiring real hardware.
"""

import sys
from pathlib import Path
from unittest.mock import patch

import pytest

# Ensure infra/ is importable (same pattern as test_llama_server.py)
sys.path.insert(0, str(Path(__file__).resolve().parent / "infra"))

from dynamic_test_opts import run_dynamic_test_opts, _detect_memory_bytes, _detect_cores


# ── Helpers ──────────────────────────────────────────────────────────


class FakeResult:
    """Minimal subprocess.CompletedProcess mock."""

    def __init__(self, returncode=0, stdout="", stderr=""):
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


# ── _detect_memory_bytes ─────────────────────────────────────────────


class TestDetectMemoryBytes:
    def test_linux_free_b(self):
        with patch("dynamic_test_opts.subprocess.run") as mock:
            mock.return_value = FakeResult(
                stdout="Mem:\n   4294967296  1073741824  3221225472  0  0  3600000000\n"
            )
            # column 6 (0-based) is "available"
            assert _detect_memory_bytes() == 3_600_000_000

    def test_linux_free_b_uses_available_not_total(self):
        with patch("dynamic_test_opts.subprocess.run") as mock:
            mock.return_value = FakeResult(
                stdout="Mem:\n   8589934592  2147483648  6442450944  0  0  6000000000\n"
            )
            # should pick column 6 (available), not column 1 (total)
            assert _detect_memory_bytes() == 6_000_000_000

    def test_macos_sysctl(self):
        def side_effect(*args, **kwargs):
            if args and args[0] and args[0][0] == "free":
                raise FileNotFoundError("no free")
            return FakeResult(stdout="17179869184")

        with patch("dynamic_test_opts.subprocess.run", side_effect=side_effect):
            assert _detect_memory_bytes() == 17_179_869_184  # 16 GB

    def test_rejects_below_min_memory(self):
        with patch("dynamic_test_opts.subprocess.run") as mock:
            mock.return_value = FakeResult(
                stdout="Mem:\n   500000000  100000000  400000000\n"
            )
            with pytest.raises(SystemExit):
                _detect_memory_bytes()


# ── _detect_cores ────────────────────────────────────────────────────


class TestDetectCores:
    def test_nproc(self):
        with patch("dynamic_test_opts.subprocess.run") as mock:
            mock.return_value = FakeResult(stdout="12\n")
            assert _detect_cores() == 12

    def test_nproc_zero_returns_4(self):
        with patch("dynamic_test_opts.subprocess.run") as mock:
            mock.return_value = FakeResult(stdout="0\n")
            assert _detect_cores() == 4  # fallback

    def test_macos_sysctl_ncpu(self):
        def side_effect(*args, **kwargs):
            if args and args[0] and args[0][0] == "nproc":
                raise FileNotFoundError("no nproc")
            return FakeResult(stdout="8\n")

        with patch("dynamic_test_opts.subprocess.run", side_effect=side_effect):
            assert _detect_cores() == 8

    def test_nproc_error_returns_4(self):
        def side_effect(*args, **kwargs):
            raise FileNotFoundError()

        with patch("dynamic_test_opts.subprocess.run", side_effect=side_effect):
            assert _detect_cores() == 4  # fallback


# ── run_dynamic_test_opts ────────────────────────────────────────────


class TestRunDynamicTestOpts:
    def _make_runner(self, memory_bytes, cores):
        """Build a subprocess.run that returns `memory_bytes` then `cores`."""
        call_count = [0]
        mem_bytes = memory_bytes
        cores_val = cores

        def fake_run(cmd, *args, **kwargs):
            call_count[0] += 1
            if cmd and cmd[0] == "free":
                available = mem_bytes
                return FakeResult(stdout=f"Mem:\n   {mem_bytes * 2}  {mem_bytes}  {available}\n")
            if cmd and cmd[0] == "nproc":
                return FakeResult(stdout=f"{cores_val}\n")
            raise FileNotFoundError(cmd[0] if cmd else "unknown")

        return fake_run

    def test_16gb_4cores(self):
        runner = self._make_runner(memory_bytes=16 * 1024 * 1024 * 1024, cores=4)
        with patch("dynamic_test_opts.subprocess.run", side_effect=runner):
            result = run_dynamic_test_opts()

        # page_cnt = (16GB - 16GB reserve) / 2 = 0, but avail > reserve so
        # remaining = 16GB - 16GB = 0, safe_budget = 0 // 2 = 0
        # page_cnt = 0 // (4096 * 4 * 8) = 0, rounds down to 0, then clamped to min 65536
        # max_j = min(4, 6) = 4
        assert result["TEST_OPTS"] == "--page-sz normal --page-cnt 65536 -j 4"
        assert result["LDFLAGS_EXE"] == "-Wl,-z,shstk"

    def test_64gb_8cores(self):
        runner = self._make_runner(memory_bytes=64 * 1024 * 1024 * 1024, cores=8)
        with patch("dynamic_test_opts.subprocess.run", side_effect=runner):
            result = run_dynamic_test_opts()

        # remaining = 64GB - 16GB = 48GB
        # safe_budget = 48GB // 2 = 24GB = 25769803776
        # max_j = min(8, 6) = 6
        # page_cnt = 25769803776 // (4096 * 6 * 8) = 25769803776 // 196608 = 131072
        # rounds down to nearest 1024: 131072 // 1024 = 128, 128 * 1024 = 131072
        assert result["TEST_OPTS"] == "--page-sz normal --page-cnt 131072 -j 6"
        assert result["LDFLAGS_EXE"] == "-Wl,-z,shstk"

    def test_32gb_2cores(self):
        runner = self._make_runner(memory_bytes=32 * 1024 * 1024 * 1024, cores=2)
        with patch("dynamic_test_opts.subprocess.run", side_effect=runner):
            result = run_dynamic_test_opts()

        # remaining = 32GB - 16GB = 16GB
        # safe_budget = 16GB // 2 = 8GB = 8589934592
        # max_j = min(2, 6) = 2
        # page_cnt = 8589934592 // (4096 * 2 * 8) = 8589934592 // 65536 = 131072
        # rounds down to nearest 1024: 131072 // 1024 = 128, 128 * 1024 = 131072
        assert result["TEST_OPTS"] == "--page-sz normal --page-cnt 131072 -j 2"
        assert result["LDFLAGS_EXE"] == "-Wl,-z,shstk"

    def test_min_page_cnt_enforcement(self):
        runner = self._make_runner(memory_bytes=5 * 1024 * 1024 * 1024, cores=1)
        with patch("dynamic_test_opts.subprocess.run", side_effect=runner):
            result = run_dynamic_test_opts()

        # remaining = 5GB - 16GB → < 0, so remaining = 5GB // 2 = 2.5GB
        # safe_budget = 2.5GB // 2 = 1.25GB
        # max_j = min(1, 6) = 1
        # page_cnt = ~1.25GB // (4096 * 1 * 8) = ~39321, rounds to 39328
        # 39328 < 65536 → clamp to 65536, max_j = min_jobs = 1
        assert "--page-cnt 65536" in result["TEST_OPTS"]
        assert "-j 1" in result["TEST_OPTS"]

    def test_high_core_cap(self):
        runner = self._make_runner(memory_bytes=256 * 1024 * 1024 * 1024, cores=64)
        with patch("dynamic_test_opts.subprocess.run", side_effect=runner):
            result = run_dynamic_test_opts()

        # max_j = min(64, 6) = 6 (capped)
        # remaining = 256GB - 16GB = 240GB
        # safe_budget = 240GB // 2 = 120GB
        # page_cnt = 120GB // (4096 * 6 * 8) = 120GB // 196608 ≈ 655360
        assert "-j 6" in result["TEST_OPTS"]

    def test_ldflags_always_shstk(self):
        runner = self._make_runner(memory_bytes=16 * 1024 * 1024 * 1024, cores=4)
        with patch("dynamic_test_opts.subprocess.run", side_effect=runner):
            result = run_dynamic_test_opts()

        assert result["LDFLAGS_EXE"] == "-Wl,-z,shstk"
