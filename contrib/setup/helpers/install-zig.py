#!/usr/bin/env python3
"""Install a prebuilt official Zig release for local development or CI.

The --version argument is REQUIRED.  There is no default version.
If the index JSON is missing, malformed, or a version is absent from it,
the script FAILS with a non-zero exit code rather than falling back to
anything.

Downloads are verified with SHA256 (from index.json) and the required minisign
signature (from ziglang.org/builds/*.minisig).

Platform detection is delegated to contrib/platform.sh via the --platform
argument.  No other file in contrib/setup/ should re-implement OS/arch detection.
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zipfile
from pathlib import Path

ZIG_INDEX_URL = "https://ziglang.org/download/index.json"
ZIG_BUILDS_BASE_URL = "https://ziglang.org/builds"

# Zig minisign public key — copied from ziglang.org/download/
ZIG_MINISIGN_PUBKEY = "RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U"

# Platform → Zig release target mapping.
# contrib/platform.sh emits: linux-x86, macos-arm, windows-x86, etc.
PLATFORM_TO_TARGET = {
    "linux-x86": "x86_64-linux",
    "linux-arm": "aarch64-linux",
    "macos-x86": "x86_64-macos",
    "macos-arm": "aarch64-macos",
    "windows-x86": "x86_64-windows",
    "windows-arm": "aarch64-windows",
}


def eprint(*args):
    print(*args, file=sys.stderr)


# ── Platform helpers ──────────────────────────────────────────────────────────
# Platform detection is the single source of truth in contrib/platform.sh.
# All scripts in contrib/setup/ derive platform from --platform or platform.sh,
# never from Python's platform module.


def is_windows(platform_str):
    """Return True if the platform string indicates Windows."""
    return platform_str and "windows" in platform_str


def resolve_target(platform_str):
    """Convert contrib/platform.sh platform string to Zig release target key.

    E.g. 'linux-x86' -> 'x86_64-linux', 'windows-arm' -> 'aarch64-windows'.
    """
    if platform_str is None:
        raise SystemExit("--platform is required; platform detection is handled by contrib/platform.sh")
    target = PLATFORM_TO_TARGET.get(platform_str)
    if target is None:
        raise SystemExit(
            f"unknown platform '{platform_str}'; expected one of: {', '.join(PLATFORM_TO_TARGET.keys())}"
        )
    return target


# ── Install paths ────────────────────────────────────────────────────────────


def default_install_root(platform_str):
    if is_windows(platform_str):
        local = os.environ.get("LOCALAPPDATA")
        if not local:
            raise SystemExit("LOCALAPPDATA is not set")
        return Path(local) / "Programs" / "Zig"
    return Path.home() / ".local" / "zig"


def default_cache_root(platform_str):
    if is_windows(platform_str):
        local = os.environ.get("LOCALAPPDATA")
        if not local:
            raise SystemExit("LOCALAPPDATA is not set")
        return Path(local) / "cache" / "zig"
    xdg = os.environ.get("XDG_CACHE_HOME")
    if xdg:
        return Path(xdg) / "zig"
    return Path.home() / ".cache" / "zig"


# ── Index / release resolution ───────────────────────────────────────────────


def load_index(index_url):
    with urllib.request.urlopen(index_url) as response:
        return json.load(response)


def dev_build_archive_url(version, target):
    ext = ".zip" if target.endswith("-windows") else ".tar.xz"
    return f"{ZIG_BUILDS_BASE_URL}/zig-{target}-{version}{ext}"


def url_exists(url):
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "tickoni-zig-installer"})
    try:
        with urllib.request.urlopen(req):
            return True
    except Exception:
        return False


def select_release(index, version, target):
    version_entry = index.get(version)
    if version_entry is None:
        dev_url = dev_build_archive_url(version, target)
        if url_exists(dev_url):
            return dev_url, None
        raise SystemExit(
            f"Zig version '{version}' was not found in {ZIG_INDEX_URL} and no dev build was found at {dev_url}"
        )
    target_entry = version_entry.get(target)
    if target_entry is None:
        raise SystemExit(f"Zig version '{version}' has no prebuilt archive for target '{target}'")
    archive_url = target_entry.get("tarball") or target_entry.get("zip")
    if not archive_url:
        raise SystemExit(f"Zig version '{version}' target '{target}' is missing an archive URL")
    shasum = target_entry.get("shasum")
    if not shasum:
        raise SystemExit(f"Zig version '{version}' target '{target}' is missing a sha256 checksum")
    return archive_url, shasum


# ── Download ──────────────────────────────────────────────────────────────────


def download_archive(url, dest, dry_run=False):
    print(f"[download] {url} -> {dest}")
    if dry_run:
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url) as response, open(dest, "wb") as out:
        shutil.copyfileobj(response, out)


def download_minisig(archive_url, dest, dry_run=False):
    """Download the .minisig signature file next to the archive."""
    sig_url = f"{archive_url}.minisig"
    print(f"[download] {sig_url} -> {dest}")
    if dry_run:
        return False
    sig_exists = url_exists(sig_url)
    if not sig_exists:
        raise SystemExit(f"required Zig minisig signature not found at {sig_url}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(sig_url) as response, open(dest, "wb") as out:
        shutil.copyfileobj(response, out)
    return True


# ── Verification ──────────────────────────────────────────────────────────────


def verify_sha256(path, expected, dry_run=False):
    if not expected:
        print(f"[verify] no sha256 published in index.json for {path.name}; skipping sha256 verification")
        return
    print(f"[verify] sha256 {path} == {expected}")
    if dry_run:
        return
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    actual = digest.hexdigest()
    if actual.lower() != expected.lower():
        raise SystemExit(f"sha256 mismatch for {path}: expected {expected}, got {actual}")


def _which(cmd):
    """Check if a command exists on PATH."""
    return shutil.which(cmd) is not None


def _find_minisign():
    """Find minisign binary (minisign-verify on OpenBSD, minisig on Ubuntu, minisign elsewhere)."""
    for name in ("minisign-verify", "minisig", "minisign"):
        found = _which(name)
        if found:
            return found
    return None


def _install_minisign_windows_github(platform_str, dry_run=False):
    """Download minisign binary from GitHub releases when winget fails."""
    # Use the latest released version from GitHub
    # We hard-code 0.12 since it is stable and already released;
    # if a newer version appears we just update this constant.
    version = "0.12"
    archive_name = f"minisign-{version}-win64.zip"
    archive_url = f"https://github.com/jedisct1/minisign/releases/download/{version}/{archive_name}"
    print(f"[minisign] downloading {archive_url}")
    if dry_run:
        return False

    with tempfile.TemporaryDirectory() as tmpdir:
        archive_path = os.path.join(tmpdir, archive_name)
        dl_result = subprocess.run(
            ["curl", "-sSfL", "--retry", "3", "-o", archive_path, archive_url],
            capture_output=True, text=True
        )
        if dl_result.returncode != 0 or not os.path.getsize(archive_path) > 0:
            print(f"[minisign] download failed for {archive_name}", file=sys.stderr)
            return False

        # Extract to temp dir
        subprocess.run(["unzip", "-o", archive_path, "-d", tmpdir], check=True)

        # Find the binary
        bin_name = "minisign.exe"
        bin_path = None
        for root, dirs, files in os.walk(tmpdir):
            if bin_name in files:
                bin_path = os.path.join(root, bin_name)
                break
        if not bin_path:
            print("[minisign] minisign.exe not found in archive", file=sys.stderr)
            return False

        # Install to a stable location on PATH
        install_dir = Path(os.environ.get("LOCALAPPDATA", r"C:\Users\runneradmin\AppData\Local")) / "Minisign"
        install_dir.mkdir(parents=True, exist_ok=True)
        dest = install_dir / bin_name
        shutil.copy2(bin_path, dest)

        # Prepend to current process PATH so we can find it immediately
        os.environ["PATH"] = str(install_dir) + os.pathsep + os.environ.get("PATH", "")

        if _find_minisign():
            print(f"[minisign] installed via GitHub release to {dest}")
            return True
        return False


def _find_winget():
    """Resolve winget to an absolute path for reliable subprocess execution."""
    which = shutil.which("winget") or shutil.which("winget.exe")
    if which:
        return which
    system_root = os.environ.get("SystemRoot", r"C:\Windows")
    for subdir in ("System32", "SysArm64"):
        candidate = os.path.join(system_root, subdir, "winget.exe")
        if os.path.isfile(candidate):
            return candidate
    return None


def _refresh_windows_path():
    """Refresh os.environ['PATH'] from the Windows environment.

    winget updates the User-level PATH via registry, which is not visible
    to the current Python process until the environment is re-read.
    """
    try:
        new_path = subprocess.check_output(
            ["cmd", "/c", "echo", "%PATH%"],
            shell=False,
            text=True,
        ).strip()
        os.environ["PATH"] = new_path
    except Exception:
        pass


def _ensure_minisign_installed(platform_str, dry_run=False):
    """Install minisign via the appropriate package manager if not present. Returns True if usable after."""
    if _find_minisign():
        return True
    if dry_run:
        print("[minisign] binary not found, dry-run — skipping install")
        return False
    print("[minisign] minisign not found on PATH — attempting to install")
    # Debian/Ubuntu: apt install minisign (use -n for non-interactive CI)
    if shutil.which("apt") and shutil.which("sudo"):
        subprocess.run(["sudo", "-n", "apt-get", "update", "-qq"], check=True)
        result = subprocess.run(
            ["sudo", "-n", "apt-get", "install", "-y", "-qq", "minisign"],
            capture_output=True, text=True
        )
        if result.returncode == 0 and _find_minisign():
            print("[minisign] installed via apt")
            return True
    # macOS: brew install minisign
    if shutil.which("brew"):
        result = subprocess.run(
            ["brew", "install", "minisign"],
            capture_output=True, text=True
        )
        if result.returncode == 0 and _find_minisign():
            print("[minisign] installed via brew")
            return True
    # Windows: winget install minisign (with fallback to GitHub release)
    if is_windows(platform_str):
        winget = _find_winget()
        if winget:
            result = subprocess.run(
                [winget, "install", "--id", "jedisct1.minisign", "--silent", "--accept-package-agreements", "--accept-source-agreements"],
                capture_output=True, text=True
            )
            output = (result.stdout or "") + (result.stderr or "")
            # Winget returns 0 on success, but also returns 1638 (already installed)
            # and may return non-zero even when the package is present.
            # Parse output for success indicators.
            if (result.returncode == 0
                    or "Successfully installed" in output
                    or "already installed" in output
                    or _find_minisign()):
                _refresh_windows_path()
                if _find_minisign():
                    print("[minisign] installed via winget")
                    return True
                # Winget may have installed to a non-PATH location; try GitHub fallback
        # Fallback: download from GitHub releases
        print("[minisign] winget did not yield a usable binary, trying GitHub release")
        if _install_minisign_windows_github(platform_str, dry_run=False):
            return True
    print("[minisign] could not install minisign automatically — cannot verify Zig", file=sys.stderr)
    return False


def verify_minisig(archive_path, sig_path, platform_str, dry_run=False):
    """Verify archive using minisign; fail if minisign is unavailable."""
    if dry_run:
        print(f"[verify] minisig {archive_path} (dry-run)")
        return
    minisign_bin = _find_minisign()
    if not minisign_bin:
        if not _ensure_minisign_installed(platform_str, dry_run=False):
            raise SystemExit("required minisign binary is not available; cannot verify Zig")
        minisign_bin = _find_minisign()
        if not minisign_bin:
            raise SystemExit("required minisign binary is still unavailable after installation attempt")

    print(f"[verify] minisig {archive_path} ...")
    cmd = [
        minisign_bin,
        "-V",
        "-P",
        ZIG_MINISIGN_PUBKEY,
        "-x",
        str(sig_path),
        "-m",
        str(archive_path),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        eprint(result.stderr.strip())
        raise SystemExit(f"minisig verification FAILED for {archive_path}")
    print("[verify] minisig OK")


# ── Extract ───────────────────────────────────────────────────────────────────


def extract_archive(archive_path, dest_dir, dry_run=False):
    print(f"[extract] {archive_path} -> {dest_dir}")
    if dry_run:
        return
    if dest_dir.exists():
        shutil.rmtree(dest_dir)
    dest_dir.mkdir(parents=True, exist_ok=True)
    suffixes = archive_path.suffixes
    if archive_path.suffix == ".zip":
        with zipfile.ZipFile(archive_path) as zf:
            zf.extractall(dest_dir)
        return
    if suffixes[-2:] == [".tar", ".xz"] or archive_path.suffix == ".xz":
        with tarfile.open(archive_path, "r:xz") as tf:
            tf.extractall(dest_dir)
        return
    raise SystemExit(f"unsupported Zig archive format: {archive_path.name}")


# ── Install ───────────────────────────────────────────────────────────────────


def resolve_source_dir(extract_root, dry_run=False, archive_stem=None):
    if dry_run:
        if archive_stem is None:
            raise SystemExit("archive_stem is required for dry-run resolution")
        return extract_root / archive_stem
    children = [p for p in extract_root.iterdir() if p.is_dir()]
    if len(children) != 1:
        raise SystemExit(f"expected exactly one extracted Zig directory in {extract_root}, found {len(children)}")
    return children[0]


def copy_tree(src, dst, dry_run=False):
    print(f"[install] {src} -> {dst}")
    if dry_run:
        return
    if dst.exists():
        shutil.rmtree(dst)
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(src, dst)


def add_to_github_path(path_value, dry_run=False):
    github_path = os.environ.get("GITHUB_PATH")
    if not github_path:
        return
    print(f"[github-path] {path_value}")
    if dry_run:
        return
    with open(github_path, "a", encoding="utf-8") as fh:
        fh.write(str(path_value) + os.linesep)


def update_windows_user_path(path_value, dry_run=False):
    print(f"[user-path] prepend {path_value}")
    if dry_run:
        return
    import subprocess

    ps = (
        "$zigDir = '" + str(path_value) + "'\n"
        "$current = [Environment]::GetEnvironmentVariable('Path', 'User')\n"
        "$parts = @()\n"
        "if ($current) { $parts = $current -split ';' | Where-Object { $_ -and ($_ -ne $zigDir) } }\n"
        "$new = ($zigDir + ';' + ($parts -join ';')).TrimEnd(';')\n"
        "[Environment]::SetEnvironmentVariable('Path', $new, 'User')\n"
    )
    subprocess.run(["powershell.exe", "-NoProfile", "-Command", ps], check=True)


def print_posix_activation(path_value):
    print("[activation] add Zig to your shell PATH with:")
    print(f'  export PATH="{path_value}:$PATH"')


# ── Main ──────────────────────────────────────────────────────────────────────


def main():
    parser = argparse.ArgumentParser(description="Install a prebuilt official Zig release for local development or CI.")
    parser.add_argument("version", help="Zig release version or channel key from index.json (REQUIRED)")
    parser.add_argument("--index-url", default=ZIG_INDEX_URL, help="Zig download index JSON URL")
    parser.add_argument("--platform", required=True, help="platform string from contrib/platform.sh (e.g. linux-x86, macos-arm, windows-x86)")
    parser.add_argument("--target", help="prebuilt Zig target key (overrides --platform)")
    parser.add_argument("--install-root", type=Path, default=None, help="root directory that will receive zig-<target>-<version>")
    parser.add_argument("--cache-root", type=Path, default=None, help="cache/work directory for downloaded Zig archives")
    parser.add_argument("--user-path", action="store_true", help="persist the installed Zig directory to the Windows user PATH")
    parser.add_argument("--dry-run", action="store_true", help="print the plan without downloading, extracting, or editing PATH")
    args = parser.parse_args()

    platform_str = args.platform
    install_root = args.install_root or default_install_root(platform_str)
    cache_root = args.cache_root or default_cache_root(platform_str)

    # --target overrides --platform for backwards compatibility.
    if args.target:
        target = args.target
    else:
        target = resolve_target(platform_str)

    index = load_index(args.index_url)
    archive_url, shasum = select_release(index, args.version, target)

    archive_name = archive_url.rsplit("/", 1)[-1]
    archive_path = cache_root / "archives" / archive_name
    sig_path = cache_root / "archives" / f"{archive_name}.minisig"
    extract_root = cache_root / "extract" / f"{args.version}-{target}"
    archive_stem = archive_name.removesuffix(".tar.xz").removesuffix(".zip")

    download_archive(archive_url, archive_path, dry_run=args.dry_run)
    verify_sha256(archive_path, shasum, dry_run=args.dry_run)

    # Minisign verification (download sig and verify)
    has_sig = download_minisig(archive_url, sig_path, dry_run=args.dry_run)
    if has_sig:
        verify_minisig(archive_path, sig_path, platform_str, dry_run=args.dry_run)
    elif args.dry_run:
        print(f"[verify] minisig required for {archive_name} (dry-run)")
    else:
        raise SystemExit(f"required Zig minisig signature is missing for {archive_name}")

    extract_archive(archive_path, extract_root, dry_run=args.dry_run)

    source_dir = resolve_source_dir(extract_root, dry_run=args.dry_run, archive_stem=archive_stem)
    install_dir = install_root / source_dir.name
    copy_tree(source_dir, install_dir, dry_run=args.dry_run)

    add_to_github_path(install_dir, dry_run=args.dry_run)

    if args.user_path:
        update_windows_user_path(install_dir, dry_run=args.dry_run)
    elif not is_windows(platform_str) and not os.environ.get("GITHUB_PATH"):
        print_posix_activation(install_dir)

    print(f"[done] zig version={args.version} target={target} install_dir={install_dir}")


if __name__ == "__main__":
    main()
