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
from config import resolve_version


ZIG_INDEX_URL = "https://ziglang.org/download/index.json"
ZIG_BUILDS_BASE_URL = "https://ziglang.org/builds"
ZIG_MINISIGN_PUBKEY = "RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U"

PLATFORM_TO_ZIG_TARGET = {
    "linux-x86": "x86_64-linux",
    "linux-arm": "aarch64-linux",
    "macos-x86": "x86_64-macos",
    "macos-arm": "aarch64-macos",
    "windows-x86": "x86_64-windows",
    "windows-arm": "aarch64-windows",
}


class _ZigMinisigVerifier:
    """Helper for Zig minisign verification."""

    def __init__(self, pubkey: str):
        self.pubkey = pubkey

    def find(self) -> str | None:
        for name in ("minisign", "minisign-verify", "minisig"):
            found = shutil.which(name)
            if found:
                return found
        return None

    def verify(self, archive_path: Path, sig_path: Path) -> None:
        minisign = self.find()
        if not minisign:
            print(
                f"[WARN] minisign binary not found on PATH — skipping signature "
                f"verification for {archive_path.name}",
                file=sys.stderr,
            )
            print(
                "  To enable verification, install minisign: apt install minisign "
                "(Debian/Ubuntu), brew install minisign (macOS), or "
                "winget install jedisct1.minisign (Windows)",
                file=sys.stderr,
            )
            return
        cmd = [minisign, "V", "-P", self.pubkey, "-x", str(sig_path), "-m", str(archive_path)]
        print(f"[verify] minisig {archive_path.name} ...")
        result = subprocess.run(cmd, capture_output=False, text=True)
        if result.returncode != 0:
            print(f"ERROR: minisig verification FAILED for {archive_path.name}", file=sys.stderr)
            sys.exit(1)
        print("[verify] minisig OK")


@register('install_zig')
class ZigInstallStrategy(InstallStrategy):
    """Install an official prebuilt Zig release."""

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
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

    def _install(self, version: str, target: str, install_root: str, user_path: bool, platform_str: str) -> None:
        """Core Zig installation logic."""
        index_url = ZIG_INDEX_URL

        with urllib.request.urlopen(index_url) as resp:
            index = json.load(resp)
        version_entry = index.get(version)
        if version_entry is None:
            ext = ".zip" if target.endswith("-windows") else ".tar.xz"
            dev_url = f"{ZIG_BUILDS_BASE_URL}/zig-{target}-{version}{ext}"
            req = urllib.request.Request(dev_url, method="HEAD")
            try:
                urllib.request.urlopen(req)
                archive_url = dev_url
            except Exception:
                print(f"ERROR: Zig version '{version}' not found in {index_url} and no dev build at {dev_url}", file=sys.stderr)
                sys.exit(1)
        else:
            target_entry = version_entry.get(target)
            if target_entry is None:
                print(f"ERROR: Zig version '{version}' has no prebuilt archive for target '{target}'", file=sys.stderr)
                sys.exit(1)
            archive_url = target_entry.get("tarball") or target_entry.get("zip")
            if not archive_url:
                print(f"ERROR: Zig version '{version}' target '{target}' is missing an archive URL", file=sys.stderr)
                sys.exit(1)

        archive_name = archive_url.rsplit("/", 1)[-1]
        cache_dir = Path(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache"))) / "zig" / "archives"
        archive_path = cache_dir / archive_name
        sig_path = cache_dir / f"{archive_name}.minisig"

        print(f"[download] {archive_name}")
        _download_file(archive_url, archive_path, dry_run=False)

        # Minisign verification
        sig_url = f"{archive_url}.minisig"
        sig_exists = False
        try:
            req = urllib.request.Request(sig_url, method="HEAD")
            urllib.request.urlopen(req)
            sig_exists = True
        except Exception:
            pass

        if sig_exists:
            _download_file(sig_url, sig_path, dry_run=False)
            verifier = _ZigMinisigVerifier(ZIG_MINISIGN_PUBKEY)
            verifier.verify(archive_path, sig_path)
        else:
            print(f"ERROR: required minisig signature not found at {sig_url}", file=sys.stderr)
            sys.exit(1)

        # Extract
        extract_root = cache_dir / "extract" / f"{version}-{target}"
        if extract_root.exists():
            shutil.rmtree(extract_root)
        extract_root.mkdir(parents=True, exist_ok=True)

        if archive_name.endswith(".zip"):
            import zipfile
            with zipfile.ZipFile(archive_path) as zf:
                zf.extractall(extract_root)
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

        # PATH handling
        bin_dir = str(install_dir / "zig")
        if platform_str.startswith("windows"):
            self._handle_windows_path(bin_dir, user_path)
        else:
            self._handle_posix_path(bin_dir)

        print(f"[done] zig version={version} target={target} install_dir={install_dir}")

    def _handle_windows_path(self, bin_dir: str, user_path: bool):
        gh_path = os.environ.get("GITHUB_PATH")
        if gh_path:
            with open(gh_path, "a") as fh:
                fh.write(bin_dir + os.linesep)
            print(f"[github-path] {bin_dir}")
        if user_path:
            ps = (
                f"$zigDir = '{bin_dir}'\n"
                "$current = [Environment]::GetEnvironmentVariable('Path', 'User')\n"
                "$parts = @()\n"
                "if ($current) { $parts = $current -split ';' | Where-Object { $_ -and ($_ -ne $zigDir) } }\n"
                "$new = ($zigDir + ';' + ($parts -join ';')).TrimEnd(';')\n"
                "[Environment]::SetEnvironmentVariable('Path', $new, 'User')\n"
            )
            subprocess.run(["powershell.exe", "-NoProfile", "-Command", ps], check=True)
            print(f"[user-path] prepend {bin_dir}")

    def _handle_posix_path(self, bin_dir: str):
        gh_path = os.environ.get("GITHUB_PATH")
        if gh_path:
            with open(gh_path, "a") as fh:
                fh.write(bin_dir + os.linesep)
            print(f"[github-path] {bin_dir}")
        if not gh_path:
            print(f"[activation] add Zig to your shell PATH with:")
            print(f'  export PATH="{bin_dir}:$PATH"')
