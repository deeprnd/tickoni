"""llama.cpp download strategy — pre-built binary download with SHA256 verification.

Replaces: llama_cpp_build.py (clone + cmake + build)

This strategy reads artifact metadata from build-config.json and delegates
download, SHA256 verification, and archive extraction to the shared helpers
in .download.
"""
import os
import sys
from pathlib import Path
from ..base import InstallStrategy, _download_file
from .. import register
from .download import _expand_home, _is_windows, _verify_sha256, _extract_archive


@register('llama_cpp_download')
class LlamaCppDownloadStrategy(InstallStrategy):
    """Download pre-built llama.cpp binaries with SHA256 verification."""

    @staticmethod
    def _resolve_from_config(platform_str: str) -> dict:
        """Read artifact URL, SHA256, and server binary from build-config.json."""
        config_path = Path(__file__).parent.parent.parent.parent / 'build' / 'build-config.json'
        with open(config_path) as f:
            build_config = __import__('json').load(f)

        llama_config = build_config.get('llama_cpp', {})
        artifacts = llama_config.get('artifacts', {})
        version = llama_config.get('version', 'b10760')
        base_url = llama_config.get('base_url', '').replace('{version}', version)

        # Map platform to artifact key
        artifact = None
        if platform_str in artifacts:
            artifact = artifacts[platform_str]
        else:
            parts = platform_str.split('-', 1)
            if len(parts) == 2:
                candidate = f"{parts[0]}-{parts[1]}"
                if candidate in artifacts:
                    artifact = artifacts[candidate]
                else:
                    print(f"ERROR: no llama.cpp artifact for platform {platform_str}", file=sys.stderr)
                    sys.exit(1)
            else:
                print(f"ERROR: no llama.cpp artifact for platform {platform_str}", file=sys.stderr)
                sys.exit(1)

        filename = artifact['filename'].replace('{version}', version)
        url = f"{base_url}/{filename}"
        sha256 = artifact.get('sha256')
        extract_dir = artifact.get('extract_dir', '.')
        server_bin = artifact.get('server_bin', 'llama-server' + ('.exe' if _is_windows(platform_str) else ''))

        return {
            'url': url,
            'version': version,
            'sha256': sha256,
            'extract_dir': extract_dir,
            'server_bin': server_bin,
        }

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        artifact = self._resolve_from_config(platform_str)
        params = tool.get('parameters', {})

        # Direct URL override (for testing or custom builds)
        if params.get('download_url'):
            artifact['url'] = params['download_url']
            artifact['sha256'] = params.get('sha256', artifact['sha256'])

        install_dir = _expand_home(params.get('install_dir', '~/work/models/llama.cpp'))
        server_path = os.path.join(install_dir, artifact['server_bin'])

        # Idempotency check
        if os.path.isfile(server_path) and os.access(server_path, os.X_OK):
            print(f"llama.cpp already installed: {install_dir}")
            return

        if dry_run:
            print(f"[DRY-RUN] Would download {artifact['url']} -> {install_dir}")
            return

        os.makedirs(install_dir, exist_ok=True)

        import tempfile
        with tempfile.TemporaryDirectory() as tmpdir:
            archive_path = Path(tmpdir) / os.path.basename(artifact['url'])

            # Download
            print(f"[DOWNLOAD] {artifact['url']} -> {archive_path}")
            _download_file(artifact['url'], archive_path, dry_run=False)

            if not archive_path.exists() or archive_path.stat().st_size == 0:
                print(f"ERROR: downloaded file is empty: {artifact['url']}", file=sys.stderr)
                sys.exit(1)

            # SHA256 verification
            if artifact['sha256']:
                _verify_sha256(archive_path, artifact['sha256'])
                print(f"[CHECKSUM] SHA256 verified for {os.path.basename(artifact['url'])}")

            # Extract
            _extract_archive(archive_path, install_dir, artifact['extract_dir'], artifact['version'])
            print(f"[EXTRACT] archive -> {install_dir}")

            # Verify binary
            if not os.path.isfile(server_path):
                print(f"ERROR: server binary not found after extraction: {server_path}", file=sys.stderr)
                sys.exit(1)

        print(f"[INSTALLED] llama.cpp {artifact['version']} -> {install_dir}")

    @staticmethod
    def requires_openblas() -> bool:
        """The pre-built llama.cpp binaries depend on system OpenBLAS."""
        return True
