"""Download strategies: github_release, binary_download, and archive_download."""
import hashlib
import json
import os
import shutil
import sys
import urllib.request
from pathlib import Path
from ..base import DownloadInstallStrategy, _activate_path, _run_cmd, _download_file
from .. import register
from config import resolve_version
try:
    from ...platform import get_platform_from_string
except ImportError:
    # orchestrator.py is also executed directly, with contrib/setup on
    # sys.path rather than imported as the contrib.setup package.
    from platform import get_platform_from_string

# ── helpers ──────────────────────────────────────────────────────────────────

def _expand_home(path: str) -> str:
    """Expand ~ to HOME."""
    if path == '~':
        path = os.environ.get('HOME', os.path.expanduser('~'))
    elif path.startswith('~/'):
        path = os.path.join(os.environ.get('HOME', os.path.expanduser('~')), path[2:])
    return path


def _is_windows(platform_str: str) -> bool:
    """Decide Windows from the orchestrator-supplied platform string."""
    return platform_str.startswith('windows')


def _verify_sha256(archive_path: Path, expected: str) -> None:
    """Verify a file's SHA256 against an expected hex digest."""
    actual = hashlib.sha256(archive_path.read_bytes()).hexdigest()
    if actual != expected:
        print(f"ERROR: SHA256 mismatch for {archive_path.name}", file=__import__('sys').stderr)
        print(f"  expected: {expected}", file=__import__('sys').stderr)
        print(f"  actual:   {actual}", file=__import__('sys').stderr)
        __import__('sys').exit(1)


def _extract_archive(archive_path: Path, dest: str, extract_dir: str, version: str | None) -> None:
    """Extract tar.gz / zip into *dest*, flattening one inner directory if present."""
    name = archive_path.name
    if name.endswith(('.tar.gz', '.tgz')):
        import tarfile
        with tarfile.open(archive_path) as tf:
            tf.extractall(dest)
    elif name.endswith('.zip'):
        import zipfile
        with zipfile.ZipFile(archive_path) as zf:
            zf.extractall(dest)
    else:
        print(f"ERROR: unsupported archive format: {name}", file=__import__('sys').stderr)
        __import__('sys').exit(1)

    # Flatten one inner directory (common with versioned tarball roots).
    if extract_dir and extract_dir != '.':
        expanded = extract_dir.replace('{version}', version or '')
        inner = os.path.join(dest, expanded)
        if os.path.isdir(inner):
            for item in os.listdir(inner):
                src = os.path.join(inner, item)
                dst = os.path.join(dest, item)
                if os.path.exists(dst):
                    continue
                os.rename(src, dst)
            os.rmdir(inner)


def _verify_minisign(archive_path: Path, sig_path: Path, pubkey: str) -> None:
    """Verify an archive's minisign signature against *pubkey*.

    If no minisign binary is on PATH, if the sig file is empty/missing,
    or if the build name contains ``-dev.``, a warning is logged and
    verification continues (never exits).
    """
    import shutil
    import subprocess

    minisign = shutil.which('minisign')
    if not minisign:
        minisign = shutil.which('minisign-verify')
    if not minisign:
        minisign = shutil.which('minisig')

    if not minisign:
        print(
            f"[WARN] minisign binary not found on PATH — skipping signature "
            f"verification for {archive_path.name}",
            file=__import__('sys').stderr,
        )
        return

    # If signature file is empty or missing, skip verification
    if not sig_path.exists() or sig_path.stat().st_size == 0:
        print(
            f"[WARN] signature file {sig_path.name} is empty or missing — "
            f"skipping verification for {archive_path.name}",
            file=__import__('sys').stderr,
        )
        return

    cmd = [minisign, "-V", "-P", pubkey, "-x", str(sig_path), "-m", str(archive_path)]
    print(f"[verify] minisig {archive_path.name} ...")
    result = subprocess.run(cmd, capture_output=False, text=True)
    if result.returncode != 0:
        # Dev builds may use a different signing key or have corrupted
        # signatures; treat as warning only for dev builds.
        is_dev = "-dev." in archive_path.name or ".dev." in archive_path.name
        if is_dev:
            print(
                f"[WARN] minisig verification FAILED for dev build {archive_path.name}; "
                f"continuing without verified signature",
                file=__import__('sys').stderr,
            )
            return
        print(f"ERROR: minisig verification FAILED for {archive_path.name}", file=__import__('sys').stderr)
        __import__('sys').exit(1)
    print("[verify] minisig OK")


def _download_and_verify(
    url: str,
    archive_path: Path,
    expected_sha256: str | None,
    sig_url: str | None = None,
    sig_path: Path | None = None,
    pubkey: str | None = None,
) -> None:
    """Template Method: download an archive with optional SHA256 and minisign verification.

    Parameters
    ----------
    url : str
        Download URL for the archive.
    archive_path : Path
        Where to save the downloaded archive.
    expected_sha256 : str or None
        Expected hex SHA256 digest.  If given, verification runs.
    sig_url : str or None
        URL for the minisign signature file.  If given together with
        *pubkey*, the signature is downloaded and verified.
    sig_path : Path or None
        Local path to save the signature file (also the path used for
        verification if it already exists from the download above).
    pubkey : str or None
        Minisign public key string.
    """
    import urllib.request

    # 1. Download the archive
    print(f"[DOWNLOAD] {url} -> {archive_path}")
    _download_file(url, archive_path, dry_run=False)

    if not archive_path.exists() or archive_path.stat().st_size == 0:
        print(f"ERROR: downloaded file is empty: {url}", file=__import__('sys').stderr)
        __import__('sys').exit(1)

    # 2. SHA256 verification
    if expected_sha256:
        print("[CHECKSUM] Verifying SHA256 ...")
        _verify_sha256(archive_path, expected_sha256)
        print(f"[CHECKSUM] SHA256 verified for {archive_path.name}")

    # 3. Minisign verification
    if sig_url and pubkey:
        if sig_path is None:
            sig_path = archive_path.with_suffix(archive_path.suffix + '.minisig')

        print(f"[resolve] Minisign signature: {sig_url}")
        _download_file(sig_url, sig_path, dry_run=False)
        _verify_minisign(archive_path, sig_path, pubkey)


def resolve_version_from_config(config: dict, version_ref: str) -> str | None:
    """Thin re-export of config.resolve_version.

    Strategies can import this directly from download.py instead of
    reaching into config.py, keeping all download/verify plumbing in
    one module.
    """
    return resolve_version(config, version_ref)


# ── strategies ───────────────────────────────────────────────────────────────

@register('github_release')
class GitHubReleaseStrategy(DownloadInstallStrategy):
    """Install from GitHub releases."""

    def _resolve_url(self, tool: dict, config: dict, platform_str: str) -> tuple[str, str, str, bool]:
        params = tool['parameters']
        source = params.get('type', 'standard')
        owner = params.get('owner')
        repo = params.get('repo')
        version_ref = params.get('version_ref')
        version = resolve_version(config, version_ref)
        verify_checksum = params.get('verify_checksum', False)

        if source == 'cbmc_deb':
            self._install_cbmc_deb(tool, params, config, platform_str, version)
            return ('', '', '', False)
        if source == 'litani_deb':
            print("[INFO] Litani is installed with CBMC; skipping standalone install")
            return ('', '', '', False)

        os_name, arch = get_platform_from_string(platform_str)
        if os_name == 'macos':
            os_name = 'darwin'
        asset_pattern_os_map = params.get('asset_pattern_os_map', {})
        asset_pattern = params.get('asset_pattern', '')
        pattern = ''

        if asset_pattern_os_map:
            os_map = asset_pattern_os_map.get(os_name, '')
            pattern = os_map.get(arch, '') if isinstance(os_map, dict) else str(os_map)
        elif asset_pattern:
            pattern = asset_pattern.replace('{os}', os_name).replace('{arch}', arch)
        else:
            print(f"ERROR: no asset pattern defined for {owner or repo}", file=__import__('sys').stderr)
            __import__('sys').exit(1)

        if not pattern:
            print(f"ERROR: could not resolve asset for {platform_str}", file=__import__('sys').stderr)
            __import__('sys').exit(1)

        if version:
            pattern = pattern.replace('{version}', version)
        else:
            url = f"https://api.github.com/repos/{owner}/{repo}/releases/latest"
            result = _run_cmd(['curl', '-sSfL', url])
            if result.returncode != 0:
                print(f"ERROR: could not fetch latest release", file=__import__('sys').stderr)
                __import__('sys').exit(1)
            release = json.loads(result.stdout)
            version = release.get('tag_name', '').lstrip('v')
            pattern = pattern.replace('{version}', version)

        download_url = f"https://github.com/{owner}/{repo}/releases/download/v{version}/{pattern}"
        return (download_url, version, pattern, verify_checksum)

    def _install_cbmc_deb(self, tool, params, config, platform_str, version):
        """Install CBMC from GitHub release (Ubuntu-specific deb)."""
        if "linux" not in platform_str:
            print(f"WARNING: CBMC is Linux-only, skipping on {platform_str}", file=__import__('sys').stderr)
            return

        ubuntu_ver = None
        try:
            with open('/etc/os-release') as f:
                for line in f:
                    if line.startswith('VERSION_ID='):
                        ubuntu_ver = line.split('=')[1].strip().strip('"')
                        break
        except FileNotFoundError:
            pass

        if ubuntu_ver not in ('22.04', '24.04'):
            print(f"WARNING: CBMC requires Ubuntu 22.04 or 24.04 (got {ubuntu_ver}), skipping", file=__import__('sys').stderr)
            return

        arch = None
        for part in platform_str.split('-'):
            if part in ('x86', 'arm'):
                arch = part
        if arch == 'x86':
            prefix = f'ubuntu-{ubuntu_ver}-cbmc-'
        elif arch == 'arm' and ubuntu_ver == '24.04':
            prefix = 'ubuntu-24.04-arm64-cbmc-'
        else:
            print(f"WARNING: unsupported arch {platform_str} for CBMC, skipping", file=__import__('sys').stderr)
            return

        import tempfile
        with tempfile.TemporaryDirectory() as tmpdir:
            result = _run_cmd(['curl', '-sSfL', 'https://api.github.com/repos/diffblue/cbmc/releases/latest'])
            if result.returncode != 0:
                print(f"WARNING: could not fetch CBMC releases", file=__import__('sys').stderr)
                return
            release = json.loads(result.stdout)
            assets = release.get('assets', [])
            matching = [a for a in assets if a['name'].startswith(prefix) and a['name'].endswith('-Linux.deb')]
            if not matching:
                matching = [a for a in assets if a['name'].startswith(prefix) and a['name'].endswith('.deb')]
            if not matching:
                print(f"WARNING: no matching CBMC asset found for {prefix}", file=__import__('sys').stderr)
                return
            url = matching[0]['browser_download_url']
            deb_path = Path(tmpdir) / 'cbmc.deb'
            self._download_file(url, deb_path)

            litani_result = _run_cmd(['curl', '-sSfL', 'https://api.github.com/repos/awslabs/aws-build-accumulator/releases/latest'])
            litani_release = json.loads(litani_result.stdout) if litani_result.returncode == 0 else {'assets': []}
            litani_assets = litani_release.get('assets', [])
            litani_match = [a for a in litani_assets if a['name'].startswith('litani-') and a['name'].endswith('.deb')]
            if litani_match:
                litani_url = litani_match[0]['browser_download_url']
                litani_path = Path(tmpdir) / 'litani.deb'
                self._download_file(litani_url, litani_path)
                _run_cmd(['sudo', 'apt-get', 'install', '-y', '--no-install-recommends', str(deb_path), str(litani_path), 'universal-ctags'])
            else:
                _run_cmd(['sudo', 'apt-get', 'install', '-y', '--no-install-recommends', str(deb_path), 'universal-ctags'])


def _relocate_dir(src: Path, dest: str) -> None:
    """Replace the directory tree at *dest* with *src*, using sudo if needed."""
    parent = os.path.dirname(os.path.abspath(dest))
    existing_ancestor = parent
    while existing_ancestor and not os.path.isdir(existing_ancestor):
        existing_ancestor = os.path.dirname(existing_ancestor)
    can_write = os.access(existing_ancestor, os.W_OK) and (
        not os.path.exists(dest) or os.access(dest, os.W_OK)
    )
    if can_write:
        os.makedirs(parent, exist_ok=True)
        if os.path.exists(dest):
            shutil.rmtree(dest)
        shutil.move(str(src), dest)
    else:
        _run_cmd(['sudo', 'rm', '-rf', dest])
        _run_cmd(['sudo', 'mkdir', '-p', parent])
        _run_cmd(['sudo', 'cp', '-a', str(src), dest])


@register('binary_download')
class BinaryDownloadStrategy(DownloadInstallStrategy):
    """Install a toolchain shipped as a versioned tarball.

    The archive is expected to unpack to a single top-level directory (the Go
    distribution's ``go1.x.y.<os>-<arch>.tar.gz`` unpacks to ``go/``). That
    directory is moved into ``install_dir`` and the configured ``bin_dirs``
    are put on PATH for the rest of the run, ``$GITHUB_PATH``, and the shell.
    """

    def _resolve_url(self, tool: dict, config: dict, platform_str: str) -> tuple[str, str, str, bool]:
        params = tool['parameters']
        url_pattern = params.get('url_pattern', '')
        version_ref = params.get('version_ref')

        version = resolve_version(config, version_ref)
        if not version:
            print(f"ERROR: no version for {tool['name']}", file=sys.stderr)
            sys.exit(1)

        os_name, arch = get_platform_from_string(platform_str)
        if os_name == 'macos':
            os_name = 'darwin'
        arch_map = {'x86': 'amd64', 'x86_64': 'amd64', 'arm': 'arm64', 'arm64': 'arm64', 'aarch64': 'arm64'}
        if arch is not None:
            arch = arch_map.get(arch, arch)

        url = url_pattern.replace('{version}', version)
        url = url.replace('{{.os}}', os_name).replace('{{.arch}}', arch)
        return (url, version, os.path.basename(url), False)

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        url, version, pattern, _ = self._resolve_url(tool, config, platform_str)
        params = tool['parameters']
        name = tool['name']
        install_dir = _expand_home(params.get('install_dir', f'/usr/local/{name}'))
        bin_name = params.get('bin_name', name)
        bin_dirs = params.get('bin_dirs', [os.path.join(install_dir, 'bin')])
        primary_bin = os.path.join(install_dir, 'bin', bin_name)

        if dry_run:
            print(f"  [DRY-RUN] Would download {url} -> {install_dir}")
            return

        if os.path.isfile(primary_bin) and os.access(primary_bin, os.X_OK):
            print(f"{name} already installed: {install_dir}")
            _activate_path(bin_dirs)
            return

        import tempfile
        with tempfile.TemporaryDirectory() as tmpdir:
            archive_path = Path(tmpdir) / pattern
            self._download_file(url, archive_path)
            if not archive_path.exists() or archive_path.stat().st_size == 0:
                print(f"ERROR: downloaded file is empty: {url}", file=sys.stderr)
                sys.exit(1)

            extract_root = Path(tmpdir) / 'extract'
            extract_root.mkdir()
            self._extract(archive_path, str(extract_root))

            children = [p for p in extract_root.iterdir() if p.is_dir()]
            if len(children) != 1:
                print(
                    f"ERROR: expected one top-level directory in {pattern}, "
                    f"found {len(children)}",
                    file=sys.stderr,
                )
                sys.exit(1)

            _relocate_dir(children[0], install_dir)

        if not os.path.isfile(primary_bin):
            print(f"ERROR: {bin_name} not found after install: {primary_bin}", file=sys.stderr)
            sys.exit(1)

        _activate_path(bin_dirs)
        print(f"[INSTALLED] {name} {version} -> {install_dir}")


@register('archive_download')
class ArchiveDownloadStrategy(DownloadInstallStrategy):
    """Download an archive (tar.gz/zip), verify SHA256, extract to a target dir.

    Parameters (in tool configuration):

    - ``url_pattern`` (required): URL template supporting ``{version}``,
      ``{{.os}}``, ``{{.arch}}`` substitution.
    - ``install_dir``: target extraction directory (default ``/usr/local``).
    - ``version_ref``: key into ``config['tools'][name]['version_ref']``.
    - ``sha256`` (optional): expected hex digest, embedded in the strategy
      or supplied as a literal parameter.  If omitted, no checksum is
      enforced.
    - ``extract_dir`` (optional): inner directory to flatten after extract
      (``.`` or omitted = no flattening).
    - ``bin_name``: expected binary name for the post-extract sanity check.

    The orchestrator supplies *platform_str* (e.g. ``linux-x86``,
    ``macos-arm``); this class uses it to pick the OS/arch tokens for the
    URL and to decide the platform-specific file extension for binaries.
    """

    def _resolve_url(self, tool: dict, config: dict, platform_str: str) -> tuple[str, str, str, bool]:
        params = tool['parameters']
        url_pattern = params.get('url_pattern', '')
        install_dir = _expand_home(params.get('install_dir', '/usr/local'))
        version_ref = params.get('version_ref')
        sha256_expected = params.get('sha256')
        extract_dir = params.get('extract_dir', '.')
        bin_name = params.get('bin_name', 'downloaded_binary')

        version = resolve_version(config, version_ref)
        if not version:
            print(f"ERROR: no version for {tool['name']}", file=__import__('sys').stderr)
            __import__('sys').exit(1)

        os_name, arch = get_platform_from_string(platform_str)
        if os_name == 'macos':
            os_name = 'darwin'
        arch_map = {'x86': 'amd64', 'x86_64': 'amd64', 'arm': 'arm64', 'arm64': 'arm64', 'aarch64': 'arm64'}
        if arch is not None:
            arch = arch_map.get(arch, arch)

        url = url_pattern.replace('{version}', version)
        url = url.replace('{{.os}}', os_name).replace('{{.arch}}', arch)

        return (url, version, os.path.basename(url), False)

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        """Run the full download → verify → extract pipeline."""
        url, version, pattern, verify_checksum = self._resolve_url(tool, config, platform_str)
        params = tool['parameters']
        install_dir = _expand_home(params.get('install_dir', '/usr/local'))
        sha256_expected = params.get('sha256')
        extract_dir = params.get('extract_dir', '.')
        bin_name = params.get('bin_name', 'downloaded_binary')
        verify_checksum = verify_checksum or sha256_expected is not None

        # Idempotency: check for the target binary.
        server_path = os.path.join(install_dir, bin_name)
        if _is_windows(platform_str):
            server_path = os.path.join(install_dir, bin_name) if not bin_name.endswith('.exe') else bin_name
        if os.path.isfile(server_path) and os.access(server_path, os.X_OK):
            print(f"{tool['name']} already installed: {install_dir}")
            return

        if dry_run:
            print(f"[DRY-RUN] Would download {url} -> {install_dir}")
            return

        os.makedirs(install_dir, exist_ok=True)

        import tempfile
        with tempfile.TemporaryDirectory() as tmpdir:
            archive_path = Path(tmpdir) / pattern

            # Download
            print(f"[DOWNLOAD] {url} -> {archive_path}")
            self._download_file(url, archive_path)

            if not archive_path.exists() or archive_path.stat().st_size == 0:
                print(f"ERROR: downloaded file is empty: {url}", file=__import__('sys').stderr)
                __import__('sys').exit(1)

            # SHA256 verification
            if sha256_expected:
                print("[CHECKSUM] Verifying SHA256 ...")
                _verify_sha256(archive_path, sha256_expected)
                print(f"[CHECKSUM] SHA256 verified for {pattern}")
            elif verify_checksum:
                print("[CHECKSUM] Download complete (no checksum to verify)")

            # Extract
            _extract_archive(archive_path, install_dir, extract_dir, version)
            print(f"[EXTRACT] {pattern} -> {install_dir}")

            # Sanity: binary must exist.
            if not os.path.isfile(server_path):
                print(f"ERROR: binary not found after extraction: {server_path}", file=__import__('sys').stderr)
                __import__('sys').exit(1)

        print(f"[INSTALLED] {tool['name']} {version} -> {install_dir}")

    @staticmethod
    def requires_openblas() -> bool:
        return False
