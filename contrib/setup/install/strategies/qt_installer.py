"""Qt Online Installer strategy — downloads the per-platform installer binary,
renames to canonical name, invokes CLI to install Qt modules.

All version data (installer version, Qt library version, asset names,
SHA-256 hashes, base URL) is driven from ``tool-versions.json`` under
``versions.qt-installer``.  No version numbers are hardcoded in code.

Installer binaries are downloaded with their vendor-specific names
(e.g. ``qt-online-installer-linux-x64-{version}.run``) then renamed to
a canonical form (``qt-installer.run``/``.dmg``/``.exe``) so the
invocation command is always the same regardless of vendor naming
conventions.
"""
import os
import sys
import shutil
import tempfile
from pathlib import Path
from ..base import InstallStrategy, _download_file, _run_cmd
from .. import register
from .download import _expand_home, _is_windows as _is_platform_windows, _verify_sha256, resolve_version_from_config


# ── Platform → installer binary canonical name & flags ────────────────────────

_CANONICAL = {
    'linux-x86': ('qt-installer.run', '--accept-licenses --default-answer --confirm-command install'),
    'linux-arm': ('qt-installer.run', '--accept-licenses --default-answer --confirm-command install'),
    'macos-x86': ('qt-installer.dmg', '--accept-licenses --default-answer --confirm-command install'),
    'macos-arm': ('qt-installer.dmg', '--accept-licenses --default-answer --confirm-command install'),
    'windows-x86': ('qt-installer.exe', '/S /accept-licenses --confirm-command install'),
    'windows-arm': ('qt-installer.exe', '/S /accept-licenses --confirm-command install'),
}


# ── Version helpers ───────────────────────────────────────────────────────────

def _is_qt_installed(install_dir: str, qt_version: str, qt_sub_dir: str) -> bool:
    """Check if the expected Qt binaries are present in the install directory."""
    check_paths = [
        os.path.join(install_dir, qt_version, qt_sub_dir, 'bin', 'qmake'),
        os.path.join(install_dir, qt_version, qt_sub_dir, 'bin', 'qmake.exe'),
    ]
    for p in check_paths:
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return True
    return False


# ── Strategy ──────────────────────────────────────────────────────────────────

@register('qt_installer')
class QtInstallerStrategy(InstallStrategy):
    """Install Qt via the Qt Online Installer CLI."""

    @staticmethod
    def _resolve_from_config(platform_str: str, config: dict) -> dict:
        """Read artifact metadata from tool-versions.json."""
        qt_entry = config.get('versions', {}).get('qt-installer', {})
        if isinstance(qt_entry, str):
            # Legacy: bare string version — no artifact metadata
            print(
                f"ERROR: qt-installer entry in tool-versions.json must be an "
                f"object with options, got: {qt_entry}",
                file=sys.stderr,
            )
            sys.exit(1)

        options = qt_entry.get('options', {})
        qt_module = options.get('qt_module', {}).get(platform_str)
        asset_name = options.get('asset_name', {}).get(platform_str)
        sha256 = options.get('sha256', {}).get(platform_str)
        base_url = options.get('base_url', '')

        if qt_module is None:
            print(
                f"ERROR: no qt_module defined for platform '{platform_str}' in "
                f"tool-versions.json.qt-installer.options.qt_module",
                file=sys.stderr,
            )
            sys.exit(1)
        if asset_name is None:
            print(
                f"ERROR: no asset_name defined for platform '{platform_str}' in "
                f"tool-versions.json.qt-installer.options.asset_name",
                file=sys.stderr,
            )
            sys.exit(1)

        return {
            'qt_module': qt_module,
            'asset_name': asset_name,
            'sha256': sha256,
            'base_url': base_url,
        }

    @staticmethod
    def _extract_qt_subdir(qt_module: str) -> str:
        """Extract the directory component from a Qt module ID like
        ``qt.qt6.6112.linux_gcc_64`` → ``linux_gcc_64``."""
        return qt_module.split('.')[-1]

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        params = tool.get('parameters', {})

        # ── Resolve version from tool-versions.json ───────────────────────
        version = resolve_version_from_config(config, 'qt-installer')
        if not version:
            print("ERROR: no qt-installer version in tool-versions.json", file=sys.stderr)
            sys.exit(1)

        # ── Resolve platform-specific metadata from tool-versions.json ────
        resolved = self._resolve_from_config(platform_str, config)
        qt_module = resolved['qt_module']
        asset_name = resolved['asset_name']
        sha256_expected = resolved['sha256']
        base_url = resolved['base_url']

        # Substitute {version} into asset_name (e.g. "qt-...-{version}.run")
        asset_name = asset_name.replace('{version}', version)

        canonical_name, flags = _CANONICAL.get(platform_str)
        if canonical_name is None:
            print(f"ERROR: no canonical installer name for platform '{platform_str}'", file=sys.stderr)
            sys.exit(1)

        # Qt sub-directory (e.g. linux_gcc_64, macOS_clang_64)
        qt_sub_dir = self._extract_qt_subdir(qt_module)

        # Build download URL
        download_url = f'{base_url}/{asset_name}'

        install_dir = _expand_home(params.get('install_dir', '~/Qt'))

        # ── Idempotency check ─────────────────────────────────────────────
        if _is_qt_installed(install_dir, version, qt_sub_dir):
            print(f'Qt already installed in {install_dir}')
            return

        if dry_run:
            print(f'[DRY-RUN] Would install Qt {version} (module={qt_module}) -> {install_dir}')
            return

        print(f'[INSTALL] Qt {version} (module={qt_module}) via {asset_name}')
        print(f'  Install dir: {install_dir}')

        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir = Path(tmpdir)

            # 1. Download with vendor-specific name
            downloaded = tmpdir / asset_name
            print(f'[DOWNLOAD] {download_url} -> {downloaded}')
            _download_file(download_url, downloaded, dry_run=False)

            if not downloaded.exists() or downloaded.stat().st_size == 0:
                print(f'ERROR: downloaded file is empty: {download_url}', file=sys.stderr)
                sys.exit(1)

            # 2. Verify SHA256
            if sha256_expected:
                print('[CHECKSUM] Verifying SHA256 ...')
                _verify_sha256(downloaded, sha256_expected)
                print(f'[CHECKSUM] SHA256 verified for {asset_name}')

            # 3. Rename to canonical name
            canonical = tmpdir / canonical_name
            shutil.move(str(downloaded), str(canonical))

            # 4. Make executable (for .run files)
            if not _is_platform_windows(platform_str):
                os.chmod(canonical, 0o755)

            # 5. Run the installer
            install_cmd = [str(canonical), f'--root {install_dir}', flags, qt_module]
            print(f'[INSTALLER] {" ".join(install_cmd)}')
            result = _run_cmd(install_cmd, capture=True)
            if result.returncode != 0:
                print(f'ERROR: Qt installer exited with code {result.returncode}', file=sys.stderr)
                if result.stderr:
                    print(f'[installer stderr] {result.stderr}', file=sys.stderr)
                sys.exit(1)

        print(f'[INSTALLED] Qt {version} -> {install_dir}')
