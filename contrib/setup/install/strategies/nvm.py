"""nvm install strategy — install Node.js via nvm."""
import os
import subprocess
import sys
from ..base import InstallStrategy, _activate_path
from config import resolve_version
from .. import register


def _nvm_sh() -> str | None:
    """Locate the nvm helper script."""
    nvm_sh = os.path.expanduser('~/.nvm/nvm.sh')
    if os.path.isfile(nvm_sh):
        return nvm_sh
    return None


@register('nvm')
class NvmInstallStrategy(InstallStrategy):
    """Install Node.js via nvm (curl install.sh | bash, source nvm.sh, nvm install)."""

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        nvm_ref = tool.get('version_ref', 'nvm')
        nvm_version = resolve_version(config, nvm_ref)
        if not nvm_version:
            print(f"ERROR: no nvm version in config for {tool.get('name', 'nvm')}", file=sys.stderr)
            sys.exit(1)

        node_ref = tool.get('parameters', {}).get('node_version', 'nodejs')
        node_version = resolve_version(config, node_ref)
        if not node_version:
            print(f"ERROR: no Node.js version in config for {tool.get('name', 'nvm')}", file=sys.stderr)
            sys.exit(1)

        if dry_run:
            print(f"  [DRY-RUN] Would install nvm {nvm_version} + Node.js {node_version}")
            return

        print(f"[NVM] Installing nvm {nvm_version} ...")
        nvm_sh = _nvm_sh()

        # 1. Install nvm if not present
        if not nvm_sh:
            print("[NVM] Downloading nvm install script ...")
            import tempfile
            import urllib.request
            with tempfile.TemporaryDirectory() as tmpdir:
                script_path = os.path.join(tmpdir, 'install.sh')
                url = f'https://raw.githubusercontent.com/nvm-sh/nvm/v{nvm_version}/install.sh'
                urllib.request.urlretrieve(url, script_path)
                result = subprocess.run(
                    ['bash', script_path],
                    capture_output=True, text=True,
                )
                if result.returncode != 0:
                    print(f"ERROR: nvm install script failed", file=sys.stderr)
                    if result.stderr:
                        print(result.stderr, file=sys.stderr, end="")
                    sys.exit(1)

        nvm_sh = _nvm_sh()
        if not nvm_sh:
            print("ERROR: nvm.sh not found after install script", file=sys.stderr)
            sys.exit(1)

        # 2. Source nvm and install Node.js
        print(f"[NVM] Installing Node.js {node_version} ...")
        env = os.environ.copy()
        cmd = f'source "{nvm_sh}" && nvm install {node_version}'
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

        print(f"[INSTALLED] nvm {nvm_version}, Node.js {node_version}")


def _persist_nvm_path(nvm_sh: str) -> None:
    """Add nvm source lines to .bashrc or .zshrc (whichever exists)."""
    marker = f'nvm.sh"'
    shell_rc = None
    zshrc = os.path.expanduser('~/.zshrc')
    bashrc = os.path.expanduser('~/.bashrc')
    if os.path.isfile(zshrc):
        shell_rc = zshrc
    elif os.path.isfile(bashrc):
        shell_rc = bashrc
    else:
        return
    try:
        content = open(shell_rc).read()
    except IOError:
        return
    if marker in content:
        return
    lines = (
        '\n# nvm (managed by Hermes setup)\n'
        'export NVM_DIR="$HOME/.nvm"\n'
        f'[ -s "{nvm_sh}" ] && \. "{nvm_sh}"\n'
    )
    with open(shell_rc, 'a') as f:
        f.write(lines)
