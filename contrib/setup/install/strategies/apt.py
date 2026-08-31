"""Apt, brew, and winget strategies."""
import subprocess
import sys
import re
from ..base import InstallStrategy
from .. import register


def _is_versioned_package(pkg_name):
    """Check if a package name already contains a version number.
    
    Examples:
        'clang-18' → True
        'llvm-18' → True
        'gcc' → False
        'cmake' → False
        'python3' → False (the '3' is part of the name, not a version suffix)
    """
    # Match package names ending with -<digits> where digits >= 2 chars
    # This avoids matching 'python3', 'gcc-12-base', etc.
    return bool(re.search(r'-\d{2,}$', pkg_name))


def _resolve_version(tool_name, platform_str, config):
    """Resolve a platform-scoped version from config.versions.<tool_name>.
    Returns the version string or None if not found."""
    versions = config.get('versions', {})
    tool_versions = versions.get(tool_name, {})
    if not isinstance(tool_versions, dict):
        return None
    raw = tool_versions.get(platform_str)
    if raw is None:
        return None
    return str(raw)


def _log_version(tool_name, pkg_name):
    """Log the installed version of a tool after installation."""
    version_map = {
        'gcc': 'gcc',
        'clang-llvm': 'clang',
        'make': 'make',
        'cmake': 'cmake',
    }
    binary = version_map.get(tool_name)
    if not binary:
        return
    try:
        result = subprocess.run(
            [binary, '--version'],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            print(f"[VERSION] {binary}: {result.stdout.splitlines()[0].strip()}")
    except Exception:
        pass


def _find_winget_shell():
    """Return the shell command to invoke winget on Windows."""
    for ps in ('pwsh', 'powershell'):
        try:
            result = subprocess.run(
                [ps, '-NoProfile', '-Command', 'winget --version'],
                capture_output=True, timeout=10,
            )
            if result.returncode == 0:
                return ps
        except Exception:
            pass
    for ps in ('pwsh', 'powershell'):
        try:
            script = (
                'Install-Module -Name Microsoft.WinGet.Client '
                '-Repository PSGallery -Force -Scope CurrentUser -Confirm:$false;'
                'Repair-WinGetPackageManager -Latest -Force'
            )
            result = subprocess.run(
                [ps, '-NoProfile', '-Command', script],
                capture_output=True, timeout=120,
            )
            if result.returncode == 0:
                result = subprocess.run(
                    [ps, '-NoProfile', '-Command', 'winget --version'],
                    capture_output=True, timeout=10,
                )
                if result.returncode == 0:
                    return ps
        except Exception:
            pass
    return 'cmd'


def _winget_already_installed(output: str) -> bool:
    """Check if winget output means the package is already installed."""
    return 'Found an existing package already installed' in output


@register('apt')
class AptInstallStrategy(InstallStrategy):
    """Install via apt-get, with fallback to brew (macOS) / winget (Windows).
    
    Version resolution:
    - For tools with platform-scoped versions in config.versions (e.g. gcc),
      the package name is constructed as <name>-<version>.
    - Packages that already contain a version number (e.g. clang-18, llvm-18)
      are left as-is — the version is baked into the package name.
    - If the versioned package fails to install, we fall back to the unversioned
      package name.
    """

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        params = tool.get('parameters', {})
        pkg = params.get('package', '')
        packages = params.get('packages', [])
        if not isinstance(packages, list):
            packages = [pkg]
        # Single-package tools (e.g. gcc) have 'package' but no 'packages' key,
        # so packages=[] here. Fall back to the single package name.
        if not packages and pkg:
            packages = [pkg]

        if dry_run:
            for p in packages:
                print(f"  [DRY-RUN] Would install {p}")
            return

        def _try_install(pkg_name):
            print(f"[INSTALL] Installing {pkg_name}...")
            result = subprocess.run([
                'sudo', '-n', 'apt-get', 'install', '-y', '--no-install-recommends', pkg_name
            ], capture_output=True, text=True)
            return result

        tool_name = tool.get('name', '')

        if "linux" in platform_str:
            from config import _apt_update
            _apt_update()
            for pkg_name in packages:
                # Determine final package name with version if applicable
                if _is_versioned_package(pkg_name):
                    # Already versioned (e.g. clang-18, llvm-18) — use as-is
                    final_pkg = pkg_name
                else:
                    # Check for platform-scoped version (e.g. gcc: linux-x86=12, linux-arm=14)
                    versioned_pkg = _resolve_version(tool_name, platform_str, config)
                    if versioned_pkg:
                        final_pkg = f"{pkg_name}-{versioned_pkg}"
                    else:
                        final_pkg = pkg_name

                result = _try_install(final_pkg)
                if result.returncode != 0:
                    # Fallback: if versioned install fails, try without version
                    if final_pkg != pkg_name:
                        print(f"  [WARN] {final_pkg} not available, trying {pkg_name}",
                              file=sys.stderr)
                        result = _try_install(pkg_name)
                        if result.returncode != 0:
                            print(f"ERROR: apt install failed for {pkg_name}",
                                  file=sys.stderr)
                            sys.exit(1)
                    else:
                        print(f"ERROR: apt install failed for {pkg_name}",
                              file=sys.stderr)
                        sys.exit(1)
                _log_version(tool_name, final_pkg)
            return

        if "macos" in platform_str:
            # On macOS, `make` installs BSD make; we need `gmake` (GNU Make)
            # which Firedancer's GNUmakefile requires.
            resolved_packages = []
            for pkg_name in packages:
                # macOS: `make` → install `gmake` instead
                if pkg_name == 'make':
                    resolved_packages.append('gmake')
                else:
                    resolved_packages.append(pkg_name)

            for pkg_name in resolved_packages:
                print(f"[BREW] Installing {pkg_name}...")
                result = subprocess.run(
                    ['brew', 'install', '--formula', pkg_name],
                    capture_output=True, text=True
                )
                if result.returncode != 0:
                    print(f"ERROR: brew install failed for {pkg_name}",
                          file=sys.stderr)
                    sys.exit(1)
            _log_version(tool_name, resolved_packages[-1] if resolved_packages else '')
            return

        if "windows" in platform_str:
            shell = _find_winget_shell()
            for pkg_name in packages:
                winget_id = params.get('winget_id', pkg_name)
                print(f"[WINGET] Installing {winget_id}...")
                if shell in ('pwsh', 'powershell'):
                    winget_cmd = (
                        f'winget install --exact --id {winget_id} '
                        '--accept-package-agreements '
                        '--accept-source-agreements '
                        '--source winget'
                    )
                    cmd = [shell, '-NoProfile', '-Command', winget_cmd]
                else:
                    cmd = [
                        shell, '/c', 'winget', 'install', '--exact', '--id', winget_id,
                        '--accept-package-agreements', '--accept-source-agreements',
                        '--source', 'winget'
                    ]
                result = subprocess.run(cmd, capture_output=True, text=True)
                if result.returncode != 0:
                    print(f"ERROR: winget install failed for {winget_id}",
                          file=sys.stderr)
                    sys.exit(1)
            return

        print(f"ERROR: unknown platform '{platform_str}' for apt install",
              file=sys.stderr)
        sys.exit(1)


@register('brew')
class BrewInstallStrategy(InstallStrategy):
    """Install via brew."""

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        pkg = tool['parameters'].get('package', '')
        if dry_run:
            print(f"  [DRY-RUN] Would brew install {pkg}")
            return
        print(f"[BREW] Installing {pkg}...")
        result = subprocess.run(['brew', 'install', pkg], capture_output=True, text=True)
        if result.returncode != 0:
            print(f"ERROR: brew install failed for {pkg}", file=sys.stderr)
            sys.exit(1)


@register('winget')
class WingetInstallStrategy(InstallStrategy):
    """Install via winget."""

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        pkg = tool['parameters'].get('package', '')
        if dry_run:
            print(f"  [DRY-RUN] Would winget install {pkg}")
            return
        print(f"[WINGET] Installing {pkg}...")
        shell = _find_winget_shell()
        if shell in ('pwsh', 'powershell'):
            winget_cmd = (
                f'winget install --exact --id {pkg} '
                '--accept-package-agreements '
                '--accept-source-agreements '
                '--source winget'
            )
            cmd = [shell, '-NoProfile', '-Command', winget_cmd]
        else:
            cmd = [
                shell, '/c', 'winget', 'install', '--exact', '--id', pkg,
                '--accept-package-agreements', '--accept-source-agreements',
                '--source', 'winget'
            ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            if result.stdout and _winget_already_installed(result.stdout):
                print(f"  {pkg} already installed, skipping")
                return
            print(f"ERROR: winget install failed for {pkg}", file=sys.stderr)
            sys.exit(1)
