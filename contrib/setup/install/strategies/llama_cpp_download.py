"""llama.cpp download strategy — pre-built binary download with SHA256 verification.

Replaces: llama_cpp_build.py (clone + cmake + build)

This strategy reads artifact metadata from tool-versions.json and delegates
download, SHA256 verification, and archive extraction to the shared helpers
in .download.
"""
import json
import os
import sys
from pathlib import Path
from ..base import InstallStrategy
from .. import register
from .download import _download_and_verify, _extract_archive, _expand_home, _is_windows
from config import resolve_version


@register('llama_cpp_download')
class LlamaCppDownloadStrategy(InstallStrategy):
    """Download pre-built llama.cpp binaries with SHA256 verification."""

    @staticmethod
    def _resolve_from_config(platform_str: str, config: dict) -> dict:
        """Read artifact metadata from tool-versions.json."""
        llama_entry = config.get('versions', {}).get('llama-cpp', {})
        if isinstance(llama_entry, str):
            # Legacy: bare string version — no artifact metadata available
            sha256 = None
            filename = None
            extract_dir = '.'
            server_bin = 'llama-server'
            base_url = ''
        else:
            options = llama_entry.get('options', {})
            sha256 = options.get('sha256', {}).get(platform_str)
            filename = options.get('filename', {}).get(platform_str)
            extract_dir = options.get('extract_dir', {}).get(platform_str, '.')
            server_bin = options.get('server_bin', {}).get(platform_str, 'llama-server')
            base_url = options.get('base_url', '')

        if filename is None:
            print(f"ERROR: no llama.cpp filename for platform {platform_str}", file=sys.stderr)
            sys.exit(1)

        return {
            'sha256': sha256,
            'filename': filename,
            'extract_dir': extract_dir,
            'server_bin': server_bin,
            'base_url': base_url,
        }

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        resolved = self._resolve_from_config(platform_str, config)
        params = tool.get('parameters', {})

        # Version from tool-versions.json via resolve_version
        version = resolve_version(config, 'llama-cpp')
        if not version:
            print("ERROR: no llama-cpp version in tool-versions.json", file=sys.stderr)
            sys.exit(1)

        # Build URL from tool-versions.json base_url
        base_url = resolved['base_url'].replace('{version}', version)
        filename = resolved['filename'].replace('{version}', version)
        url = f"{base_url}/{filename}"
        sha256 = resolved['sha256']

        # Direct URL override (for testing or custom builds)
        if params.get('download_url'):
            url = params['download_url']
            sha256 = params.get('sha256', sha256)

        install_dir = _expand_home(params.get('install_dir', '~/work/models/llama.cpp'))
        server_path = os.path.join(install_dir, resolved['server_bin'])

        # Idempotency check
        if os.path.isfile(server_path) and os.access(server_path, os.X_OK):
            print(f"llama.cpp already installed: {install_dir}")
            return

        if dry_run:
            print(f"[DRY-RUN] Would download {url} -> {install_dir}")
            return

        os.makedirs(install_dir, exist_ok=True)

        import tempfile
        with tempfile.TemporaryDirectory() as tmpdir:
            archive_path = Path(tmpdir) / filename

            # Download + verify (shared pipeline)
            _download_and_verify(
                url=url,
                archive_path=archive_path,
                expected_sha256=sha256,
                sig_url=None,  # llama.cpp releases don't use minisign
                sig_path=None,
                pubkey=None,
            )

            # Extract
            _extract_archive(archive_path, install_dir, resolved['extract_dir'], version)
            print(f"[EXTRACT] archive -> {install_dir}")

            # Verify binary
            if not os.path.isfile(server_path):
                print(f"ERROR: server binary not found after extraction: {server_path}", file=sys.stderr)
                sys.exit(1)

        print(f"[INSTALLED] llama.cpp {version} -> {install_dir}")

    @staticmethod
    def requires_openblas() -> bool:
        """The pre-built llama.cpp binaries depend on system OpenBLAS."""
        return True
