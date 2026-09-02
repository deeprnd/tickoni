"""llama.cpp download strategy — pre-built binary download with SHA256 verification.

Replaces: llama_cpp_build.py (clone + cmake + build)

This strategy reads artifact metadata from build-config.json and delegates
download, SHA256 verification, and archive extraction to the shared helpers
in .download.
"""
import os
import sys
import json
from pathlib import Path
from ..base import InstallStrategy
from .. import register
from .download import _download_and_verify, _extract_archive, _expand_home, _is_windows
from config import resolve_version


@register('llama_cpp_download')
class LlamaCppDownloadStrategy(InstallStrategy):
    """Download pre-built llama.cpp binaries with SHA256 verification."""

    @staticmethod
    def _resolve_from_config(platform_str: str) -> dict:
        """Read artifact URL and server binary from build-config.json.

        Note: version is no longer embedded here. The caller (execute)
        resolves it from tool-versions.json via resolve_version.
        """
        config_path = Path(__file__).parent.parent.parent.parent / 'build' / 'build-config.json'
        with open(config_path) as f:
            build_config = json.load(f)

        llama_config = build_config.get('llama_cpp', {})
        artifacts = llama_config.get('artifacts', {})

        # Map platform to artifact key
        artifact = None
        for key, val in artifacts.items():
            if key == platform_str:
                artifact = val
                break
        if artifact is None:
            parts = platform_str.split('-', 1)
            if len(parts) == 2:
                candidate = f"{parts[0]}-{parts[1]}"
                if candidate in artifacts:
                    artifact = artifacts[candidate]

        if artifact is None:
            print(f"ERROR: no llama.cpp artifact for platform {platform_str}", file=sys.stderr)
            sys.exit(1)

        extract_dir = artifact.get('extract_dir', '.')
        server_bin = artifact.get('server_bin', 'llama-server' + ('.exe' if _is_windows(platform_str) else ''))

        return {
            'artifact': artifact,
            'extract_dir': extract_dir,
            'server_bin': server_bin,
        }

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        resolved = self._resolve_from_config(platform_str)
        params = tool.get('parameters', {})

        # Version from tool-versions.json via resolve_version
        version = resolve_version(config, 'llama-cpp')
        if not version:
            print("ERROR: no llama-cpp version in tool-versions.json", file=sys.stderr)
            sys.exit(1)

        # Build URL from build-config, substituting version
        artifact = resolved['artifact']
        llama_config = json.load(
            open(Path(__file__).parent.parent.parent.parent / 'build' / 'build-config.json')
        )['llama_cpp']
        base_url = llama_config.get('base_url', '').replace('{version}', version)
        filename = artifact['filename'].replace('{version}', version)
        url = f"{base_url}/{filename}"
        sha256 = artifact.get('sha256')

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
