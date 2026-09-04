"""Python script strategy."""
import os
from ..base import InstallStrategy
from .. import register
from config import resolve_version


@register('python_script')
class PythonScriptStrategy(InstallStrategy):
    """Run a Python installer script."""

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        script = tool['parameters'].get('script', '')
        args = tool['parameters'].get('args', [])
        version_ref = tool['parameters'].get('version_ref')

        script_dir = os.path.dirname(os.path.abspath(__file__))
        parent_dir = os.path.dirname(os.path.dirname(os.path.dirname(script_dir)))
        script_path = os.path.join(parent_dir, 'helpers', script)
        if not os.path.isfile(script_path):
            print(f"ERROR: script not found: {script_path}", file=__import__('sys').stderr)
            __import__('sys').exit(1)

        if dry_run:
            print(f"  [DRY-RUN] Would run python3 '{script_path}' --platform {platform_str} {' '.join(args)}")
            return

        cmd = ['python3', script_path, '--platform', platform_str]
        version = resolve_version(config, version_ref)
        if version:
            cmd.append(version)
        cmd.extend(args)

        print(f"[PYTHON] Running {script_path}...")
        result = __import__('subprocess').run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"ERROR: python installer failed", file=__import__('sys').stderr)
            __import__('sys').exit(1)
