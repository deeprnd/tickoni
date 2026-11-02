"""Unit tests for infra.dynamic_test_opts (resource detection).

Mocks subprocess.run for memory detection; cores come from FD_TEST_CORES
env var passed by justfile from platform.sh.
"""

import os
import subprocess
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

# Ensure infra/ is importable
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "infra"))

from dynamic_test_opts import run_dynamic_test_opts, _detect_memory_bytes, _detect_cores

import dynamic_test_opts as d


# ── Helpers ──────────────────────────────────────────────────────────


class _FakeResult:
    """Minimal subprocess.CompletedProcess mock."""

    def __init__(self, returncode=0, stdout="", stderr=""):
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


class _MockSubprocess:
    """A minimal subprocess mock that carries the real TimeoutExpired."""
    TimeoutExpired = subprocess.TimeoutExpired

    def __init__(self):
        self.run = MagicMock()


def _free_mem_line(available):
    """Build a single ``free -b`` Mem: line where the 7th column is *available*."""
    return f"Mem:  {available * 2:>20}  {available:>20}  {available:>20}  0  0  {available:>20}"


# ── _detect_cores ────────────────────────────────────────────────────


class TestDetectCores:
    def test_reads_fd_test_cores(self):
        old = os.environ.pop("FD_TEST_CORES", None)
        try:
            os.environ["FD_TEST_CORES"] = "12"
            assert _detect_cores() == 12
        finally:
            if old is not None:
                os.environ["FD_TEST_CORES"] = old
            else:
                os.environ.pop("FD_TEST_CORES", None)

    def test_missing_raises_keyerror(self):
        old = os.environ.pop("FD_TEST_CORES", None)
        try:
            with pytest.raises(KeyError):
                _detect_cores()
        finally:
            if old is not None:
                os.environ["FD_TEST_CORES"] = old
            else:
                os.environ.pop("FD_TEST_CORES", None)


# ── _detect_memory_bytes ─────────────────────────────────────────────


class TestDetectMemoryBytes:
    def test_linux_free_b(self):
        mock_sp = _MockSubprocess()
        mock_sp.run.return_value = _FakeResult(
            stdout=_free_mem_line(3_600_000_000)
        )
        old_sp = d.subprocess
        d.subprocess = mock_sp
        try:
            assert _detect_memory_bytes() == 3_600_000_000
        finally:
            d.subprocess = old_sp

    def test_linux_free_b_uses_available_not_total(self):
        mock_sp = _MockSubprocess()
        mock_sp.run.return_value = _FakeResult(
            stdout=_free_mem_line(6_000_000_000)
        )
        old_sp = d.subprocess
        d.subprocess = mock_sp
        try:
            assert _detect_memory_bytes() == 6_000_000_000
        finally:
            d.subprocess = old_sp

    def test_macos_sysctl(self):
        def side_effect(cmd, *args, **kwargs):
            if cmd and cmd[0] == "free":
                raise FileNotFoundError("no free")
            if cmd and cmd[0] == "sysctl":
                return _FakeResult(stdout="17179869184")
            raise FileNotFoundError(cmd[0] if cmd else "unknown")

        mock_sp = _MockSubprocess()
        mock_sp.run.side_effect = side_effect
        old_sp = d.subprocess
        d.subprocess = mock_sp
        try:
            assert _detect_memory_bytes() == 17_179_869_184  # 16 GB
        finally:
            d.subprocess = old_sp

    def test_rejects_below_min_memory(self):
        mock_sp = _MockSubprocess()
        mock_sp.run.return_value = _FakeResult(
            stdout=_free_mem_line(500_000_000)
        )
        old_sp = d.subprocess
        d.subprocess = mock_sp
        try:
            with pytest.raises(SystemExit):
                _detect_memory_bytes()
        finally:
            d.subprocess = old_sp


# ── run_dynamic_test_opts ────────────────────────────────────────────


class TestRunDynamicTestOpts:
    def setup_method(self):
        """pytest calls setup_method (not setUp); save FD_TEST_CORES."""
        self._old_fd_test_cores = os.environ.pop("FD_TEST_CORES", None)

    def teardown_method(self):
        if self._old_fd_test_cores is not None:
            os.environ["FD_TEST_CORES"] = self._old_fd_test_cores
        else:
            os.environ.pop("FD_TEST_CORES", None)

    def _make_runner(self, memory_bytes, cores):
        """Build a subprocess.run that returns `memory_bytes`."""
        mem_bytes = memory_bytes

        def fake_run(cmd, *args, **kwargs):
            if cmd and cmd[0] == "free":
                return _FakeResult(stdout=_free_mem_line(mem_bytes))
            # macOS fallback: sysctl -n hw.memsize
            if cmd and len(cmd) > 1 and cmd[0] == "sysctl":
                if cmd[1] == "-n" and cmd[2] == "hw.memsize":
                    return _FakeResult(stdout=str(mem_bytes))
            raise FileNotFoundError(cmd[0] if cmd else "unknown")

        return fake_run

    def test_16gb_4cores(self):
        runner = self._make_runner(memory_bytes=16 * 1024 * 1024 * 1024, cores=4)
        with patch.object(d, "subprocess", spec=True) as mock_sp, \
             patch.dict(os.environ, {"FD_TEST_CORES": "3"}):
            mock_sp.TimeoutExpired = subprocess.TimeoutExpired
            mock_sp.run.side_effect = runner
            result = run_dynamic_test_opts()

        # FD_TEST_CORES=3 → cores=3; max_jobs=min(3, 6)=3
        # avail = 16 GB == os_reserve → remaining = avail//2 = 8 GB
        # safe_budget = 8 GB // 2 = 4 GB
        # page_cnt = 4 GB // (4096*3*4) = 87040
        # 87040 >= 65536 → no clamp
        assert result["TEST_OPTS"] == "--page-sz normal --page-cnt 87040 -j 3"
        assert result["LDFLAGS_EXE"] == "-Wl,-z,shstk"

    def test_64gb_8cores(self):
        runner = self._make_runner(memory_bytes=64 * 1024 * 1024 * 1024, cores=8)
        with patch.object(d, "subprocess", spec=True) as mock_sp, \
             patch.dict(os.environ, {"FD_TEST_CORES": "7"}):
            mock_sp.TimeoutExpired = subprocess.TimeoutExpired
            mock_sp.run.side_effect = runner
            result = run_dynamic_test_opts()

        # FD_TEST_CORES=7 → cores=7; max_jobs=min(7, 6)=6
        # avail = 64 GB → remaining = 64 - 16 = 48 GB
        # safe_budget = 48 GB // 2 = 24 GB
        # page_cnt = 24 GB // (4096 * 6 * 4) = 262144
        # 262144 >= 65536 → no clamp
        assert result["TEST_OPTS"] == "--page-sz normal --page-cnt 262144 -j 6"
        assert result["LDFLAGS_EXE"] == "-Wl,-z,shstk"

    def test_32gb_2cores(self):
        runner = self._make_runner(memory_bytes=32 * 1024 * 1024 * 1024, cores=2)
        with patch.object(d, "subprocess", spec=True) as mock_sp, \
             patch.dict(os.environ, {"FD_TEST_CORES": "1"}):
            mock_sp.TimeoutExpired = subprocess.TimeoutExpired
            mock_sp.run.side_effect = runner
            result = run_dynamic_test_opts()

        # FD_TEST_CORES=1 → cores=1; max_jobs=min(1, 6)=1
        # avail = 32 GB → remaining = 32 - 16 = 16 GB
        # safe_budget = 16 GB // 2 = 8 GB
        # page_cnt = 8 GB // (4096 * 1 * 4) = 524288
        # 524288 >= 65536 → no clamp
        assert result["TEST_OPTS"] == "--page-sz normal --page-cnt 524288 -j 1"
        assert result["LDFLAGS_EXE"] == "-Wl,-z,shstk"

    def test_min_page_cnt_enforcement(self):
        runner = self._make_runner(memory_bytes=4 * 1024 * 1024 * 1024, cores=1)
        with patch.object(d, "subprocess", spec=True) as mock_sp, \
             patch.dict(os.environ, {"FD_TEST_CORES": "1"}):
            mock_sp.TimeoutExpired = subprocess.TimeoutExpired
            mock_sp.run.side_effect = runner
            result = run_dynamic_test_opts()

        # FD_TEST_CORES=1 → cores=1; max_jobs=min(1, 6)=1
        # avail = 4 GB → remaining = 4 // 2 = 2 GB; safe_budget = 1 GB
        # page_cnt = 1 GB // (4096 * 1 * 4) = 65536 (exactly at min)
        assert "--page-cnt 65536" in result["TEST_OPTS"]
        assert "-j 1" in result["TEST_OPTS"]

    def test_high_core_cap(self):
        runner = self._make_runner(memory_bytes=256 * 1024 * 1024 * 1024, cores=64)
        with patch.object(d, "subprocess", spec=True) as mock_sp, \
             patch.dict(os.environ, {"FD_TEST_CORES": "63"}):
            mock_sp.TimeoutExpired = subprocess.TimeoutExpired
            mock_sp.run.side_effect = runner
            result = run_dynamic_test_opts()

        # FD_TEST_CORES=63 → cores=63; max_jobs=min(63, 6)=6
        assert "-j 6" in result["TEST_OPTS"]

    def test_ldflags_always_shstk(self):
        runner = self._make_runner(memory_bytes=16 * 1024 * 1024 * 1024, cores=4)
        with patch.object(d, "subprocess", spec=True) as mock_sp, \
             patch.dict(os.environ, {"FD_TEST_CORES": "3"}):
            mock_sp.TimeoutExpired = subprocess.TimeoutExpired
            mock_sp.run.side_effect = runner
            result = run_dynamic_test_opts()

        assert result["LDFLAGS_EXE"] == "-Wl,-z,shstk"
