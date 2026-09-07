"""Unit tests for infra.dynamic_test_opts (resource detection).

Mocks subprocess.run so the page_cnt formula can be verified
for known system configurations without requiring real hardware.

Key detail: _detect_memory_bytes and _detect_cores catch
subprocess.TimeoutExpired in their fallback paths.  A plain
MagicMock doesn't have a real TimeoutExpired class, so the
except clause itself would raise TypeError.  We fix this by
creating a custom mock object that carries the real
subprocess.TimeoutExpired exception.
"""

import subprocess
import sys
from pathlib import Path
from unittest.mock import MagicMock

import pytest

# Ensure infra/ is importable
sys.path.insert(0, str(Path(__file__).resolve().parent / "infra"))

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
    """A minimal subprocess mock that carries the real TimeoutExpired.

    The production code has ``except (FileNotFoundError, ValueError,
    subprocess.TimeoutExpired)`` clauses.  A plain MagicMock doesn't
    have a real ``TimeoutExpired`` exception class — it returns another
    MagicMock, which would itself raise TypeError when used in an
    ``except`` clause.  This class provides the real one.
    """
    TimeoutExpired = subprocess.TimeoutExpired

    def __init__(self):
        self.run = MagicMock()


def _free_mem_line(available):
    """Build a single ``free -b`` Mem: line where the 7th column is *available*."""
    # columns: total used free shared buff/cache available
    return f"Mem:  {available * 2:>20}  {available:>20}  {available:>20}  0  0  {available:>20}"


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


# ── _detect_cores ────────────────────────────────────────────────────


class TestDetectCores:
    def test_nproc(self):
        mock_sp = _MockSubprocess()
        mock_sp.run.return_value = _FakeResult(stdout="12\n")
        old_sp = d.subprocess
        d.subprocess = mock_sp
        try:
            assert _detect_cores() == 12
        finally:
            d.subprocess = old_sp

    def test_nproc_zero_returns_4(self):
        mock_sp = _MockSubprocess()
        mock_sp.run.return_value = _FakeResult(stdout="0\n")
        old_sp = d.subprocess
        d.subprocess = mock_sp
        try:
            assert _detect_cores() == 4  # fallback
        finally:
            d.subprocess = old_sp

    def test_macos_sysctl_ncpu(self):
        def side_effect(cmd, *args, **kwargs):
            if cmd and cmd[0] == "nproc":
                raise FileNotFoundError("no nproc")
            if cmd and cmd[0] == "sysctl":
                return _FakeResult(stdout="8\n")
            raise FileNotFoundError(cmd[0] if cmd else "unknown")

        mock_sp = _MockSubprocess()
        mock_sp.run.side_effect = side_effect
        old_sp = d.subprocess
        d.subprocess = mock_sp
        try:
            assert _detect_cores() == 8
        finally:
            d.subprocess = old_sp

    def test_nproc_error_returns_4(self):
        def side_effect(cmd, *args, **kwargs):
            raise FileNotFoundError()

        mock_sp = _MockSubprocess()
        mock_sp.run.side_effect = side_effect
        old_sp = d.subprocess
        d.subprocess = mock_sp
        try:
            assert _detect_cores() == 4  # fallback
        finally:
            d.subprocess = old_sp


# ── run_dynamic_test_opts ────────────────────────────────────────────


class TestRunDynamicTestOpts:
    def _make_runner(self, memory_bytes, cores):
        """Build a subprocess.run that returns `memory_bytes` then `cores`."""
        mem_bytes = memory_bytes
        cores_val = cores

        def fake_run(cmd, *args, **kwargs):
            if cmd and cmd[0] == "free":
                return _FakeResult(stdout=_free_mem_line(mem_bytes))
            if cmd and cmd[0] == "nproc":
                return _FakeResult(stdout=f"{cores_val}\n")
            raise FileNotFoundError(cmd[0] if cmd else "unknown")

        return fake_run

    def test_16gb_4cores(self):
        runner = self._make_runner(memory_bytes=16 * 1024 * 1024 * 1024, cores=4)
        mock_sp = _MockSubprocess()
        mock_sp.run.side_effect = runner
        old_sp = d.subprocess
        d.subprocess = mock_sp
        try:
            result = run_dynamic_test_opts()
        finally:
            d.subprocess = old_sp

        # avail = 16 GB == os_reserve → remaining = avail//2 = 8 GB
        # safe_budget = 8 GB // 2 = 4 GB; page_cnt = 4 GB // (4096*4*8) = 32768
        # 32768 < 65536 → clamp to 65536, max_j = min_jobs = 1
        assert result["TEST_OPTS"] == "--page-sz normal --page-cnt 65536 -j 1"
        assert result["LDFLAGS_EXE"] == "-Wl,-z,shstk"

    def test_64gb_8cores(self):
        runner = self._make_runner(memory_bytes=64 * 1024 * 1024 * 1024, cores=8)
        mock_sp = _MockSubprocess()
        mock_sp.run.side_effect = runner
        old_sp = d.subprocess
        d.subprocess = mock_sp
        try:
            result = run_dynamic_test_opts()
        finally:
            d.subprocess = old_sp

        assert result["TEST_OPTS"] == "--page-sz normal --page-cnt 131072 -j 6"
        assert result["LDFLAGS_EXE"] == "-Wl,-z,shstk"

    def test_32gb_2cores(self):
        runner = self._make_runner(memory_bytes=32 * 1024 * 1024 * 1024, cores=2)
        mock_sp = _MockSubprocess()
        mock_sp.run.side_effect = runner
        old_sp = d.subprocess
        d.subprocess = mock_sp
        try:
            result = run_dynamic_test_opts()
        finally:
            d.subprocess = old_sp

        assert result["TEST_OPTS"] == "--page-sz normal --page-cnt 131072 -j 2"
        assert result["LDFLAGS_EXE"] == "-Wl,-z,shstk"

    def test_min_page_cnt_enforcement(self):
        runner = self._make_runner(memory_bytes=5 * 1024 * 1024 * 1024, cores=1)
        mock_sp = _MockSubprocess()
        mock_sp.run.side_effect = runner
        old_sp = d.subprocess
        d.subprocess = mock_sp
        try:
            result = run_dynamic_test_opts()
        finally:
            d.subprocess = old_sp

        assert "--page-cnt 65536" in result["TEST_OPTS"]
        assert "-j 1" in result["TEST_OPTS"]

    def test_high_core_cap(self):
        runner = self._make_runner(memory_bytes=256 * 1024 * 1024 * 1024, cores=64)
        mock_sp = _MockSubprocess()
        mock_sp.run.side_effect = runner
        old_sp = d.subprocess
        d.subprocess = mock_sp
        try:
            result = run_dynamic_test_opts()
        finally:
            d.subprocess = old_sp

        assert "-j 6" in result["TEST_OPTS"]

    def test_ldflags_always_shstk(self):
        runner = self._make_runner(memory_bytes=16 * 1024 * 1024 * 1024, cores=4)
        mock_sp = _MockSubprocess()
        mock_sp.run.side_effect = runner
        old_sp = d.subprocess
        d.subprocess = mock_sp
        try:
            result = run_dynamic_test_opts()
        finally:
            d.subprocess = old_sp

        assert result["LDFLAGS_EXE"] == "-Wl,-z,shstk"
