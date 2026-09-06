"""Node.js install strategy — routes to nvm (Linux/macOS) or chocolatey (Windows)."""
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
        f'[ -s "{nvm_sh}" ] && \\. "{nvm_sh}"\n'
    )
    with open(shell_rc, 'a') as f:
        f.write(lines)


def _ensure_chocolatey() -> None:
    """Install chocolatey if not present on Windows."""
    import shutil
    if shutil.which('choco') or shutil.which('choco.exe'):
        return
    print("[CHOCO] Installing Chocolatey ...")
    import subprocess as sp
    result = sp.run(
        ['cmd', '/c', 'powershell -c "irm https://community.chocolatey.org/install.ps1|iex"'],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(f"ERROR: chocolatey install failed", file=sys.stderr)
        if result.stderr:
            print(result.stderr, file=sys.stderr, end="")
        sys.exit(1)


def _install_nodejs_nvm(config, node_version):
    """Install Node.js via nvm (Linux/macOS)."""
    nvm_ref = 'nvm'
    nvm_version = resolve_version(config, nvm_ref)
    if not nvm_version:
        print(f"ERROR: no nvm version in config", file=sys.stderr)
        sys.exit(1)

    print(f"[NVM] Installing nvm {nvm_version} ...")
    nvm_sh = _nvm_sh()

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

    nvm_dir = os.path.expanduser('~/.nvm')
    _activate_path([os.path.join(nvm_dir, 'current', 'bin')])
    _persist_nvm_path(nvm_sh)

    print(f"[INSTALLED] nvm {nvm_version}, Node.js {node_version}")


def _install_nodejs_chocolatey(config, node_version):
    """Install Node.js via chocolatey (Windows)."""
    import shutil

    _ensure_chocolatey()

    choco_cmd = 'choco install nodejs -y --no-progress --version="' + node_version + '"'
    print(f"[CHOCO] Installing Node.js {node_version} ...")
    result = subprocess.run(
        ['cmd', '/c', choco_cmd],
        capture_output=True, text=True,
    )

    output = (result.stdout or '') + (result.stderr or '')
    already_installed = any(m in output for m in ('already installed.', 'Installed', 'Package installed'))
    if result.returncode != 0 and not already_installed:
        if output:
            print(output, file=sys.stderr, end='')
        print(f"ERROR: choco install failed for Node.js", file=sys.stderr)
        sys.exit(1)

    # Activate Node.js bin dir on PATH
    node_bin = r'C:\Program Files\nodejs'
    _activate_path([node_bin])

    print(f"[INSTALLED] Node.js {node_version} via chocolatey")


@register('nodejs')
class NodejsInstallStrategy(InstallStrategy):
    """Install Node.js — nvm on Linux/macOS, chocolatey on Windows."""

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        node_ref = tool.get('version_ref', 'nodejs')
        node_version = resolve_version(config, node_ref)
        if not node_version:
            print(f"ERROR: no Node.js version in config", file=sys.stderr)
            sys.exit(1)

        if dry_run:
            if 'windows' in platform_str:
                print(f"  [DRY-RUN] Would install Node.js {node_version} via chocolatey")
            else:
                print(f"  [DRY-RUN] Would install Node.js {node_version} via nvm")
            return

        if 'windows' in platform_str:
            _install_nodejs_chocolatey(config, node_version)
        else:
            _install_nodejs_nvm(config, node_version)
