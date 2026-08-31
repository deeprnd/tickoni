"""Apt, brew, and winget strategies."""
import subprocess
import sys
from ..base import InstallStrategy
from .. import register


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
    """Install via apt-get, with fallback to brew (macOS) / winget (Windows)."""

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        params = tool.get('parameters', {})
        pkg = params.get('package', '')
        packages = params.get('packages', [])
        if not isinstance(packages, list):
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

        if "linux" in platform_str:
            from config import _apt_update
            _apt_update()
            for pkg_name in packages:
                result = _try_install(pkg_name)
                if result.returncode != 0:
                    print(f"ERROR: apt install failed for {pkg_name}", file=sys.stderr)
                    sys.exit(1)
            return

        if "macos" in platform_str:
            for pkg_name in packages:
                print(f"[BREW] Installing {pkg_name}...")
                result = subprocess.run(['brew', 'install', '--formula', pkg_name], capture_output=True, text=True)
                if result.returncode != 0:
                    print(f"ERROR: brew install failed for {pkg_name}", file=sys.stderr)
                    sys.exit(1)
            return

        if "windows" in platform_str:
            shell = _find_winget_shell()
            for pkg_name in packages:
                winget_id = params.get('winget_id', pkg_name)
                print(f"[WINGET] Installing {winget_id}...")
                if shell in ('pwsh', 'powershell'):
                    winget_cmd = (
                        f'winget install --id {winget_id} '
                        '--accept-package-agreements '
                        '--accept-source-agreements '
                        '--disable-interactivity'
                    )
                    cmd = [shell, '-NoProfile', '-Command', winget_cmd]
                else:
                    cmd = [
                        shell, '/c', 'winget', 'install', '--id', winget_id,
                        '--accept-package-agreements', '--accept-source-agreements',
                        '--disable-interactivity'
                    ]
                result = subprocess.run(cmd, capture_output=True, text=True)
                if result.returncode != 0:
                    print(f"ERROR: winget install failed for {winget_id}", file=sys.stderr)
                    sys.exit(1)
            return

        print(f"ERROR: unknown platform '{platform_str}' for apt install", file=sys.stderr)
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
                f'winget install --id {pkg} '
                '--accept-package-agreements '
                '--accept-source-agreements '
                '--disable-interactivity'
            )
            cmd = [shell, '-NoProfile', '-Command', winget_cmd]
        else:
            cmd = [
                shell, '/c', 'winget', 'install', '--id', pkg,
                '--accept-package-agreements', '--accept-source-agreements',
                '--disable-interactivity'
            ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            if result.stdout and _winget_already_installed(result.stdout):
                print(f"  {pkg} already installed, skipping")
                return
            print(f"ERROR: winget install failed for {pkg}", file=sys.stderr)
            sys.exit(1)
