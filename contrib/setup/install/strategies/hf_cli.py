"""Hugging Face CLI strategy — provision the ``hf`` command in an isolated venv.

The ``hf`` command ships in the base ``huggingface_hub`` distribution; the old
``huggingface_hub[cli]`` extra was removed upstream and now only emits a
warning.  Installing into the interpreter's site-packages is also unsafe on the
CI runners: Homebrew's Python marks its environment externally managed and its
packages carry no ``RECORD`` file, so a transitive dependency bump (for example
``typing_extensions``) makes ``pip`` abort with ``uninstall-no-record-file``.

To stay deterministic and never mutate a system interpreter, this strategy
creates a dedicated virtual environment and installs ``huggingface_hub`` into
it, then puts the venv's script directory on ``PATH`` (and ``$GITHUB_PATH``).
"""
import os
import shutil
import subprocess
import sys
from ..base import InstallStrategy, _activate_path
from .. import register


HF_VENV_DIR = os.path.join(
    os.environ.get('HOME', os.path.expanduser('~')), 'work', 'hf-cli-venv'
)


def _venv_scripts_dir(venv_dir: str) -> str:
    """Return the platform-specific executables directory inside *venv_dir*."""
    if os.name == 'nt' or sys.platform.startswith('win'):
        return os.path.join(venv_dir, 'Scripts')
    return os.path.join(venv_dir, 'bin')


def _venv_python(venv_dir: str) -> str:
    scripts = _venv_scripts_dir(venv_dir)
    return os.path.join(scripts, 'python.exe' if os.name == 'nt' else 'python')


def ensure_hf_cli(dry_run: bool = False) -> str:
    """Ensure the ``hf`` command is available; return its resolved path.

    Idempotent: returns immediately when ``hf`` already resolves, otherwise
    builds the dedicated venv once and reuses it on later runs.
    """
    existing = shutil.which('hf')
    if existing:
        return existing

    scripts_dir = _venv_scripts_dir(HF_VENV_DIR)
    hf_in_venv = shutil.which('hf', path=scripts_dir)
    if hf_in_venv:
        _activate_path([scripts_dir])
        return hf_in_venv

    if dry_run:
        print(f"  [DRY-RUN] Would create venv {HF_VENV_DIR} and install huggingface_hub")
        return os.path.join(scripts_dir, 'hf')

    print(f"Installing huggingface_hub into {HF_VENV_DIR} ...")
    venv_python = _venv_python(HF_VENV_DIR)
    if not os.path.isfile(venv_python):
        result = subprocess.run(
            [sys.executable, '-m', 'venv', HF_VENV_DIR],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            print("ERROR: failed to create huggingface_hub venv", file=sys.stderr)
            if result.stderr:
                print(result.stderr, file=sys.stderr, end='')
            sys.exit(1)

    result = subprocess.run(
        [venv_python, '-m', 'pip', 'install', 'huggingface_hub'],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print("ERROR: failed to install huggingface_hub", file=sys.stderr)
        if result.stdout:
            print(result.stdout, file=sys.stderr, end='')
        if result.stderr:
            print(result.stderr, file=sys.stderr, end='')
        sys.exit(1)

    _activate_path([scripts_dir])
    hf_path = shutil.which('hf', path=scripts_dir)
    if not hf_path:
        print("ERROR: hf CLI not found after installing huggingface_hub", file=sys.stderr)
        sys.exit(1)
    print(f"[INSTALLED] huggingface_hub -> {hf_path}")
    return hf_path


@register('hf_cli')
class HfCliStrategy(InstallStrategy):
    """Provision the ``hf`` command in a dedicated virtual environment."""

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        ensure_hf_cli(dry_run=dry_run)
