"""Homebrew install strategy (macOS)."""
import subprocess
import sys
from ..base import InstallStrategy, _log_version
from .. import register


@register('brew')
class BrewInstallStrategy(InstallStrategy):
    """Install via Homebrew.

    Always installs formulae (``--formula``): every tool routed here is a CLI
    formula, and the flag keeps Homebrew from resolving an identically named
    cask. Homebrew's ``make`` formula installs GNU make as ``gmake``, which is
    the binary Firedancer's GNUmakefile expects — the formula name stays
    ``make``.
    """

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        params = tool.get('parameters', {})
        pkg = params.get('package', '')
        packages = params.get('packages', [])
        if not isinstance(packages, list):
            packages = [pkg]
        if not packages and pkg:
            packages = [pkg]

        if dry_run:
            for p in packages:
                print(f"  [DRY-RUN] Would brew install {p}")
            return

        for pkg_name in packages:
            print(f"[BREW] Installing {pkg_name}...")
            result = subprocess.run(
                ['brew', 'install', '--formula', pkg_name],
                capture_output=True, text=True
            )
            if result.returncode != 0:
                print(f"ERROR: brew install failed for {pkg_name}", file=sys.stderr)
                sys.exit(1)
        _log_version(tool.get('name', ''), packages[-1] if packages else '')
