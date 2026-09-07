"""Check commands for idempotency checks."""
from abc import ABC, abstractmethod
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
    # The shared manifest uses POSIX `command -v`, but shell=True invokes
    # cmd.exe on native Windows, where `command` is not valid.  Resolve the
    # simple executable form directly so preinstalled runner tools are not
    # needlessly sent to winget.
    if 'windows' in platform_str:
        match = re.fullmatch(r'command -v ([A-Za-z0-9_.+-]+)', check.strip())
        if match:
            return ExecutableCheck(match.group(1))
    return ShellCheckCommand(check)
