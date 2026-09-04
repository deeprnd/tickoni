"""Platform string helpers and matching."""
import os
import subprocess
from shell import bash_command


def matches_platform(tool, platform_key):
    """Check if tool matches the current platform."""
    p = tool.get('platform', 'all')
    if p == 'all':
        return True
    if p == platform_key:
        return True
    if platform_key.startswith(p + '-') or platform_key == p:
        return True
    if p in platform_key:
        return True
    return False


def detect_platform(args_platform):
    """Determine platform: use --platform arg, or detect via platform.sh."""
    if args_platform:
        return args_platform
    try:
        # platform.sh lives at <repo_root>/contrib/platform.sh
        script_dir = os.path.dirname(os.path.abspath(__file__))
        repo_root = os.path.dirname(os.path.dirname(script_dir))
        plat = subprocess.check_output(
            [bash_command(), 'contrib/platform.sh', 'platform'],
            stderr=subprocess.DEVNULL,
            cwd=repo_root,
        ).decode().strip()
        return plat
    except Exception:
        print("ERROR: could not detect platform. Use --platform linux-x86 etc.", file=__import__('sys').stderr)
        __import__('sys').exit(1)


def get_platform_from_string(platform_str):
    """Extract os/arch from platform string for URL substitution."""
    os_name = None
    arch = None
    for part in platform_str.split('-'):
        if part in ('linux', 'macos', 'windows', 'darwin'):
            os_name = part
        elif part in ('x86', 'x86_64', 'amd64'):
            arch = 'amd64'
        elif part in ('arm', 'arm64', 'aarch64'):
            arch = 'arm64'
    return os_name, arch
