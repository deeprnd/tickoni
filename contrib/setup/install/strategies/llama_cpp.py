"""Llama.cpp install strategy — calls the setup scripts."""
import os
import subprocess
import sys
from .. import register
from ..base import InstallStrategy


@register('llama_cpp')
class LlamaCppInstallStrategy(InstallStrategy):
    """Install llama.cpp by running the platform-specific setup script."""

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        script = tool['parameters'].get('script', '')
        check_only = tool['parameters'].get('check_only', False)

        script_dir = os.path.dirname(os.path.abspath(__file__))
        parent_dir = os.path.dirname(os.path.dirname(os.path.dirname(script_dir)))
        script_path = os.path.join(parent_dir, script)

        if not os.path.isfile(script_path):
            print(f"ERROR: llama.cpp setup script not found: {script_path}", file=sys.stderr)
            sys.exit(1)

        if dry_run:
            print(f"  [DRY-RUN] Would run {script_path}")
            return

        cmd = ['bash', script_path]
        if check_only:
            cmd.append('--check-only')

        print(f"[LLAMA.CPP] Running {script_path}...")
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.stdout:
            print(result.stdout)
        if result.stderr:
            print(result.stderr, file=sys.stderr)
        if result.returncode != 0:
            print(f"ERROR: {script} failed (exit {result.returncode})", file=sys.stderr)
            sys.exit(1)
