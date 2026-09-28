from __future__ import annotations

import os
from pathlib import Path
import subprocess


RUNNER = Path(__file__).with_name("run_test_series.sh")


def _write_executable(path: Path, exit_code: int) -> None:
    path.write_text(f"#!/usr/bin/env bash\nexit {exit_code}\n", encoding="utf-8")
    path.chmod(path.stat().st_mode | 0o111)


def test_run_test_series_propagates_test_failure(tmp_path: Path) -> None:
    failing_test = tmp_path / "failing-test"
    _write_executable(failing_test, 7)

    result = subprocess.run(
        ["bash", os.fspath(RUNNER), os.fspath(failing_test)],
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 1
    assert "FAILED (exit 7)" in result.stdout


def test_run_test_series_accepts_passing_test(tmp_path: Path) -> None:
    passing_test = tmp_path / "passing-test"
    _write_executable(passing_test, 0)

    result = subprocess.run(
        ["bash", os.fspath(RUNNER), os.fspath(passing_test)],
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0
    assert "All 1 tests passed." in result.stdout
