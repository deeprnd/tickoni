"""Regression tests for cache-restored Zig installations."""
import importlib.util
import os
import sys
from pathlib import Path


setup_dir = Path(__file__).resolve().parents[1] / "setup"
sys.path.insert(0, str(setup_dir))
platform_spec = importlib.util.spec_from_file_location("platform", setup_dir / "platform.py")
platform_module = importlib.util.module_from_spec(platform_spec)
sys.modules["platform"] = platform_module
platform_spec.loader.exec_module(platform_module)

from contrib.setup.install.strategies.zig import ZigInstallStrategy  # noqa: E402


def test_zig_reuses_cache_restored_target_installation(monkeypatch, tmp_path, capsys):
    version = "0.17.0-dev.2320+1e770dbef"
    target = "aarch64-windows"
    install_dir = tmp_path / f"zig-{target}-{version}"
    install_dir.mkdir()
    (install_dir / "zig.exe").touch()
    github_path = tmp_path / "github-path"

    monkeypatch.setattr("contrib.setup.install.strategies.zig.shutil.which", lambda name: None)
    monkeypatch.setenv("GITHUB_PATH", str(github_path))
    monkeypatch.setenv("PATH", "C:\\Windows\\System32")

    ZigInstallStrategy()._install(version, target, str(tmp_path), False, "windows-arm")

    assert f"[SKIP] zig {version} already installed at {install_dir}" in capsys.readouterr().out
    assert github_path.read_text().strip() == str(install_dir)
    assert os.environ["PATH"].startswith(str(install_dir))
