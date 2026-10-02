"""Install the official Minisign binary on Windows without WinGet."""

import os
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

from config import resolve_version
from .. import register
from ..base import InstallStrategy, _activate_path, _download_file
from .download import _verify_sha256


@register("minisign_download")
class MinisignDownloadStrategy(InstallStrategy):
    """Install the pinned native binary from the official Minisign release."""

    def execute(
        self,
        tool: dict,
        config: dict,
        platform_str: str,
        dry_run: bool,
    ) -> None:
        if not platform_str.startswith("windows"):
            print(
                f"ERROR: minisign_download does not support {platform_str}",
                file=sys.stderr,
            )
            sys.exit(1)

        params = tool.get("parameters", {})
        version = resolve_version(config, params.get("version_ref"))
        expected_sha256 = params.get("sha256")
        if not version or not expected_sha256:
            print("ERROR: pinned Minisign version and SHA256 are required", file=sys.stderr)
            sys.exit(1)

        local_app_data = os.environ.get("LOCALAPPDATA")
        if not local_app_data:
            print("ERROR: LOCALAPPDATA is required to install Minisign", file=sys.stderr)
            sys.exit(1)

        install_dir = Path(local_app_data) / "Tickoni" / "bin"
        executable = install_dir / "minisign.exe"
        if executable.is_file():
            _activate_path([str(install_dir)])
            print(f"[SKIP] minisign {version} already installed at {executable}")
            return

        url = (
            "https://github.com/jedisct1/minisign/releases/download/"
            f"{version}/minisign-{version}-win64.zip"
        )
        archive_member_arch = "aarch64" if platform_str == "windows-arm" else "x86_64"
        archive_member = f"minisign-win64/{archive_member_arch}/minisign.exe"

        if dry_run:
            print(f"  [DRY-RUN] Would download {url} -> {executable}")
            return

        with tempfile.TemporaryDirectory() as tmpdir:
            archive = Path(tmpdir) / f"minisign-{version}-win64.zip"
            _download_file(url, archive)
            _verify_sha256(archive, expected_sha256)
            try:
                with zipfile.ZipFile(archive) as bundle:
                    with bundle.open(archive_member) as source:
                        install_dir.mkdir(parents=True, exist_ok=True)
                        with executable.open("wb") as destination:
                            shutil.copyfileobj(source, destination)
            except (KeyError, zipfile.BadZipFile, OSError) as exc:
                print(f"ERROR: could not install Minisign: {exc}", file=sys.stderr)
                sys.exit(1)

        _activate_path([str(install_dir)])
        print(f"[INSTALLED] minisign {version} -> {executable}")
