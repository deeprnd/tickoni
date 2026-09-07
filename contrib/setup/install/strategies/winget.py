"""WinGet install strategy (Windows).

Also owns WinGet discovery: on hosted Windows runners the ``winget`` execution
alias is often present on PATH but not launchable, so the strategy resolves a
real ``winget.exe`` (or a PowerShell that can reach it) before installing.
"""
from dataclasses import dataclass
import glob
import os
import re
import shlex
import shutil
import subprocess
import sys
from ..base import InstallStrategy
from .. import register


# WinGet discovery and invocation only ever run on Windows, but this module may
# be exercised (and unit-tested) from a POSIX host, where ``os.pathsep`` and
# ``os.path`` use POSIX semantics.  Pin the Windows values so the logic behaves
# identically regardless of the interpreter's host platform.
_WINDOWS_PATH_SEP = ';'


@dataclass(frozen=True)
class WingetResolution:
    """Result of resolving an executable WinGet invocation."""

    command: str | None
    status: str
    detail: str


def _refresh_winget_path() -> None:
    """Expose the per-user WindowsApps and WinGet package directories.

    Do not add every directory below ``WinGet\\Packages``.  Hosted Windows
    runners can have a large package tree, and putting all of it on PATH can
    exceed Windows' 32K environment-variable limit before WinGet is probed.
    """
    local_app_data = os.environ.get('LOCALAPPDATA')
    if not local_app_data:
        return

    package_root = os.path.join(local_app_data, 'Microsoft', 'WinGet', 'Packages')
    candidates = [os.path.join(local_app_data, 'Microsoft', 'WindowsApps')]
    # Portable packages generally place binaries in their package root or a
    # bin subdirectory.  Keep discovery shallow and bounded; _find_winget_shell
    # still searches recursively when it specifically needs winget.exe.
    candidates.extend(glob.glob(os.path.join(package_root, '*')))
    candidates.extend(glob.glob(os.path.join(package_root, '*', 'bin')))
    candidates.extend(glob.glob(os.path.join(package_root, '*', '*', 'bin')))

    path_entries = os.environ.get('PATH', '').split(_WINDOWS_PATH_SEP)
    for candidate in candidates:
        if os.path.isdir(candidate) and candidate not in path_entries:
            path_entries.insert(0, candidate)
    os.environ['PATH'] = _WINDOWS_PATH_SEP.join(path_entries)


def _probe_winget_power_shell(ps: str) -> bool:
    """Verify that PowerShell can resolve and execute WinGet."""
    result = subprocess.run(
        [ps, '-NoProfile', '-Command',
         'Get-Command winget.exe -ErrorAction SilentlyContinue; winget --version'],
        capture_output=True, text=True, timeout=10,
    )
    return result.returncode == 0 and bool(result.stdout.strip())


def _app_installer_present(ps: str) -> bool:
    """Return whether the Microsoft App Installer package is registered."""
    result = subprocess.run(
        [ps, '-NoProfile', '-Command',
         'Get-AppxPackage -Name Microsoft.DesktopAppInstaller'],
        capture_output=True, text=True, timeout=10,
    )
    return result.returncode == 0 and bool(result.stdout.strip())


def _appx_winget_path(ps: str) -> str | None:
    """Return the registered App Installer package's real winget.exe path."""
    result = subprocess.run(
        [ps, '-NoProfile', '-Command',
         "$package = Get-AppxPackage -Name Microsoft.DesktopAppInstaller "
         "| Select-Object -First 1; "
         "if ($package) { Join-Path $package.InstallLocation 'winget.exe' }"],
        capture_output=True, text=True, timeout=10,
    )
    if result.returncode != 0:
        return None
    path = result.stdout.strip().splitlines()
    return path[0].strip() if path else None


def _find_winget_shell() -> WingetResolution:
    """Resolve WinGet and report why resolution failed when it is unavailable."""
    _refresh_winget_path()

    # A real package-local executable is preferable to the WindowsApps UWP
    # alias, which may be visible to PATH but cannot be launched by CreateProcess.
    package_candidates = glob.glob(os.path.join(
        os.environ.get('LOCALAPPDATA', ''), 'Microsoft', 'WinGet',
        'Packages', '**', 'winget.exe'
    ), recursive=True)
    for candidate in [*package_candidates, shutil.which('winget.exe')]:
        if not candidate or 'WindowsApps' in candidate:
            continue
        try:
            result = subprocess.run(
                [candidate, '--version'], capture_output=True, text=True, timeout=10
            )
            if result.returncode == 0:
                return WingetResolution(candidate, 'executable', 'verified executable')
        except (FileNotFoundError, OSError, subprocess.TimeoutExpired):
            pass

    powershells = [ps for ps in ('pwsh', 'powershell') if shutil.which(ps)]
    # On hosted Windows ARM runners the WindowsApps execution alias can be
    # registered but unavailable to the runner account.  Resolve and verify
    # the executable inside the registered App Installer package directly.
    for ps in powershells:
        try:
            candidate = _appx_winget_path(ps)
            if candidate:
                result = subprocess.run(
                    [candidate, '--version'],
                    capture_output=True, text=True, timeout=10,
                )
                if result.returncode == 0:
                    return WingetResolution(candidate, 'appx', 'verified App Installer executable')
        except (FileNotFoundError, OSError, subprocess.TimeoutExpired):
            pass

    for ps in powershells:
        try:
            if _probe_winget_power_shell(ps):
                return WingetResolution(ps, 'powershell', 'PowerShell resolved winget.exe')
        except (FileNotFoundError, OSError, subprocess.TimeoutExpired):
            pass

    app_installer = False
    for ps in powershells:
        try:
            app_installer = _app_installer_present(ps)
            if app_installer:
                break
        except (FileNotFoundError, OSError, subprocess.TimeoutExpired):
            pass

    # Repair only when App Installer is absent.  Always refresh and verify the
    # resulting command; a successful repair command alone is not evidence that
    # winget can execute in this process.
    if powershells and not app_installer:
        ps = powershells[0]
        repair = (
            'Install-Module -Name Microsoft.WinGet.Client '
            '-Repository PSGallery -Force -Scope CurrentUser -Confirm:$false; '
            'Repair-WinGetPackageManager -Latest -Force'
        )
        try:
            result = subprocess.run(
                [ps, '-NoProfile', '-Command', repair],
                capture_output=True, text=True, timeout=120,
            )
            _refresh_winget_path()
            if result.returncode == 0 and _probe_winget_power_shell(ps):
                return WingetResolution(ps, 'repaired', 'WinGet verified after App Installer repair')
        except (FileNotFoundError, OSError, subprocess.TimeoutExpired):
            pass

    if not powershells:
        return WingetResolution(None, 'powershell_missing', 'pwsh and powershell are not on PATH')
    if not app_installer:
        return WingetResolution(None, 'app_installer_missing', 'Microsoft.DesktopAppInstaller is not registered')
    return WingetResolution(None, 'cannot_execute', 'App Installer is present, but winget.exe cannot execute')


def _require_winget() -> str:
    """Return a verified WinGet command or fail with an actionable diagnostic."""
    resolution = _find_winget_shell()
    if resolution.command is None:
        print(
            f"ERROR: WinGet unavailable ({resolution.status}): {resolution.detail}",
            file=sys.stderr,
        )
        sys.exit(1)
    print(f"[WINGET] Using {resolution.command} ({resolution.status})")
    return resolution.command


def _is_winget_executable(command: str) -> bool:
    """Return whether *command* is winget.exe, including an absolute path.

    Windows paths use either separator; split on both rather than relying on
    ``os.path.basename``, which ignores backslashes on a POSIX host.
    """
    return re.split(r'[\\/]', command)[-1].lower() == 'winget.exe'


def _winget_already_installed(output: str) -> bool:
    """Check if winget output means the package is already installed."""
    return any(message in output for message in (
        'Found an existing package already installed',
        'No available upgrade found',
        'No newer package versions are available',
    ))


def _winget_succeeded_or_noop(result) -> bool:
    """Accept winget's successful and already-installed outcomes."""
    output = (result.stdout or '') + (result.stderr or '')
    return result.returncode == 0 or result.returncode == 43 or _winget_already_installed(output)


def _winget_failure_status(output: str) -> str:
    """Classify a failed WinGet command for actionable CI diagnostics."""
    missing_package_markers = (
        'No package found matching input criteria',
        'No package found matching input criteria.',
        'No applicable upgrade found',
    )
    if any(marker in output for marker in missing_package_markers):
        return 'package_not_found_or_unsupported'
    return 'install_failed'


def _winget_install_command(shell: str, winget_id: str, override: str) -> list[str]:
    """Build the ``winget install`` argv for the resolved shell or executable."""
    flags = [
        '--exact', '--id', winget_id,
        '--accept-package-agreements', '--accept-source-agreements',
        '--disable-interactivity', '--source', 'winget',
    ]
    if shell in ('pwsh', 'powershell'):
        winget_cmd = 'winget install ' + ' '.join(flags)
        if override:
            winget_cmd += f' --override {shlex.quote(override)}'
        return [shell, '-NoProfile', '-Command', winget_cmd]
    # A resolved winget.exe is invoked directly; a fallback shell needs `/c`.
    argv = [shell] if _is_winget_executable(shell) else [shell, '/c', 'winget']
    argv += ['install', *flags]
    if override:
        argv += ['--override', override]
    return argv


@register('winget')
class WingetInstallStrategy(InstallStrategy):
    """Install via winget.

    The package id comes from ``winget_id`` (cross-platform tools that name their
    apt/brew package in ``package``) or from ``package`` directly
    (Windows-only tool entries).
    """

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        params = tool.get('parameters', {})
        winget_id = params.get('winget_id') or params.get('package', '')
        override = params.get('override', '')

        if dry_run:
            print(f"  [DRY-RUN] Would winget install {winget_id}")
            return

        print(f"[WINGET] Installing {winget_id}...")
        shell = _require_winget()
        cmd = _winget_install_command(shell, winget_id, override)
        result = subprocess.run(cmd, capture_output=True, text=True)
        if not _winget_succeeded_or_noop(result):
            output = (result.stdout or '') + (result.stderr or '')
            if output:
                print(output, file=sys.stderr, end='')
            print(
                f"ERROR: winget install failed for {winget_id} "
                f"({_winget_failure_status(output)})",
                file=sys.stderr,
            )
            sys.exit(1)
