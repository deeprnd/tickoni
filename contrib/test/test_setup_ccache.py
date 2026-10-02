"""Regression tests for the Windows Ccache bootstrap."""

import hashlib
import shutil
import zipfile
from pathlib import Path

from contrib.setup.install.strategies import ccache


def test_windows_arm_downloads_official_ccache_without_winget(
    monkeypatch, tmp_path
):
    archive = tmp_path / "ccache-windows-arm64.zip"
    with zipfile.ZipFile(archive, "w") as bundle:
        bundle.writestr(
            "ccache-4.14.1-windows-aarch64/ccache.exe",
            b"arm64",
        )

    config = {"versions": {"ccache": {"version": "4.14.1"}}}
    tool = {
        "name": "ccache",
        "version_ref": "ccache",
        "parameters": {
            "sha256": {
                "windows-arm": hashlib.sha256(archive.read_bytes()).hexdigest(),
            },
        },
    }
    local_app_data = tmp_path / "LocalAppData"
    github_path = tmp_path / "github-path"
    monkeypatch.setenv("LOCALAPPDATA", str(local_app_data))
    monkeypatch.setenv("GITHUB_PATH", str(github_path))
    monkeypatch.setenv("PATH", "C:\\Windows\\System32")

    def copy_archive(url: str, destination: Path, dry_run: bool = False):
        assert not dry_run
        assert url.endswith("ccache-4.14.1-windows-aarch64.zip")
        shutil.copyfile(archive, destination)

    monkeypatch.setattr(ccache, "_download_file", copy_archive)

    ccache.CcacheDownloadStrategy().execute(
        tool, config, "windows-arm", dry_run=False
    )

    install_dir = local_app_data / "Tickoni" / "bin"
    assert (install_dir / "ccache.exe").read_bytes() == b"arm64"
    assert github_path.read_text().strip() == str(install_dir)
