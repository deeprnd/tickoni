"""Hugging Face model download strategy — pip install huggingface_hub + hf download."""
import os
import shutil
import subprocess
import sys
from ..base import InstallStrategy
from .. import register


def _expand_home(path: str) -> str:
    """Expand ~ to HOME."""
    if path == '~':
        path = os.environ.get('HOME', os.path.expanduser('~'))
    elif path.startswith('~/'):
        path = os.path.join(os.environ.get('HOME', os.path.expanduser('~')), path[2:])
    return path


def _ensure_hf_cli():
    """Ensure huggingface_hub CLI (hf command) is available."""
    if shutil.which('hf'):
        return

    # Try to find pip-installed scripts dirs
    import sysconfig
    scripts_dirs = []
    for scheme in ('nt_user', 'posix_user', 'posix_prefix', 'nt'):
        if scheme in sysconfig.get_scheme_names():
            p = sysconfig.get_path('scripts', scheme=scheme)
            if p:
                scripts_dirs.append(p)

    env_path = os.environ.get('PATH', '')
    for sd in scripts_dirs:
        if sd not in env_path:
            env_path = f"{sd}:{env_path}"

    if shutil.which('hf', path=env_path):
        os.environ['PATH'] = env_path
        return

    # Install via pip
    print("Installing huggingface_hub CLI...")
    result = subprocess.run(
        [sys.executable, '-m', 'pip', 'install', '--user', 'huggingface_hub[cli]'],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        # Try --break-system-packages for Debian/Ubuntu
        result = subprocess.run(
            [sys.executable, '-m', 'pip', 'install', '--break-system-packages',
             'huggingface_hub[cli]'],
            capture_output=True, text=True
        )
    if result.returncode != 0:
        print("ERROR: failed to install huggingface_hub", file=sys.stderr)
        if result.stderr:
            print(result.stderr, file=sys.stderr, end='')
        sys.exit(1)

    # Update PATH again
    for sd in scripts_dirs:
        env_path = f"{sd}:{env_path}"
    os.environ['PATH'] = env_path

    if not shutil.which('hf', path=env_path):
        print("ERROR: hf CLI not found after installing huggingface_hub", file=sys.stderr)
        sys.exit(1)


@register('hf_model')
class HfModelStrategy(InstallStrategy):
    """Download a GGUF model from Hugging Face."""

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        repo_id = tool['parameters'].get(
            'repo_id', 'unsloth/gemma-4-E2B-it-qat-GGUF'
        )
        model_file = tool['parameters'].get(
            'model_file', 'gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf'
        )
        model_dir_raw = tool['parameters'].get(
            'model_dir', '$HOME/work/models/gemma/gemma-4-E2B-it-qat-GGUF'
        )

        # Handle $HOME expansion (from tool-versions.json)
        model_dir = model_dir_raw.replace('$HOME', os.environ.get('HOME', os.path.expanduser('~')))
        model_dir = _expand_home(model_dir)
        model_path = os.path.join(model_dir, model_file)

        # Check if already downloaded
        if os.path.isfile(model_path) and os.path.getsize(model_path) > 0:
            print(f"model already present: {model_path}")
            return

        if dry_run:
            print(f"  [DRY-RUN] Would download {repo_id}/{model_file} -> {model_path}")
            return

        # Ensure hf CLI
        _ensure_hf_cli()

        # Create model dir
        os.makedirs(model_dir, exist_ok=True)

        # Download
        print(f"downloading {repo_id}/{model_file} with hf...")
        result = subprocess.run(
            ['hf', 'download', repo_id, model_file, '--local-dir', model_dir],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            print(f"ERROR: hf download failed: {result.stderr}", file=sys.stderr)
            sys.exit(1)

        # Verify
        if not os.path.isfile(model_path):
            print(f"download finished but model file is missing: {model_path}", file=sys.stderr)
            sys.exit(1)

        print(f"model present: {model_path}")
