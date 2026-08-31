"""Tests for the cross-platform pip installer launcher selection."""

import sys
from pathlib import Path
from unittest.mock import patch


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "setup"))

from install.strategies.pip import _run_pip  # noqa: E402


def test_run_pip_falls_back_when_current_interpreter_is_not_spawnable():
    expected = object()

    def run(command, **kwargs):
        if command[0] == sys.executable:
            raise FileNotFoundError(2, "not found")
        assert command[1:] == ["-m", "pip", "install", "--upgrade", "pipx"]
        return expected

    with patch("install.strategies.pip._python_commands", return_value=[
        [sys.executable], ["C:/Python/python.exe"]
    ]), patch("install.strategies.pip.subprocess.run", side_effect=run):
        assert _run_pip("pipx", "windows-x86") is expected


def test_run_pip_keeps_break_system_packages_off_windows():
    with patch("install.strategies.pip._python_commands", return_value=[[sys.executable]]), \
            patch("install.strategies.pip.subprocess.run") as run:
        _run_pip("pipx", "windows-arm")
        assert "--break-system-packages" not in run.call_args.args[0]
