"""Regression tests for native setup shell selection."""

import sys
from pathlib import Path, PureWindowsPath

import pytest

from contrib.setup import shell


def test_non_windows_uses_bash(monkeypatch):
    monkeypatch.setattr(shell.os, "name", "posix")

    assert shell.bash_command() == "bash"


@pytest.mark.skipif(sys.platform != "win32", reason="requires Windows pathlib")
def test_windows_skips_wsl_launcher(monkeypatch, tmp_path):
    git_root = PureWindowsPath("C:\\Program Files\\Git")
    git_bash = git_root / "usr" / "bin" / "bash.exe"
    git_exe = git_root / "cmd" / "git.exe"

    def which(command):
        if command in ("bash.exe", "bash"):
            return r"C:\Windows\System32\bash.exe"
        if command in ("git.exe", "git"):
            return str(git_exe)
        return None

    monkeypatch.setattr(shell.os, "name", "nt")
    monkeypatch.setattr(shell.shutil, "which", which)

    assert Path(shell.bash_command()) == git_bash
