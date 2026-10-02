"""Install the official Ccache binary on Windows without WinGet."""

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


@register("ccache_download")
class CcacheDownloadStrategy(InstallStrategy):
    """Install the pinned native binary from the official Ccache release."""

    def execute(
        self,
        tool: dict,
        config: dict,
        platform_str: str,
        dry_run: bool,
    ) -> None:
        archive_arch = {
            "windows-arm": "aarch64",
            "windows-x86": "x86_64",
        }.get(platform_str)
        if archive_arch is None:
            print(
                f"ERROR: ccache_download does not support {platform_str}",
                file=sys.stderr,
            )
            sys.exit(1)

        params = tool.get("parameters", {})
        version = resolve_version(config, tool.get("version_ref"))
        checksums = params.get("sha256", {})
        expected_sha256 = checksums.get(platform_str)
        if not version or not expected_sha256:
            print(
                f"ERROR: pinned Ccache version and SHA256 are required for {platform_str}",
                file=sys.stderr,
            )
            sys.exit(1)

        local_app_data = os.environ.get("LOCALAPPDATA")
        if not local_app_data:
            print("ERROR: LOCALAPPDATA is required to install Ccache", file=sys.stderr)
            sys.exit(1)

        install_dir = Path(local_app_data) / "Tickoni" / "bin"
        executable = install_dir / "ccache.exe"
        url = (
            "https://github.com/ccache/ccache/releases/download/"
            f"v{version}/ccache-{version}-windows-{archive_arch}.zip"
        )
        archive_member = (
            f"ccache-{version}-windows-{archive_arch}/ccache.exe"
        )

        if dry_run:
            print(f"  [DRY-RUN] Would download {url} -> {executable}")
            return

        if executable.is_file():
            _activate_path([str(install_dir)])
            print(f"[SKIP] ccache {version} already installed at {executable}")
            return

        with tempfile.TemporaryDirectory() as tmpdir:
            archive = Path(tmpdir) / f"ccache-{version}-windows-{archive_arch}.zip"
            _download_file(url, archive)
            _verify_sha256(archive, expected_sha256)
            try:
                with zipfile.ZipFile(archive) as bundle:
                    with bundle.open(archive_member) as source:
                        install_dir.mkdir(parents=True, exist_ok=True)
                        with executable.open("wb") as destination:
                            shutil.copyfileobj(source, destination)
            except (KeyError, zipfile.BadZipFile, OSError) as exc:
                print(f"ERROR: could not install Ccache: {exc}", file=sys.stderr)
                sys.exit(1)

        _activate_path([str(install_dir)])
        print(f"[INSTALLED] ccache {version} -> {executable}")
