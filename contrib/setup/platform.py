"""Platform string helpers and matching."""


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
