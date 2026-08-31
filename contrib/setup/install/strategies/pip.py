"""Pip, pipx, and go_install strategies."""
import os
import shutil
import subprocess
import sys
from ..base import InstallStrategy
from .. import register


def _python_commands() -> list[list[str]]:
    """Return usable Python launchers, preferring the current interpreter.

    On Windows CI, ``sys.executable`` can refer to a toolcache path that is no
    longer spawnable after the runner image updates.  The Python launcher and
    PATH-resolved interpreters provide reliable fallbacks, including on ARM.
    """
    commands: list[list[str]] = []
    if sys.executable:
        commands.append([sys.executable])

    for launcher in (("py", "-3"), ("python",), ("python3",)):
        executable = shutil.which(launcher[0])
        if executable and [executable, *launcher[1:]] not in commands:
            commands.append([executable, *launcher[1:]])
    return commands


def _run_pip(package: str, platform_str: str):
    """Run pip, falling back when a Windows interpreter cannot be spawned."""
    args = ["-m", "pip", "install", "--upgrade", package]
    if "windows" not in platform_str:
        # --break-system-packages is Debian/Ubuntu-specific; skip on macOS.
        args.append("--break-system-packages")

    missing: list[str] = []
    for command in _python_commands():
        try:
            return subprocess.run(command + args, capture_output=True, text=True)
        except FileNotFoundError:
            missing.append(command[0])

    attempted = ", ".join(missing) or "no Python interpreter"
    raise FileNotFoundError(
        f"could not spawn a Python interpreter while installing {package}; "
        f"attempted: {attempted}"
    )


@register('pip')
class PipInstallStrategy(InstallStrategy):
    """Install via pip."""

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        pkg = tool['parameters'].get('package', '')
        if dry_run:
            print(f"  [DRY-RUN] Would pip install {pkg}")
            return
        print(f"[PIP] Installing {pkg}...")
        try:
            result = _run_pip(pkg, platform_str)
        except FileNotFoundError as error:
            print(f"ERROR: {error}", file=sys.stderr)
            sys.exit(1)
        if result.returncode != 0:
            print(f"ERROR: pip install failed for {pkg}", file=sys.stderr)
            if result.stdout:
                print(result.stdout, file=sys.stderr, end="")
            if result.stderr:
                print(result.stderr, file=sys.stderr, end="")
            sys.exit(1)


@register('pipx')
class PipxInstallStrategy(InstallStrategy):
    """Install via pipx."""

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        pkg = tool['parameters'].get('package', '')
        if dry_run:
            print(f"  [DRY-RUN] Would pipx install {pkg}")
            return
        print(f"[PIP] Installing {pkg}...")
        result = subprocess.run(['pipx', 'install', pkg], capture_output=True, text=True)
        if result.returncode != 0:
            print(f"ERROR: pipx install failed for {pkg}", file=sys.stderr)
            sys.exit(1)


@register('go_install')
class GoInstallStrategy(InstallStrategy):
    """Install via go install."""

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        module = tool['parameters'].get('module', '')
        if dry_run:
            print(f"  [DRY-RUN] Would go install {module}")
            return
        print(f"[GO] Installing {module}...")
        result = subprocess.run(['go', 'install', f'{module}@latest'], capture_output=True, text=True)
        if result.returncode != 0:
            print(f"ERROR: go install failed for {module}", file=sys.stderr)
            sys.exit(1)
        go_bin = os.path.expanduser('~/go/bin')
        if os.path.isdir(go_bin):
            path_parts = os.environ.get('PATH', '').split(':')
            if go_bin not in path_parts:
                os.environ['PATH'] = f"{go_bin}:{os.environ['PATH']}"
                print(f"  Added {go_bin} to PATH")
