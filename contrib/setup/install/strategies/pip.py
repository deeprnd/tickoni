"""Pip, pipx, and go_install strategies."""
import os
import shutil
import subprocess
import sys
from ..base import InstallStrategy, _activate_path
from .. import register


def _go_binary() -> str | None:
    """Locate the ``go`` binary on PATH or at a well-known install prefix."""
    found = shutil.which('go')
    if found:
        return found
    for candidate in ('/usr/local/go/bin/go', os.path.expanduser('~/go/bin/go')):
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return None


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


def _has_pip(command: list[str]) -> bool:
    """Return True if ``python -m pip`` works for *command*."""
    try:
        probe = subprocess.run(
            command + ["-m", "pip", "--version"], capture_output=True, text=True
        )
    except FileNotFoundError:
        return False
    return probe.returncode == 0


def _bootstrap_pip(command: list[str], platform_str: str) -> None:
    """Best-effort: make ``python -m pip`` available for *command*.

    Debian/Ubuntu ships a minimal ``python3`` without pip or venv; pipx also
    needs venv. Try the stdlib bootstrapper first, then the distro package.
    """
    if _has_pip(command):
        return

    subprocess.run(
        command + ["-m", "ensurepip", "--upgrade", "--default-pip"],
        capture_output=True, text=True,
    )
    if _has_pip(command):
        return

    if "linux" in platform_str and shutil.which("apt-get"):
        from config import _apt_update
        _apt_update()
        apt = ["apt-get", "install", "-y", "--no-install-recommends",
               "python3-pip", "python3-venv"]
        result = subprocess.run(["sudo", "-n", *apt], capture_output=True, text=True)
        if result.returncode != 0 and "password" in (result.stderr or "").lower():
            subprocess.run(apt, capture_output=True, text=True)


def _run_pip(package: str, platform_str: str):
    """Run pip, falling back when a Windows interpreter cannot be spawned."""
    args = ["-m", "pip", "install", "--upgrade", package]
    if "windows" not in platform_str:
        # --break-system-packages is Debian/Ubuntu-specific; skip on macOS.
        args.append("--break-system-packages")

    missing: list[str] = []
    for command in _python_commands():
        _bootstrap_pip(command, platform_str)
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
        go = _go_binary()
        if not go:
            print(
                "ERROR: go toolchain not found on PATH or under /usr/local/go/bin "
                f"while installing {module}; the 'go' category must run first",
                file=sys.stderr,
            )
            sys.exit(1)
        env = os.environ.copy()
        env['PATH'] = f"{os.path.dirname(go)}{os.pathsep}{env.get('PATH', '')}"
        result = subprocess.run(
            [go, 'install', f'{module}@latest'],
            capture_output=True, text=True, env=env,
        )
        if result.returncode != 0:
            print(f"ERROR: go install failed for {module}", file=sys.stderr)
            if result.stdout:
                print(result.stdout, file=sys.stderr, end="")
            if result.stderr:
                print(result.stderr, file=sys.stderr, end="")
            sys.exit(1)
        gobin = subprocess.run(
            [go, 'env', 'GOBIN'], capture_output=True, text=True, env=env,
        ).stdout.strip()
        gopath = subprocess.run(
            [go, 'env', 'GOPATH'], capture_output=True, text=True, env=env,
        ).stdout.strip()
        go_bin = gobin or (os.path.join(gopath, 'bin') if gopath else os.path.expanduser('~/go/bin'))
        _activate_path([go_bin])
