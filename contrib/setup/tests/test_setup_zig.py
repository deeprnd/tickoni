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


def test_forced_zig_install_bypasses_existing_path(monkeypatch, tmp_path, capsys):
    monkeypatch.setattr(
        "contrib.setup.install.strategies.zig.shutil.which",
        lambda name: str(tmp_path / "zig.exe"),
    )
    monkeypatch.setattr(
        "contrib.setup.install.strategies.zig._url_exists", lambda url: False,
    )
    with pytest.raises(SystemExit):
        ZigInstallStrategy().execute(
            {"parameters": {"version_ref": "zig"}},
            {"versions": {"zig": "0.18.0-dev.1156+0aab22eb3"}},
            "windows-arm", dry_run=False, skip_idempotency=True,
        )
    captured = capsys.readouterr()
    assert "already on PATH" not in captured.out
    assert "no Zig dev build" in captured.err


def test_windows_zig_activates_user_path_by_default(monkeypatch):
    calls = []
    monkeypatch.setattr(
        ZigInstallStrategy, "_install", lambda self, *args, **kwargs: calls.append(args),
    )
    ZigInstallStrategy().execute(
        {"parameters": {"version_ref": "zig"}},
        {"versions": {"zig": "0.18.0-dev.1156+0aab22eb3"}},
        "windows-arm", dry_run=False,
    )
    assert calls[0][3] is True


def test_windows_user_path_activation_does_not_write_env_file(monkeypatch, tmp_path):
    commands = []
    monkeypatch.delenv("GITHUB_PATH", raising=False)
    monkeypatch.setattr(
        "contrib.setup.install.strategies.zig.subprocess.run",
        lambda command, **kwargs: commands.append(command),
    )
    monkeypatch.setattr(
        ZigInstallStrategy, "_write_env_file",
        lambda *args: pytest.fail("user PATH activation must not create an env file"),
    )
    ZigInstallStrategy()._handle_windows_path(tmp_path, user_path=True)
    assert "SetEnvironmentVariable('Path', $new, 'User')" in commands[0][-1]


@pytest.mark.parametrize("reported_version", ["0.18.0-dev.1156+0aab22eb3", "0.17.0"])
def test_windows_reinstall_updates_existing_distribution_and_verifies_version(
    monkeypatch, tmp_path, capsys, reported_version,
):
    version = "0.18.0-dev.1156+0aab22eb3"
    existing = tmp_path / "zig-aarch64-windows-0.17.0"
    (existing / "lib").mkdir(parents=True)
    (existing / "zig.exe").write_text("old compiler")
    (existing / "lib" / "old.zig").touch()
    monkeypatch.setenv("XDG_CACHE_HOME", str(tmp_path / "cache"))
    monkeypatch.setattr(
        "contrib.setup.install.strategies.zig.shutil.which",
        lambda name: str(existing / "zig.exe"),
    )
    monkeypatch.setattr("contrib.setup.install.strategies.zig._url_exists", lambda url: True)
    monkeypatch.setattr(
        "contrib.setup.install.strategies.zig._download_and_verify", lambda **kwargs: None,
    )
    monkeypatch.setattr(ZigInstallStrategy, "_handle_windows_path", lambda *args: None)
    commands = []

    def run(command, **kwargs):
        commands.append(command)
        if command[0] == "unzip":
            extracted = Path(command[-1]) / f"zig-aarch64-windows-{version}"
            (extracted / "lib").mkdir(parents=True)
            (extracted / "zig.exe").write_text("new compiler")
            (extracted / "lib" / "new.zig").touch()
        return SimpleNamespace(returncode=0, stdout=reported_version + "\n", stderr="")

    monkeypatch.setattr("contrib.setup.install.strategies.zig.subprocess.run", run)

    def install():
        ZigInstallStrategy().execute(
            {"parameters": {"version_ref": "zig", "install_root": str(tmp_path / "new")}},
            {"versions": {"zig": {"version": version, "options": {"minisign_key": "test"}}}},
            "windows-arm", dry_run=False, skip_idempotency=True,
        )

    if reported_version == version:
        install()
        assert f"[done] zig version={version}" in capsys.readouterr().out
    else:
        with pytest.raises(SystemExit):
            install()
        captured = capsys.readouterr()
        assert "[done]" not in captured.out
        assert "version mismatch" in captured.err

    assert (existing / "zig.exe").read_text() == "new compiler"
    assert not (existing / "lib" / "old.zig").exists()
    assert (existing / "lib" / "new.zig").exists()
    assert commands[-1] == [str(existing / "zig.exe"), "version"]
