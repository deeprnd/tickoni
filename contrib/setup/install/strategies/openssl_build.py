"""OpenSSL build strategy — download release tarball, verify SHA256, extract, then run install-openssl.sh.

Reads artifact metadata from tool-versions.json (same pattern as llama.cpp)
and delegates build to the existing install-openssl.sh helper script.
"""
import json
import os
import subprocess
import sys
from pathlib import Path
from ..base import InstallStrategy
from .. import register
from .download import _download_and_verify, _extract_archive, _expand_home
from config import resolve_version, env_flag
from shell import bash_command


@register('openssl_build')
class OpenSSLBuildStrategy(InstallStrategy):
    """Download OpenSSL release tarball with SHA256 verification, extract, then build."""

    @staticmethod
    def _resolve_from_config(platform_str: str, config: dict) -> dict:
        """Read artifact metadata from tool-versions.json."""
        openssl_entry = config.get('versions', {}).get('openssl', {})
        if isinstance(openssl_entry, str):
            # Legacy: bare string version — no artifact metadata
            sha256 = None
            filename = None
            extract_dir = '.'
            base_url = ''
        else:
            options = openssl_entry.get('options', {})
            sha256 = options.get('sha256')
            filename = options.get('filename')
            extract_dir = options.get('extract_dir', '.')
            base_url = options.get('base_url', '')

        if filename is None:
            print(f"ERROR: no OpenSSL filename in tool-versions.json", file=sys.stderr)
            sys.exit(1)

        return {
            'sha256': sha256,
            'filename': filename,
            'extract_dir': extract_dir,
            'base_url': base_url,
        }

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        resolved = self._resolve_from_config(platform_str, config)
        params = tool.get('parameters', {})

        # Version from tool-versions.json
        version = resolve_version(config, 'openssl')
        if not version:
            print("ERROR: no openssl version in tool-versions.json", file=sys.stderr)
            sys.exit(1)

        # Build URL from tool-versions.json base_url
        base_url = resolved['base_url']
        filename = resolved['filename']
        url = f"{base_url}/{filename}"
        sha256 = resolved['sha256']

        install_dir = _expand_home(params.get('install_dir', './build/opt'))
        install_path = Path(install_dir)

        # Idempotency check (respect SKIP_IDEMPOTENCY env var)
        skip = env_flag('SKIP_IDEMPOTENCY')
        if not skip and install_path.joinpath('lib', 'libssl.a').exists():
            print(f"OpenSSL already installed: {install_dir}")
            return

        if dry_run:
            print(f"[DRY-RUN] Would download {url}, extract {resolved['extract_dir']}, build")
            return

        os.makedirs(install_dir, exist_ok=True)

        import tempfile
        with tempfile.TemporaryDirectory() as tmpdir:
            archive_path = Path(tmpdir) / filename

            # Download + verify SHA256 only (OpenSSL uses GPG ASC, not minisign)
            _download_and_verify(
                url=url,
                archive_path=archive_path,
                expected_sha256=sha256,
            )

            # Extract into install_dir/git — the script expects ${PREFIX}/git/openssl
            git_dir = os.path.join(install_dir, 'git')
            os.makedirs(git_dir, exist_ok=True)
            # Use extract_dir='.' to skip flattening, preserving the versioned root dir
            _extract_archive(archive_path, git_dir, '.', version)
            # Now we have git/openssl-3.6.4/ — rename to git/openssl/ (matching script's src_dir)
            renamed = Path(git_dir) / 'openssl'
            if renamed.exists():
                import shutil
                shutil.rmtree(str(renamed))
            extracted = Path(git_dir) / resolved['extract_dir']
            extracted.rename(renamed)
            print(f"[EXTRACT] {filename} -> {install_dir}/git/openssl")

        # Run install-openssl.sh for the build step
        # The script expects PREFIX set to install_dir and src_dir to point to the extracted source
        script = params.get('script', 'install-openssl.sh')
        script_path = os.path.join(
            os.path.dirname(os.path.abspath(__file__)),
            '..', '..', 'helpers', script,
        )
        script_path = os.path.normpath(script_path)

        if not os.path.isfile(script_path):
            print(f"ERROR: helper script not found: {script_path}", file=sys.stderr)
            sys.exit(1)

        print(f"[BUILD] Running {script}...")
        env = os.environ.copy()
        env['TK_PLATFORM'] = platform_str

        result = subprocess.run([bash_command(), script_path], env=env, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"ERROR: {script} failed (exit {result.returncode})", file=sys.stderr)
            print(result.stdout[-3000:] if result.stdout else "(no stdout)")
            print(result.stderr[-3000:] if result.stderr else "(no stderr)", file=sys.stderr)
            sys.exit(1)

        print(f"[INSTALLED] OpenSSL {version} -> {install_dir}")
