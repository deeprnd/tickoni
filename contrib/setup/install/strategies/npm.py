"""npm install strategy."""
import os
import shutil
import subprocess
import sys
from ..base import InstallStrategy
from .. import register


def _npm_binary() -> str | None:
    """Locate the ``npm`` binary on PATH."""
    found = shutil.which('npm')
    if found:
        return found
    # Check node.js install dirs
    for candidate in (
        os.path.expanduser('~/.nvm/versions/node/*/bin/npm'),
        os.path.expanduser('~/.npm/bin/npm'),
        '/usr/local/bin/npm',
    ):
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return None


@register('npm')
class NpmInstallStrategy:
    """Install via npm global install."""

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        package = tool['parameters'].get('package', '')
        if dry_run:
            print(f"  [DRY-RUN] Would npm install -g {package}")
            return
        print(f"[NPM] Installing {package}...")
        npm = _npm_binary()
        if not npm:
            print(
                "ERROR: npm toolchain not found on PATH while installing "
                f"{package}; the 'nodejs' category must run first",
                file=sys.stderr,
            )
            sys.exit(1)
        result = subprocess.run(
            [npm, 'install', '-g', package],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            print(f"ERROR: npm install failed for {package}", file=sys.stderr)
            if result.stdout:
                print(result.stdout, file=sys.stderr, end="")
            if result.stderr:
                print(result.stderr, file=sys.stderr, end="")
            sys.exit(1)
