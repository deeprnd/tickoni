"""nvm install strategy — install Node.js via nvm."""
import os
import shutil
import subprocess
import sys
from ..base import InstallStrategy, _activate_path
from .. import register


NVM_VERSION = '0.40.7'
NVM_INSTALL_URL = f'https://raw.githubusercontent.com/nvm-sh/nvm/v{NVM_VERSION}/install.sh'


def _nvm_bin() -> str | None:
    """Locate the ``nvm`` helper script."""
    # nvm.sh lives under $HOME/.nvm/nvm.sh after install
    nvm_sh = os.path.expanduser('~/.nvm/nvm.sh')
    if os.path.isfile(nvm_sh):
        return nvm_sh
    return None


@register('nvm')
class NvmInstallStrategy(InstallStrategy):
    """Install Node.js via nvm."""

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        version_ref = tool.get('version_ref', 'nodejs')
        version = tool.get('parameters', {}).get('node_version')
        if not version:
            from config import resolve_version
            version = resolve_version(config, version_ref)
        if not version:
            print(f"ERROR: no Node.js version for {tool.get('name', 'nvm')}", file=sys.stderr)
            sys.exit(1)

        if dry_run:
            print(f"  [DRY-RUN] Would install nvm {NVM_VERSION} + Node.js {version}")
            return

        print(f"[NVM] Installing nvm {NVM_VERSION} ...")
        nvm_sh = _nvm_bin()

        # 1. Install nvm if not present
        if not nvm_sh:
            print("[NVM] Downloading nvm install script ...")
            import tempfile
            with tempfile.TemporaryDirectory() as tmpdir:
                script_path = os.path.join(tmpdir, 'install.sh')
                import urllib.request
                urllib.request.urlretrieve(NVM_INSTALL_URL, script_path)
                result = subprocess.run(
                    ['bash', script_path],
                    capture_output=True, text=True,
                )
                if result.returncode != 0:
                    print(f"ERROR: nvm install script failed", file=sys.stderr)
                    if result.stderr:
                        print(result.stderr, file=sys.stderr, end="")
                    sys.exit(1)

        nvm_sh = _nvm_bin()
        if not nvm_sh:
            print("ERROR: nvm.sh not found after install script", file=sys.stderr)
            sys.exit(1)

        # 2. Source nvm and install Node.js
        print(f"[NVM] Installing Node.js {version} ...")
        env = os.environ.copy()
        # nvm.sh needs to be sourced; we run it inline in bash
        cmd = f'source "{nvm_sh}" && nvm install {version}'
        result = subprocess.run(
            ['bash', '-c', cmd],
            capture_output=True, text=True, env=env,
        )
        if result.returncode != 0:
            print(f"ERROR: nvm install Node.js failed", file=sys.stderr)
            if result.stderr:
                print(result.stderr, file=sys.stderr, end="")
            sys.exit(1)

        # 3. Add nvm bin dirs to PATH
        nvm_dir = os.path.expanduser('~/.nvm')
        _activate_path([
            os.path.join(nvm_dir, 'current', 'bin'),
        ])

        # 4. Persist PATH to shell config for subsequent sessions
        _persist_nvm_path(nvm_sh)

        print(f"[INSTALLED] nvm {NVM_VERSION}, Node.js {version}")


def _persist_nvm_path(nvm_sh: str) -> None:
    """Add nvm source lines to .bashrc / .zshrc if not already present."""
    marker = f'nvm.sh\"'
    shell_rc = os.path.expanduser('~/.bashrc')
    if not os.path.isfile(shell_rc):
        return
    try:
        content = open(shell_rc).read()
    except IOError:
        return
    if marker in content:
        return
    lines = (
        '\n# nvm (managed by Hermes setup)\n'
        f'export NVM_DIR="$HOME/.nvm"\n'
        f'[ -s "{nvm_sh}" ] && \. "{nvm_sh}"\n'
    )
    with open(shell_rc, 'a') as f:
        f.write(lines)
