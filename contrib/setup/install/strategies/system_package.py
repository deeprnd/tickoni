"""System package-manager install strategies: apt (Linux), brew (macOS), winget (Windows).

``SystemPackageInstallStrategy`` is registered as ``system_package`` and dispatches
on the target platform, so a single cross-platform tool entry installs via apt,
brew, or winget as appropriate. ``BrewInstallStrategy`` and
``WingetInstallStrategy`` remain available for platform-specific tool entries.
"""
from dataclasses import dataclass
import glob
import os
import subprocess
import sys
import re
import shutil
import shlex
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


# WinGet discovery and invocation only ever run on Windows, but this script may
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


@register('system_package')
class SystemPackageInstallStrategy(InstallStrategy):
    """Install via the platform's system package manager: apt-get (Linux),
    brew (macOS), or winget (Windows).

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
            # Try sudo -n first (non-interactive). If sudo requires a password,
            # fall back to apt-get without sudo (works for already-downloaded
            # packages or if the user has passwordless sudo).
            result = subprocess.run([
                'sudo', '-n', 'apt-get', 'install', '-y', '--no-install-recommends', pkg_name
            ], capture_output=True, text=True)
            if result.returncode != 0 and 'password' in (result.stderr or '').lower():
                print(f"  [WARN] sudo -n failed (password required), retrying without sudo")
                result = subprocess.run([
                    'apt-get', 'install', '-y', '--no-install-recommends', pkg_name
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
            # On macOS, Homebrew's `make` formula installs GNU make as
            # `gmake`; Firedancer's GNUmakefile requires that binary.
            resolved_packages = []
            for pkg_name in packages:
                # Keep the Homebrew formula name (`make`), not its binary
                # name (`gmake`).
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
            shell = _require_winget()
            for pkg_name in packages:
                winget_id = params.get('winget_id', pkg_name)
                override = params.get('override', '')
                print(f"[WINGET] Installing {winget_id}...")
                if shell in ('pwsh', 'powershell'):
                    winget_cmd = (
                        f'winget install --id {winget_id} '
                        '--accept-package-agreements '
                        '--accept-source-agreements '
                        '--disable-interactivity '
                        '--source winget'
                    )
                    if override:
                        winget_cmd += f' --override {shlex.quote(override)}'
                    cmd = [shell, '-NoProfile', '-Command', winget_cmd]
                elif _is_winget_executable(shell):
                    cmd = [
                        shell, 'install', '--id', winget_id,
                        '--accept-package-agreements', '--accept-source-agreements',
                        '--disable-interactivity', '--source', 'winget'
                    ]
                    if override:
                        cmd.extend(['--override', override])
                else:
                    cmd = [
                        shell, '/c', 'winget', 'install', '--id', winget_id,
                        '--accept-package-agreements', '--accept-source-agreements',
                        '--disable-interactivity',
                        '--source', 'winget'
                    ]
                    if override:
                        cmd.extend(['--override', override])
                result = subprocess.run(cmd, capture_output=True, text=True)
                if not _winget_succeeded_or_noop(result):
                    output = (result.stdout or '') + (result.stderr or '')
                    if output:
                        print(output, file=sys.stderr, end='')
                    print(
                        f"ERROR: winget install failed for {winget_id} "
                        f"({_winget_failure_status(output)})",
                          file=sys.stderr)
                    sys.exit(1)
            return

        print(f"ERROR: unknown platform '{platform_str}' for system_package install",
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
        params = tool['parameters']
        pkg = params.get('package', '')
        override = params.get('override', '')
        if dry_run:
            print(f"  [DRY-RUN] Would winget install {pkg}")
            return
        print(f"[WINGET] Installing {pkg}...")
        shell = _require_winget()
        if shell in ('pwsh', 'powershell'):
            winget_cmd = (
                f'winget install --exact --id {pkg} '
                '--accept-package-agreements '
                '--accept-source-agreements '
                '--source winget'
            )
            if override:
                winget_cmd += f' --override {shlex.quote(override)}'
            cmd = [shell, '-NoProfile', '-Command', winget_cmd]
        elif _is_winget_executable(shell):
            cmd = [
                shell, 'install', '--exact', '--id', pkg,
                '--accept-package-agreements', '--accept-source-agreements',
                '--disable-interactivity', '--source', 'winget'
            ]
            if override:
                cmd.extend(['--override', override])
        else:
            cmd = [
                shell, '/c', 'winget', 'install', '--exact', '--id', pkg,
                '--accept-package-agreements', '--accept-source-agreements',
                '--source', 'winget'
            ]
            if override:
                cmd.extend(['--override', override])
        result = subprocess.run(cmd, capture_output=True, text=True)
        if not _winget_succeeded_or_noop(result):
            output = (result.stdout or '') + (result.stderr or '')
            if output:
                print(output, file=sys.stderr, end='')
            print(
                f"ERROR: winget install failed for {pkg} "
                f"({_winget_failure_status(output)})",
                file=sys.stderr,
            )
            sys.exit(1)
