"""Pip, pipx, and go_install strategies."""
import os
import subprocess
import sys
from ..base import InstallStrategy
from .. import register


@register('pip')
class PipInstallStrategy(InstallStrategy):
    """Install via pip."""

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        pkg = tool['parameters'].get('package', '')
        if dry_run:
            print(f"  [DRY-RUN] Would pip install {pkg}")
            return
        print(f"[PIP] Installing {pkg}...")
        result = subprocess.run([
            'python3', '-m', 'pip', 'install',
            '--break-system-packages', '--upgrade', pkg
        ], capture_output=True, text=True)
        if result.returncode != 0:
            print(f"ERROR: pip install failed for {pkg}", file=sys.stderr)
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
