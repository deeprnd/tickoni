"""Regression tests for the Windows Minisign bootstrap."""

import hashlib
import shutil
import zipfile
from pathlib import Path

from contrib.setup.install.strategies import minisign


def test_windows_arm_downloads_official_minisign_without_winget(
    monkeypatch, tmp_path
):
    archive = tmp_path / "minisign-win64.zip"
    with zipfile.ZipFile(archive, "w") as bundle:
        bundle.writestr("minisign-win64/aarch64/minisign.exe", b"arm64")
        bundle.writestr("minisign-win64/x86_64/minisign.exe", b"x86_64")

    config = {"versions": {"minisign": {"version": "0.12"}}}
    tool = {
        "name": "minisign",
        "parameters": {
            "version_ref": "minisign",
            "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
        },
    }
    local_app_data = tmp_path / "LocalAppData"
    github_path = tmp_path / "github-path"
    monkeypatch.setenv("LOCALAPPDATA", str(local_app_data))
    monkeypatch.setenv("GITHUB_PATH", str(github_path))
    monkeypatch.setenv("PATH", "C:\\Windows\\System32")

    def copy_archive(_url: str, destination: Path, dry_run: bool = False):
        assert not dry_run
        shutil.copyfile(archive, destination)

    monkeypatch.setattr(minisign, "_download_file", copy_archive)

    minisign.MinisignDownloadStrategy().execute(
        tool, config, "windows-arm", dry_run=False
    )

    install_dir = local_app_data / "Tickoni" / "bin"
    assert (install_dir / "minisign.exe").read_bytes() == b"arm64"
    assert github_path.read_text().strip() == str(install_dir)
