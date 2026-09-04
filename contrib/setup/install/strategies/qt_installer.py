"""Qt Online Installer strategy — downloads the per-platform installer binary,
installs system dependencies (Linux/macOS), and invokes CLI to install Qt modules.

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


def _extract_qt_version(qt_module: str) -> str:
    """Extract the Qt library version from a module ID.

    ``qt.qt6.6112.linux_gcc_64`` → ``6.11.2``.
    The format is qt.qtN.NNNN.subdir where NNNN encodes X.Y.Z.
    """
    # Extract the 4-digit version segment (e.g. 6112 from qt.qt6.6112.linux_gcc_64)
    parts = qt_module.split('.')
    # parts[1] is 'qt6', parts[2] is '6112'
    version_digits = parts[2]
    major = version_digits[0]
    minor = version_digits[1:3]
    patch = version_digits[3]
    return f'{major}.{minor}.{patch}'


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
        ``qt.qt6.6112.linux_gcc_64`` → ``gcc_64``.

        The module ID has a platform prefix (linux_, macOS_, win64_, etc.)
        that is NOT part of the actual directory name.
        """
        suffix = qt_module.split('.')[-1]
        # Strip common platform prefixes that the Qt installer prepends
        for prefix in ('linux_', 'macOS_', 'win64_', 'win32_'):
            if suffix.startswith(prefix):
                return suffix[len(prefix):]
        return suffix

    @staticmethod
    def _install_system_dependencies(platform_str: str) -> None:
        """Verify system dependencies required by Qt6 on the host OS.

        System packages are installed by the orchestrator via the
        ``graphics-libs`` category before this strategy runs.  This method
        only prints a diagnostic and exits with code 1 if the packages are
        genuinely missing (e.g. the user skipped the setup step).

        On macOS and Windows no extra dependencies are needed.
        """
        if _is_platform_windows(platform_str):
            return

        # macOS: no extra dependencies needed for Qt6Quick
        if platform_str.startswith('macos'):
            print('[DEPS] macOS Qt6 has no extra system dependencies')
            return

        # Linux: verify graphics-libs were installed by the orchestrator
        if platform_str.startswith('linux'):
            packages = [
                'libgl1-mesa-dev',   # OpenGL
                'libx11-dev',        # X11
                'libxext-dev',       # X11 extensions
                'libxcb1-dev',       # XCB
            ]

            missing = []
            for pkg in packages:
                result = _run_cmd(['dpkg', '-s', pkg], capture=True)
                if result.returncode != 0:
                    missing.append(pkg)

            if missing:
                print(
                    f'ERROR: Qt6 requires graphics-libs category. '
                    f'Missing packages: {", ".join(missing)}',
                    file=sys.stderr,
                )
                print(
                    'Run `just setup-linux-x86-qt` (or the appropriate '
                    'setup-<platform> command) to install system dependencies.',
                    file=sys.stderr,
                )
                sys.exit(1)

            print('[DEPS] All Qt6 system dependencies present')

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

        # ── Install system dependencies (Linux/macOS) ─────────────────────
        # Always run — idempotent, only installs missing packages.
        self._install_system_dependencies(platform_str)

        # ── Idempotency check ─────────────────────────────────────────────
        # Extract the Qt library version from the module ID for directory lookup.
        # Module: qt.qt6.6112.linux_gcc_64 → Qt version: 6.11.2
        qt_lib_version = _extract_qt_version(qt_module)
        if _is_qt_installed(install_dir, qt_lib_version, qt_sub_dir):
            print(f'Qt {qt_lib_version} already installed in {install_dir}')
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

            # ── Build install command with unattended flags ───────────────────
            # Credentials: QT_USERNAME + QT_PASSWORD env vars (CI/local).
            # --pw expects the Qt Online Installer password, not an API token.
            # Qt CLI syntax: installer --root DIR --accept-licenses ... install --email user --pw pass MODULE
            qt_username = os.environ.get('QT_USERNAME', '')
            qt_password = os.environ.get('QT_PASSWORD', '')

            parts = [
                str(canonical),
                f'--root {install_dir}',
            ]

            # Global flags (must come before subcommand)
            parts.extend(['--accept-licenses', '--accept-obligations', '--default-answer', '--confirm-command'])

            # Subcommand
            parts.append('install')

            # Credential flags: only valid in CLI (headless) mode
            if qt_username and qt_password:
                parts.extend(['--email', qt_username, '--pw', qt_password])

            parts.append(qt_module)

            install_cmd = parts
            install_str = " ".join(install_cmd)
            print(f'[INSTALLER] {install_str}')

            # Force CLI/headless mode on platforms with display servers (local dev).
            # CI runners have no display, so this is harmless there too.
            run_env = os.environ.copy()
            if not _is_platform_windows(platform_str):
                run_env.pop('DISPLAY', None)
                run_env.pop('WAYLAND_DISPLAY', None)

            result = _run_cmd(install_cmd, capture=True, env=run_env)
            if result.returncode != 0:
                print(f'ERROR: Qt installer exited with code {result.returncode}', file=sys.stderr)
                if result.stderr:
                    print(f'[installer stderr] {result.stderr}', file=sys.stderr)
                sys.exit(1)

        print(f'[INSTALLED] Qt {version} -> {install_dir}')
