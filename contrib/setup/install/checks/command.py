"""Check commands for idempotency checks."""
from abc import ABC, abstractmethod
import glob
import ntpath
import os
import re
import shutil
import subprocess


class CheckCommand(ABC):
    """Abstract base for tool-installed check commands."""

    @abstractmethod
    def is_satisfied(self) -> bool:
        """Return True if the tool is already installed."""
        ...


class ShellCheckCommand(CheckCommand):
    """Runs a shell command; satisfied if returncode == 0."""

    def __init__(self, cmd: str):
        self.cmd = cmd

    def is_satisfied(self) -> bool:
        try:
            result = subprocess.run(
                self.cmd, shell=True, capture_output=True, timeout=10
            )
            return result.returncode == 0
        except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
            return False


class ExecutableCheck(CheckCommand):
    """Check a simple executable lookup using the host platform's PATH."""

    def __init__(self, executable: str):
        self.executable = executable

    def is_satisfied(self) -> bool:
        return shutil.which(self.executable) is not None


class MsvcInstalledCommand(CheckCommand):
    """Check the target compiler without requiring a vcvars shell."""

    def __init__(self, target_arch: str):
        self.target_arch = target_arch

    def is_satisfied(self) -> bool:
        install_path = ntpath.join(
            os.environ.get('ProgramFiles(x86)', r'C:\Program Files (x86)'),
            'Microsoft Visual Studio', '2022', 'BuildTools',
        )
        pattern = ntpath.join(
            install_path, 'VC', 'Tools', 'MSVC', '*', 'bin', 'Host*',
            self.target_arch, 'cl.exe',
        )
        return bool(glob.glob(pattern))


class MakeCheck(CheckCommand):
    """Check for GNU Make >= 4.0 on Windows (where POSIX shell checks fail).

    The tool-versions.json uses a complex POSIX pipeline for 'make':
      command -v mingw32-make >/dev/null 2>&1 || { gmake --version ...
    which cmd.exe cannot run.  This class does the same check in Python.
    """

    MAKE_BINARIES = ['mingw32-make', 'gmake', 'make']
    GNU_MAKE_RE = re.compile(r'GNU Make ([4-9]|[0-9][0-9])')

    def is_satisfied(self) -> bool:
        for name in self.MAKE_BINARIES:
            exe = shutil.which(name)
            if exe is None:
                continue
            try:
                result = subprocess.run(
                    [exe, '--version'],
                    capture_output=True, text=True, timeout=10
                )
                if result.returncode == 0 and self.GNU_MAKE_RE.search(result.stdout):
                    return True
            except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
                continue
        return False


class FileExistsCheck(CheckCommand):
    """Check that a file exists on disk (Windows-safe version of `test -f`)."""

    def __init__(self, path: str):
        self.path = path

    def is_satisfied(self) -> bool:
        return os.path.isfile(self.path)


class WingetInstalledCommand(CheckCommand):
    """Winget-specific check: queries winget for the package."""

    def __init__(self, winget_id: str):
        self.winget_id = winget_id

    def is_satisfied(self) -> bool:
        for shell in ('pwsh', 'powershell', 'cmd'):
            try:
                if shell == 'cmd':
                    cmd = f'winget list --id {self.winget_id}'
                else:
                    cmd = f'winget list --id {self.winget_id}'
                    args = [shell, '-NoProfile', '-Command', cmd]
                    result = subprocess.run(args, capture_output=True, timeout=10)
                    return result.returncode == 0 and len(result.stdout.strip()) > 0
            except Exception:
                continue
        return False


_REGISTRY: dict[str, type[CheckCommand]] = {
    'shell': ShellCheckCommand,
    'winget': WingetInstalledCommand,
}


def build_check(tool: dict, platform_str: str = '') -> CheckCommand | None:
    """Create the right check command from tool's idempotent_check field."""
    check = tool.get('idempotent_check', '')
    if not check:
        return None
    if check == 'msvc' and 'windows' in platform_str:
        target_arch = 'arm64' if platform_str == 'windows-arm' else 'x64'
        return MsvcInstalledCommand(target_arch)
    # The shared manifest uses POSIX `command -v`, but shell=True invokes
    # cmd.exe on native Windows, where `command` is not valid.  Resolve the
    # simple executable form directly so preinstalled runner tools are not
    # needlessly sent to winget.
    if 'windows' in platform_str:
        # `command -v <exe>` → shutil.which
        match = re.fullmatch(r'command -v ([A-Za-z0-9_.+-]+)', check.strip())
        if match:
            return ExecutableCheck(match.group(1))
        # `test -f <path>` → os.path.isfile
        test_match = re.fullmatch(r'test -f (.+)', check.strip())
        if test_match:
            return FileExistsCheck(test_match.group(1))
        # Complex make version check → dedicated MakeCheck
        if 'grep -qE' in check and 'GNU Make' in check:
            return MakeCheck()
    return ShellCheckCommand(check)
