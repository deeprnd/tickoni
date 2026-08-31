"""Download strategies: github_release and binary_download."""
import hashlib
import json
import os
import urllib.request
from pathlib import Path
from ..base import DownloadInstallStrategy, _run_cmd
from .. import register
from config import resolve_version
from platform import get_platform_from_string


@register('github_release')
class GitHubReleaseStrategy(DownloadInstallStrategy):
    """Install from GitHub releases."""

    def _resolve_url(self, tool: dict, config: dict, platform_str: str) -> tuple[str, str, str, bool]:
        params = tool['parameters']
        source = params.get('type', 'standard')
        owner = params.get('owner')
        repo = params.get('repo')
        version_ref = params.get('version_ref')
        version = resolve_version(config, version_ref)
        verify_checksum = params.get('verify_checksum', False)

        if source == 'cbmc_deb':
            self._install_cbmc_deb(tool, params, config, platform_str, version)
            return ('', '', '', False)
        if source == 'litani_deb':
            print("[INFO] Litani is installed with CBMC; skipping standalone install")
            return ('', '', '', False)

        os_name, arch = get_platform_from_string(platform_str)
        asset_pattern_os_map = params.get('asset_pattern_os_map', {})
        asset_pattern = params.get('asset_pattern', '')
        pattern = ''

        if asset_pattern_os_map:
            os_map = asset_pattern_os_map.get(os_name, '')
            pattern = os_map.get(arch, '') if isinstance(os_map, dict) else str(os_map)
        elif asset_pattern:
            pattern = asset_pattern.replace('{os}', os_name).replace('{arch}', arch)
        else:
            print(f"ERROR: no asset pattern defined for {owner or repo}", file=__import__('sys').stderr)
            __import__('sys').exit(1)

        if not pattern:
            print(f"ERROR: could not resolve asset for {platform_str}", file=__import__('sys').stderr)
            __import__('sys').exit(1)

        if version:
            pattern = pattern.replace('{version}', version)
        else:
            url = f"https://api.github.com/repos/{owner}/{repo}/releases/latest"
            result = _run_cmd(['curl', '-sSfL', url])
            if result.returncode != 0:
                print(f"ERROR: could not fetch latest release", file=__import__('sys').stderr)
                __import__('sys').exit(1)
            release = json.loads(result.stdout)
            version = release.get('tag_name', '').lstrip('v')
            pattern = pattern.replace('{version}', version)

        download_url = f"https://github.com/{owner}/{repo}/releases/download/v{version}/{pattern}"
        return (download_url, version, pattern, verify_checksum)

    def _install_cbmc_deb(self, tool, params, config, platform_str, version):
        """Install CBMC from GitHub release (Ubuntu-specific deb)."""
        if "linux" not in platform_str:
            print(f"WARNING: CBMC is Linux-only, skipping on {platform_str}", file=__import__('sys').stderr)
            return

        ubuntu_ver = None
        try:
            with open('/etc/os-release') as f:
                for line in f:
                    if line.startswith('VERSION_ID='):
                        ubuntu_ver = line.split('=')[1].strip().strip('"')
                        break
        except FileNotFoundError:
            pass

        if ubuntu_ver not in ('22.04', '24.04'):
            print(f"WARNING: CBMC requires Ubuntu 22.04 or 24.04 (got {ubuntu_ver}), skipping", file=__import__('sys').stderr)
            return

        arch = None
        for part in platform_str.split('-'):
            if part in ('x86', 'arm'):
                arch = part
        if arch == 'x86':
            prefix = f'ubuntu-{ubuntu_ver}-cbmc-'
        elif arch == 'arm' and ubuntu_ver == '24.04':
            prefix = 'ubuntu-24.04-arm64-cbmc-'
        else:
            print(f"WARNING: unsupported arch {platform_str} for CBMC, skipping", file=__import__('sys').stderr)
            return

        import tempfile
        with tempfile.TemporaryDirectory() as tmpdir:
            result = _run_cmd(['curl', '-sSfL', 'https://api.github.com/repos/diffblue/cbmc/releases/latest'])
            if result.returncode != 0:
                print(f"WARNING: could not fetch CBMC releases", file=__import__('sys').stderr)
                return
            release = json.loads(result.stdout)
            assets = release.get('assets', [])
            matching = [a for a in assets if a['name'].startswith(prefix) and a['name'].endswith('-Linux.deb')]
            if not matching:
                matching = [a for a in assets if a['name'].startswith(prefix) and a['name'].endswith('.deb')]
            if not matching:
                print(f"WARNING: no matching CBMC asset found for {prefix}", file=__import__('sys').stderr)
                return
            url = matching[0]['browser_download_url']
            deb_path = Path(tmpdir) / 'cbmc.deb'
            self._download_file(url, deb_path)

            litani_result = _run_cmd(['curl', '-sSfL', 'https://api.github.com/repos/awslabs/aws-build-accumulator/releases/latest'])
            litani_release = json.loads(litani_result.stdout) if litani_result.returncode == 0 else {'assets': []}
            litani_assets = litani_release.get('assets', [])
            litani_match = [a for a in litani_assets if a['name'].startswith('litani-') and a['name'].endswith('.deb')]
            if litani_match:
                litani_url = litani_match[0]['browser_download_url']
                litani_path = Path(tmpdir) / 'litani.deb'
                self._download_file(litani_url, litani_path)
                _run_cmd(['sudo', 'apt-get', 'install', '-y', '--no-install-recommends', str(deb_path), str(litani_path), 'universal-ctags'])
            else:
                _run_cmd(['sudo', 'apt-get', 'install', '-y', '--no-install-recommends', str(deb_path), 'universal-ctags'])


@register('binary_download')
class BinaryDownloadStrategy(DownloadInstallStrategy):
    """Install via arbitrary binary download."""

    def _resolve_url(self, tool: dict, config: dict, platform_str: str) -> tuple[str, str, str, bool]:
        params = tool['parameters']
        url_pattern = params.get('url_pattern', '')
        install_dir = params.get('install_dir', '/usr/local')
        version_ref = params.get('version_ref')

        version = resolve_version(config, version_ref)
        if not version:
            print(f"ERROR: no version for {tool['name']}", file=__import__('sys').stderr)
            __import__('sys').exit(1)

        os_name, arch = get_platform_from_string(platform_str)
        if os_name == 'macos':
            os_name = 'darwin'
        arch_map = {'x86': 'amd64', 'x86_64': 'amd64', 'arm': 'arm64', 'arm64': 'arm64', 'aarch64': 'arm64'}
        if arch is not None:
            arch = arch_map.get(arch, arch)

        url = url_pattern.replace('{version}', version)
        url = url.replace('{{.os}}', os_name).replace('{{.arch}}', arch)
        return (url, version, os.path.basename(url), False)
