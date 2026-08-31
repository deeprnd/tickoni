"""Config loading and version resolution."""
import json
import os
import subprocess


def load_config():
    """Load tool-versions.json from the script's directory."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    json_path = os.path.join(script_dir, 'tool-versions.json')
    with open(json_path) as f:
        return json.load(f)


def resolve_version(config, version_ref):
    """Resolve a version reference from config.versions."""
    if not version_ref:
        return None
    versions = config.get('versions', {})
    val = versions.get(version_ref)
    if val is None:
        return None
    if isinstance(val, dict):
        return str(val.get('version', ''))
    return str(val)


def _apt_update():
    """Run apt-get update once (cached)."""
    if not hasattr(_apt_update, '_updated'):  # type: ignore[attr-defined]
        try:
            subprocess.run(
                ['sudo', '-n', 'apt-get', 'update', '-qq'],
                capture_output=True, timeout=120
            )
        except Exception:
            pass
        _apt_update._updated = True  # type: ignore[attr-defined]
