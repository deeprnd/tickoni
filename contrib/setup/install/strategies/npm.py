"""npm install strategy."""
import os
import shutil
import subprocess
import sys
from ..base import InstallStrategy, _activate_path
from .. import register


def _find_npm() -> str | None:
    """Locate the ``npm`` binary — PATH, nvm versions, or fallback."""
    found = shutil.which('npm')
    if found:
        return found
    # nvm: ~/.nvm/versions/node/v<ver>/bin/npm
    nvm_versions = os.path.expanduser('~/.nvm/versions/node/*')
    import glob as _glob
    for ver_dir in sorted(_glob.glob(nvm_versions), reverse=True):
        candidate = os.path.join(ver_dir, 'bin', 'npm')
        if os.path.isfile(candidate):
            return candidate
    # legacy nvm shim
    shim = os.path.expanduser('~/.nvm/current/bin/npm')
    if os.path.isfile(shim):
        return shim
    return None


def _find_npm_bin_dir() -> str | None:
    """Find the bin dir that npm will use for global installs."""
    npm_path = _find_npm()
    if not npm_path:
        return None
    npm_bin = os.path.dirname(npm_path)
    # If it's nvm's "current" symlink, resolve to real version dir
    real = os.path.realpath(npm_bin)
    if os.path.basename(real) == 'bin' and 'nvm' in real:
        return real
    return npm_bin


@register('npm')
class NpmInstallStrategy(InstallStrategy):
    """Install via npm global install."""

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        package = tool['parameters'].get('package', '')
        if dry_run:
            print(f"  [DRY-RUN] Would npm install -g {package}")
            return
        print(f"[NPM] Installing {package}...")
        npm = _find_npm()
        if not npm:
            print(
                "ERROR: npm toolchain not found while installing "
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
        # Activate the npm bin dir so installed binaries are on PATH
        bin_dir = _find_npm_bin_dir()
        if bin_dir:
            _activate_path([bin_dir])
        print(f"[INSTALLED] {package} via npm")
