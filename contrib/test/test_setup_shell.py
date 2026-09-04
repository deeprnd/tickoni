"""Regression tests for native setup shell selection."""

from pathlib import Path

from contrib.setup import shell


def test_non_windows_uses_bash(monkeypatch):
    monkeypatch.setattr(shell.os, "name", "posix")

    assert shell.bash_command() == "bash"


def test_windows_skips_wsl_launcher(monkeypatch, tmp_path):
    git_root = tmp_path / "Git"
    git_bash = git_root / "usr" / "bin" / "bash.exe"
    git_bash.parent.mkdir(parents=True)
    git_bash.touch()
    git_exe = git_root / "cmd" / "git.exe"
    git_exe.parent.mkdir()
    git_exe.touch()

    def which(command):
        if command in ("bash.exe", "bash"):
            return r"C:\Windows\System32\bash.exe"
        if command in ("git.exe", "git"):
            return str(git_exe)
        return None

    monkeypatch.setattr(shell.os, "name", "nt")
    monkeypatch.setattr(shell.shutil, "which", which)

    assert Path(shell.bash_command()) == git_bash
