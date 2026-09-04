"""Zig install strategy."""
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path
from ..base import InstallStrategy, _download_file
from .. import register
from .download import _download_and_verify, _expand_home
from config import resolve_version


ZIG_INDEX_URL = "https://ziglang.org/download/index.json"
ZIG_BUILDS_BASE_URL = "https://ziglang.org/builds"

PLATFORM_TO_ZIG_TARGET = {
    "linux-x86": "x86_64-linux",
    "linux-arm": "aarch64-linux",
    "macos-x86": "x86_64-macos",
    "macos-arm": "aarch64-macos",
    "windows-x86": "x86_64-windows",
    "windows-arm": "aarch64-windows",
}


def _url_exists(url: str) -> bool:
    """Check an upstream URL without relying on Python's DNS/IDNA stack."""
    result = subprocess.run(
        ["curl", "-fsSIL", "--retry", "3", "--max-time", "30", url],
        capture_output=True,
        text=True,
    )
    return result.returncode == 0


@register('install_zig')
class ZigInstallStrategy(InstallStrategy):
    """Install an official prebuilt Zig release."""

    def _get_minisign_pubkey(self, config: dict) -> str:
        """Read minisign key from versions.<version_ref>.options.minisign_key."""
        version_ref = self._tool.get('parameters', {}).get('version_ref')
        if not version_ref:
            return ''
        version_entry = config.get('versions', {}).get(version_ref, {})
        if isinstance(version_entry, str):
            # Legacy: bare string version with top-level zig-minisign
            zig_minisign = config.get('versions', {}).get('zig-minisign')
            if isinstance(zig_minisign, dict):
                return zig_minisign.get('key', '')
            return str(zig_minisign or '')
        options = version_entry.get('options', {})
        return options.get('minisign_key', '')

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        self._tool = tool
        self._config = config
        version_ref = tool['parameters'].get('version_ref')
        install_root = tool['parameters'].get('install_root', os.path.expanduser('~/.local'))
        user_path = tool['parameters'].get('user_path', False)

        version = resolve_version(config, version_ref)
        if not version:
            print("ERROR: no zig version in tool-versions.json", file=sys.stderr)
            sys.exit(1)

        target = PLATFORM_TO_ZIG_TARGET.get(platform_str)
        if target is None:
            print(
                f"ERROR: unknown platform '{platform_str}' for Zig; expected one of: "
                f"{', '.join(PLATFORM_TO_ZIG_TARGET.keys())}",
                file=sys.stderr,
            )
            sys.exit(1)

        if dry_run:
            print(f"  [DRY-RUN] Would install zig {version} (target={target}) to {install_root}")
            return

        self._install(version, target, install_root, user_path, platform_str)

    @staticmethod
    def _github_path_already_written(gh_path: str, install_dir_str: str) -> bool:
        """Check if install_dir is already in GITHUB_PATH."""
        try:
            with open(gh_path) as fh:
                for line in fh:
                    if line.strip() == install_dir_str:
                        return True
        except OSError:
            pass
        return False

    def _install(self, version: str, target: str, install_root: str, user_path: bool, platform_str: str) -> None:
        """Core Zig installation logic."""
        # Check if zig is already installed and on PATH.
        existing_path = shutil.which('zig')
        if existing_path:
            install_dir = Path(existing_path).resolve().parent
            install_dir_str = str(install_dir)
            gh_path = os.environ.get("GITHUB_PATH")
            if gh_path and not self._github_path_already_written(gh_path, install_dir_str):
                with open(gh_path, "a") as fh:
                    fh.write(install_dir_str + os.linesep)
                print(f"[github-path] {install_dir} (existing zig on PATH)")
            os.environ['PATH'] = f"{install_dir_str}{os.pathsep}{os.environ['PATH']}"
            print(f"[done] zig already on PATH: {existing_path}")
            return

        index_url = ZIG_INDEX_URL
        ext = ".zip" if target.endswith("-windows") else ".tar.xz"
        dev_url = f"{ZIG_BUILDS_BASE_URL}/zig-{target}-{version}{ext}"

        # Development builds are published under /builds and are not listed in
        # download/index.json. Resolve them directly so CI does not need the
        # Python urllib DNS/IDNA path (which can be missing in runner images).
        if "-dev." in version:
            archive_url = dev_url
            if not _url_exists(archive_url):
                print(f"ERROR: no Zig dev build at {archive_url}", file=sys.stderr)
                sys.exit(1)
        else:
            with urllib.request.urlopen(index_url) as resp:
                index = json.load(resp)
            version_entry = index.get(version)
            if version_entry is None:
                print(f"ERROR: Zig version '{version}' not found in {index_url}", file=sys.stderr)
                sys.exit(1)
            target_entry = version_entry.get(target)
            if target_entry is None:
                print(f"ERROR: Zig version '{version}' has no prebuilt archive for target '{target}'", file=sys.stderr)
                sys.exit(1)
            archive_url = target_entry.get("tarball") or target_entry.get("zip")
            if not archive_url:
                print(f"ERROR: Zig version '{version}' target '{target}' is missing an archive URL", file=sys.stderr)
                sys.exit(1)

        print(f"[resolve] Zig archive: {archive_url}")
        archive_name = archive_url.rsplit("/", 1)[-1]
        cache_dir = Path(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache"))) / "zig" / "archives"
        archive_path = cache_dir / archive_name
        sig_path = cache_dir / f"{archive_name}.minisig"
        sig_url = f"{archive_url}.minisig"

        # Download + verify (shared pipeline)
        pubkey = self._get_minisign_pubkey(self._config)
        if not pubkey:
            print(f"ERROR: no minisign public key in tool-versions.json", file=sys.stderr)
            sys.exit(1)

        _download_and_verify(
            url=archive_url,
            archive_path=archive_path,
            expected_sha256=None,  # Zig uses minisign only
            sig_url=sig_url,
            sig_path=sig_path,
            pubkey=pubkey,
        )

        # Extract
        extract_root = cache_dir / "extract" / f"{version}-{target}"
        if extract_root.exists():
            shutil.rmtree(extract_root)
        extract_root.mkdir(parents=True, exist_ok=True)

        if archive_name.endswith(".zip"):
            # Some Windows runner Python installations are missing the cp437
            # codec required by zipfile. Git for Windows provides unzip and
            # avoids that Python codec dependency.
            try:
                result = subprocess.run(
                    ["unzip", "-q", "-o", str(archive_path), "-d", str(extract_root)],
                    capture_output=True,
                    text=True,
                )
            except FileNotFoundError:
                print("ERROR: unzip is required to extract Zig Windows archives", file=sys.stderr)
                sys.exit(1)
            if result.returncode != 0:
                if result.stdout:
                    print(result.stdout, file=sys.stderr, end="")
                if result.stderr:
                    print(result.stderr, file=sys.stderr, end="")
                print(f"ERROR: failed to extract {archive_path}", file=sys.stderr)
                sys.exit(1)
        else:
            with tarfile.open(archive_path, "r:xz") as tf:
                tf.extractall(extract_root)

        children = [p for p in extract_root.iterdir() if p.is_dir()]
        if len(children) != 1:
            print(f"ERROR: expected exactly one extracted directory in {extract_root}, found {len(children)}", file=sys.stderr)
            sys.exit(1)
        source_dir = children[0]

        # Install
        install_dir = Path(os.path.expandvars(install_root)) / source_dir.name
        if install_dir.exists():
            shutil.rmtree(install_dir)
        install_dir.mkdir(parents=True, exist_ok=True)
        shutil.copytree(source_dir, install_dir, dirs_exist_ok=True)
        print(f"[install] zig -> {install_dir}")

        # PATH handling — install the *directory* so `zig` (or `zig.exe`) is on PATH
        install_dir_str = str(install_dir)
        if platform_str.startswith("windows"):
            self._handle_windows_path(install_dir, user_path)
        else:
            self._handle_posix_path(install_dir)

        # In-process PATH modification so subsequent tools in this process find zig
        os.environ['PATH'] = f"{install_dir_str}{os.pathsep}{os.environ['PATH']}"

        print(f"[done] zig version={version} target={target} install_dir={install_dir}")

    def _handle_windows_path(self, install_dir: Path, user_path: bool):
        install_dir_str = str(install_dir)
        gh_path = os.environ.get("GITHUB_PATH")
        if gh_path and not self._github_path_already_written(gh_path, install_dir_str):
            with open(gh_path, "a") as fh:
                fh.write(install_dir_str + os.linesep)
            print(f"[github-path] {install_dir}")
        if user_path:
            ps = (
                f"$zigDir = '{install_dir}'\n"
                "$current = [Environment]::GetEnvironmentVariable('Path', 'User')\n"
                "$parts = @()\n"
                "if ($current) { $parts = $current -split ';' | Where-Object { $_ -and ($_ -ne $zigDir) } }\n"
                "$new = ($zigDir + ';' + ($parts -join ';')).TrimEnd(';')\n"
                "[Environment]::SetEnvironmentVariable('Path', $new, 'User')\n"
            )
            subprocess.run(["powershell.exe", "-NoProfile", "-Command", ps], check=True)
            print(f"[user-path] prepend {install_dir}")

    def _handle_posix_path(self, install_dir: Path):
        install_dir_str = str(install_dir)
        gh_path = os.environ.get("GITHUB_PATH")
        if gh_path and not self._github_path_already_written(gh_path, install_dir_str):
            with open(gh_path, "a") as fh:
                fh.write(install_dir_str + os.linesep)
            print(f"[github-path] {install_dir}")
        if not gh_path:
            print(f"[activation] add Zig to your shell PATH with:")
            print(f'  export PATH="{install_dir}:$PATH"')
