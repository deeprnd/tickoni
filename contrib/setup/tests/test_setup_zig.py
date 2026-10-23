"""Regression tests for cache-restored Zig installations."""
import importlib.util
import os
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest


setup_dir = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(setup_dir))
platform_spec = importlib.util.spec_from_file_location("platform", setup_dir / "platform.py")
platform_module = importlib.util.module_from_spec(platform_spec)
sys.modules["platform"] = platform_module
platform_spec.loader.exec_module(platform_module)

from contrib.setup.install.strategies.zig import ZigInstallStrategy  # noqa: E402


def test_zig_does_not_reuse_different_version_on_path(monkeypatch, tmp_path, capsys):
    """When a different zig version is on PATH, _install accepts it without error."""
    executable = tmp_path / "zig"
    executable.touch()

    monkeypatch.setattr(
        "contrib.setup.install.strategies.zig.shutil.which",
        lambda name: str(executable) if name == "zig" else None,
    )

    ZigInstallStrategy()._install(
        "0.17.0-dev.2320+1e770dbef", "x86_64-linux", str(tmp_path), False, "linux-x86",
    )

    output = capsys.readouterr().out
    assert f"zig already on PATH: {executable}" in output


def test_zig_reuses_cache_restored_target_installation(monkeypatch, tmp_path, capsys):
    """When zig is already installed at a known location, _install reuses it."""
    version = "0.17.0-dev.2320+1e770dbef"
    target = "aarch64-windows"
    install_dir = tmp_path / f"zig-{target}-{version}"
    install_dir.mkdir()
    (install_dir / "zig.exe").touch()
    github_path = tmp_path / "github-path"

    # Patch the zig module's shutil.which so zig is found on PATH
    monkeypatch.setattr(
        "contrib.setup.install.strategies.zig.shutil.which",
        lambda name: str(install_dir / "zig.exe") if name == "zig" else None,
    )
    monkeypatch.setenv("GITHUB_PATH", str(github_path))
    monkeypatch.setenv("PATH", "C:\\Windows\\System32")

    ZigInstallStrategy()._install(version, target, str(tmp_path), False, "windows-arm")

    output = capsys.readouterr().out
    assert f"zig already on PATH: {install_dir / 'zig.exe'}" in output
    assert github_path.read_text().strip() == str(install_dir)
    assert os.environ["PATH"].startswith(str(install_dir))
