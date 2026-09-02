"""Llama.cpp download strategy — pre-built binary download with SHA256 verification.

Replaces: llama_cpp_build.py (clone + cmake + build)

This strategy:
1. Reads the artifact URL from build-config.json based on platform
2. Downloads the archive to a temp directory
3. Verifies SHA256 checksum
4. Extracts the archive to the install directory
5. Verifies the server binary exists

OpenBLAS remains a system dependency — this strategy does NOT install it.
The install orchestrator's dependency graph handles OpenBLAS separately.
"""
import hashlib
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path
from ..base import InstallStrategy
from .. import register


def _expand_home(path: str) -> str:
    """Expand ~ to HOME."""
    if path == '~':
        path = os.environ.get('HOME', os.path.expanduser('~'))
    elif path.startswith('~/'):
        path = os.path.join(os.environ.get('HOME', os.path.expanduser('~')), path[2:])
    return path


def _is_windows():
    """Detect Windows."""
    return sys.platform in ('win32', 'cygwin')


def _resolve_url_and_platform(tool: dict, config: dict, platform_str: str) -> tuple:
    """Resolve the download URL, version, and platform mapping.

    Resolution order:
    1. Explicit URL from tool parameters (for testing/fallback)
    2. build-config.json llama_cpp artifacts section
    3. Fallback: construct URL from base_url + artifact pattern
    """
    params = tool.get('parameters', {})

    # Direct URL override (for testing or custom builds)
    if params.get('download_url'):
        return (params['download_url'], None, None, params.get('sha256'))

    # Read from build-config.json
    build_config_path = Path(__file__).parent.parent.parent.parent / 'build' / 'build-config.json'
    with open(build_config_path) as f:
        build_config = __import__('json').load(f)

    llama_config = build_config.get('llama_cpp', {})
    artifacts = llama_config.get('artifacts', {})

    # Map platform_str to artifact key
    if platform_str in artifacts:
        artifact = artifacts[platform_str]
    else:
        # Try to find a matching artifact by platform mapping
        # linux -> linux-x86 or linux-arm
        # macos -> macos-x86 or macos-arm
        # windows -> windows-x86 or windows-arm
        parts = platform_str.split('-', 1)
        if len(parts) == 2:
            os_part, arch_part = parts
            candidate = f"{os_part}-{arch_part}"
            if candidate in artifacts:
                artifact = artifacts[candidate]
            else:
                print(f"ERROR: no llama.cpp artifact for platform {platform_str}", file=sys.stderr)
                sys.exit(1)
        else:
            print(f"ERROR: no llama.cpp artifact for platform {platform_str}", file=sys.stderr)
            sys.exit(1)

    version = llama_config.get('version', 'b10760')
    base_url = llama_config.get('base_url', '')
    filename = artifact['filename'].replace('{version}', version)
    url = f"{base_url}/{filename}"

    sha256_expected = artifact.get('sha256')

    return (url, version, artifact, sha256_expected)


@register('llama_cpp_download')
class LlamaCppDownloadStrategy(InstallStrategy):
    """Download pre-built llama.cpp binaries with SHA256 verification."""

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        url, version, artifact, sha256_expected = _resolve_url_and_platform(tool, config, platform_str)
        install_dir = _expand_home(tool['parameters'].get('install_dir', '~/work/models/llama.cpp'))
        server_bin = artifact.get('server_bin', 'llama-server' + ('.exe' if _is_windows() else ''))

        # Idempotency check: is the server binary already present?
        server_path = os.path.join(install_dir, server_bin)
        if os.path.isfile(server_path) and os.access(server_path, os.X_OK):
            print(f"llama.cpp already installed: {install_dir}")
            return

        if dry_run:
            print(f"[DRY-RUN] Would download {url} -> {install_dir}")
            return

        # Ensure install directory exists
        os.makedirs(install_dir, exist_ok=True)

        with tempfile.TemporaryDirectory() as tmpdir:
            archive_path = os.path.join(tmpdir, os.path.basename(url))

            # Download
            print(f"[DOWNLOAD] {url} -> {archive_path}")
            result = subprocess.run(
                ['curl', '-sSfL', '--retry', '3', '-o', archive_path, url],
                capture_output=True, text=True
            )
            if result.returncode != 0:
                print(f"ERROR: download failed for {url}", file=sys.stderr)
                if result.stderr:
                    print(result.stderr, file=sys.stderr)
                sys.exit(1)

            # Verify file is non-empty
            if os.path.getsize(archive_path) == 0:
                print(f"ERROR: downloaded file is empty: {url}", file=sys.stderr)
                sys.exit(1)

            # SHA256 verification
            if sha256_expected:
                actual = hashlib.sha256(open(archive_path, 'rb').read()).hexdigest()
                if actual != sha256_expected:
                    print(f"ERROR: SHA256 mismatch for {os.path.basename(url)}", file=sys.stderr)
                    print(f"  expected: {sha256_expected}", file=sys.stderr)
                    print(f"  actual:   {actual}", file=sys.stderr)
                    sys.exit(1)
                print(f"[CHECKSUM] SHA256 verified for {os.path.basename(url)}")

            # Extract
            extract_dir = artifact.get('extract_dir', '.')
            name = os.path.basename(url)
            if name.endswith('.tar.gz') or name.endswith('.tgz'):
                with tarfile.open(archive_path) as tf:
                    tf.extractall(install_dir)
                print(f"[EXTRACT] tar.gz -> {install_dir} (inner: {extract_dir})")
            elif name.endswith('.zip'):
                with zipfile.ZipFile(archive_path) as zf:
                    zf.extractall(install_dir)
                print(f"[EXTRACT] zip -> {install_dir}")
            else:
                print(f"ERROR: unsupported archive format: {name}", file=sys.stderr)
                sys.exit(1)

            # Verify binary
            if not os.path.isfile(server_path):
                print(f"ERROR: server binary not found after extraction: {server_path}", file=sys.stderr)
                sys.exit(1)

        print(f"[INSTALLED] llama.cpp {version} -> {install_dir}")

    @staticmethod
    def requires_openblas() -> bool:
        """The pre-built llama.cpp binaries depend on system OpenBLAS."""
        return True
