#!/usr/bin/env python3
"""CI tool orchestrator — reads tool-versions.json and installs tools.

Usage:
    python3 orchestrator.py <category1,category2,...>     # Install
    python3 orchestrator.py <categories> --dry-run        # Preview
    python3 orchestrator.py --deps <category>              # Show resolved deps
    python3 orchestrator.py --list <category>              # List tools
    python3 orchestrator.py <categories> --platform linux-x86  # Override platform
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zipfile
from pathlib import Path


# ── Helpers ──────────────────────────────────────────────────────────────────
# Platform detection is the single source of truth in contrib/platform.sh.
# All scripts in contrib/setup/ derive platform from --platform or platform.sh.


def load_config():
    """Load tool-versions.json from the script's directory."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    json_path = os.path.join(script_dir, 'tool-versions.json')
    with open(json_path) as f:
        return json.load(f)


def resolve_deps(requested, dependencies):
    """Resolve category dependencies recursively. Detects cycles."""
    resolved = []
    visiting = set()

    def visit(cat):
        if cat in resolved:
            return
        if cat in visiting:
            print(f"ERROR: circular dependency detected: {cat}", file=sys.stderr)
            sys.exit(1)
        visiting.add(cat)
        for dep in dependencies.get(cat, []):
            visit(dep)
        resolved.append(cat)
        visiting.discard(cat)

    for cat in requested:
        visit(cat)
    return resolved


def collect_tools(resolved_categories, categories_config, tools_config):
    """Collect all tools from resolved categories, preserving dependency order."""
    tools = []
    seen = set()
    for cat in resolved_categories:
        cat_info = categories_config.get(cat, {})
        for tool_name in cat_info.get('tools', []):
            if tool_name not in seen and tool_name in tools_config:
                tool = tools_config[tool_name].copy()
                tool['name'] = tool_name
                tool['category'] = cat
                # Propagate top-level version_ref into parameters so
                # install_python_script can read params.get('version_ref')
                if 'version_ref' in tool:
                    tool.setdefault('parameters', {}).setdefault(
                        'version_ref', tool['version_ref']
                    )
                tools.append(tool)
                seen.add(tool_name)
    return tools


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


def idempotent_check(check_cmd):
    """Run idempotency check. Returns True if already installed."""
    if not check_cmd:
        return False
    try:
        result = subprocess.run(
            check_cmd, shell=True, capture_output=True, timeout=10
        )
        return result.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        return False


def run_cmd(cmd, capture=True, shell=False, **kwargs):
    """Run a command and print its output."""
    if capture and not shell:
        print(f"  $ {' '.join(cmd)}")
    elif capture and shell:
        print(f"  $ {cmd}")
    result = subprocess.run(cmd, shell=shell, capture_output=capture, text=True, **kwargs)
    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result


def _download_file(url, dest, dry_run=False):
    """Download a file from url to dest, with retries."""
    if dry_run:
        print(f"[download] {url} -> {dest} (dry-run)")
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    attempts = 0
    while attempts < 3:
        result = run_cmd(['curl', '-sSfL', '--retry', '3', '-o', str(dest), url])
        if result.returncode == 0 and dest.is_file() and dest.stat().st_size > 0:
            return
        attempts += 1
    print(f"ERROR: download failed for {url}", file=sys.stderr)
    sys.exit(1)


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


# ── Install Methods ──────────────────────────────────────────────────────────

def _apt_update():
    """Run apt-get update once."""
    if not hasattr(_apt_update, '_updated'):
        try:
            subprocess.run(
                ['sudo', '-n', 'apt-get', 'update', '-qq'],
                capture_output=True, timeout=120
            )
        except Exception:
            pass
        _apt_update._updated = True


def install_apt(tool, params, config, platform_str, dry_run=False):
    """Install via apt-get, with fallback to brew (macOS) / winget (Windows)."""
    pkg = params.get('package', '')
    packages = params.get('packages', [])
    if not isinstance(packages, list):
        packages = [pkg]

    if dry_run:
        for p in packages:
            print(f"  [DRY-RUN] Would install {p}")
        return

    def _try_install(pkg_name):
        print(f"[INSTALL] Installing {pkg_name}...")
        result = run_cmd([
            'sudo', '-n', 'apt-get', 'install', '-y', '--no-install-recommends', pkg_name
        ])
        return result

    # Determine platform from contrib/platform.sh string
    if "linux" in platform_str:
        _apt_update()
        for pkg_name in packages:
            result = _try_install(pkg_name)
            if result.returncode != 0:
                print(f"ERROR: apt install failed for {pkg_name}", file=sys.stderr)
                sys.exit(1)
        return

    if "macos" in platform_str:
        for pkg_name in packages:
            print(f"[BREW] Installing {pkg_name}...")
            result = run_cmd(['brew', 'install', '--formula', pkg_name])
            if result.returncode != 0:
                print(f"ERROR: brew install failed for {pkg_name}", file=sys.stderr)
                sys.exit(1)
        return

    if "windows" in platform_str:
        for pkg_name in packages:
            winget_id = params.get('winget_id', pkg_name)
            print(f"[WINGET] Installing {winget_id}...")
            cmd = [
                *_find_winget(), 'install', '--id', winget_id,
                '--accept-package-agreements', '--accept-source-agreements',
                '--disable-interactivity']
            result = run_cmd(cmd)
            if result.returncode != 0:
                print(f"ERROR: winget install failed for {winget_id}", file=sys.stderr)
                sys.exit(1)
        return

    print(f"ERROR: unknown platform '{platform_str}' for apt install", file=sys.stderr)
    sys.exit(1)


def install_brew(tool, params, config, platform_str, dry_run=False):
    """Install via brew."""
    pkg = params.get('package', '')
    if dry_run:
        print(f"  [DRY-RUN] Would brew install {pkg}")
        return
    print(f"[BREW] Installing {pkg}...")
    result = run_cmd(['brew', 'install', pkg])
    if result.returncode != 0:
        print(f"ERROR: brew install failed for {pkg}", file=sys.stderr)
        sys.exit(1)


def _winget_already_installed(output: str) -> bool:
    """Check if winget output means the package is already installed."""
    return 'Found an existing package already installed' in output


def _find_winget():
    """Resolve winget for subprocess execution on Windows.

    Uses `cmd /c winget` because the WindowsApps stub (found by shutil.which)
    is a UWP app that CreateProcess cannot launch directly.  cmd /c handles
    all PATH resolution reliably on GitHub Actions runners and local boxes.
    """
    return ['cmd', '/c', 'winget']


def install_winget(tool, params, config, platform_str, dry_run=False):
    """Install via winget."""
    pkg = params.get('package', '')
    if dry_run:
        print(f"  [DRY-RUN] Would winget install {pkg}")
        return
    print(f"[WINGET] Installing {pkg}...")
    cmd = [
        *_find_winget(), 'install', '--id', pkg,
        '--accept-package-agreements', '--accept-source-agreements',
        '--disable-interactivity'
    ]
    result = run_cmd(cmd)
    if result.returncode != 0:
        # winget returns 1 when package already installed with no upgrade
        if result.stdout and _winget_already_installed(result.stdout):
            print(f"  {pkg} already installed, skipping")
            return
        print(f"ERROR: winget install failed for {pkg}", file=sys.stderr)
        sys.exit(1)


def install_pip(tool, params, config, platform_str, dry_run=False):
    """Install via pip."""
    pkg = params.get('package', '')
    if dry_run:
        print(f"  [DRY-RUN] Would pip install {pkg}")
        return
    print(f"[PIP] Installing {pkg}...")
    result = run_cmd([
        'python3', '-m', 'pip', 'install',
        '--break-system-packages', '--upgrade', pkg
    ])
    if result.returncode != 0:
        print(f"ERROR: pip install failed for {pkg}", file=sys.stderr)
        sys.exit(1)


def install_pipx(tool, params, config, platform_str, dry_run=False):
    """Install via pipx."""
    pkg = params.get('package', '')
    if dry_run:
        print(f"  [DRY-RUN] Would pipx install {pkg}")
        return
    print(f"[PIP] Installing {pkg}...")
    result = run_cmd(['pipx', 'install', pkg])
    if result.returncode != 0:
        print(f"ERROR: pipx install failed for {pkg}", file=sys.stderr)
        sys.exit(1)


def install_go_install(tool, params, config, platform_str, dry_run=False):
    """Install via go install."""
    module = params.get('module', '')
    if dry_run:
        print(f"  [DRY-RUN] Would go install {module}")
        return
    print(f"[GO] Installing {module}...")
    result = run_cmd(['go', 'install', f'{module}@latest'])
    if result.returncode != 0:
        print(f"ERROR: go install failed for {module}", file=sys.stderr)
        sys.exit(1)
    # Ensure go/bin is on PATH
    go_bin = os.path.expanduser('~/go/bin')
    if os.path.isdir(go_bin):
        path_parts = os.environ.get('PATH', '').split(':')
        if go_bin not in path_parts:
            os.environ['PATH'] = f"{go_bin}:{os.environ['PATH']}"
            print(f"  Added {go_bin} to PATH")


def install_github_release(tool, params, config, platform_str, dry_run=False):
    """Install from GitHub releases."""
    source = params.get('type', 'standard')
    owner = params.get('owner')
    repo = params.get('repo')
    version_ref = params.get('version_ref')
    version = resolve_version(config, version_ref)
    verify_checksum = params.get('verify_checksum', False)
    bin_name = params.get('bin_name', owner or repo)

    if source == 'cbmc_deb':
        _install_cbmc_deb(tool, params, config, platform_str, dry_run, version)
        return
    if source == 'litani_deb':
        _install_litani_deb(tool, params, config, platform_str, dry_run, version)
        return

    # Platform-specific asset resolution — uses platform.sh string directly.
    asset_pattern_os_map = params.get('asset_pattern_os_map', {})
    asset_pattern = params.get('asset_pattern', '')

    os_name = None
    arch = None
    for part in platform_str.split('-'):
        if part in ('linux', 'macos', 'windows', 'darwin'):
            os_name = part
        elif part in ('x86', 'x86_64', 'amd64'):
            arch = 'amd64'
        elif part in ('arm', 'arm64', 'aarch64'):
            arch = 'arm64'

    if asset_pattern_os_map:
        os_map = asset_pattern_os_map.get(os_name, '')
        if isinstance(os_map, dict):
            pattern = os_map.get(arch, '')
        else:
            pattern = str(os_map)
    elif asset_pattern:
        pattern = asset_pattern
        pattern = pattern.replace('{os}', os_name)
        pattern = pattern.replace('{arch}', arch)
    else:
        print(f"ERROR: no asset pattern defined for {owner or repo}", file=sys.stderr)
        sys.exit(1)

    if not pattern:
        print(f"ERROR: could not resolve asset for {platform_str}", file=sys.stderr)
        sys.exit(1)

    # Substitute {version} in the resolved pattern (runs regardless of branch).
    if version:
        pattern = pattern.replace('{version}', version)

    # Fetch latest tag if version is not pinned
    if not version:
        url = f"https://api.github.com/repos/{owner}/{repo}/releases/latest"
        result = run_cmd(['curl', '-sSfL', url])
        if result.returncode != 0:
            print(f"ERROR: could not fetch latest release", file=sys.stderr)
            sys.exit(1)
        release = json.loads(result.stdout)
        version = release.get('tag_name', '').lstrip('v')
        pattern = pattern.replace('{version}', version)

    if dry_run:
        print(f"  [DRY-RUN] Would download v{version}/{pattern}")
        return

    with tempfile.TemporaryDirectory() as tmpdir:
        archive_path = Path(os.path.join(tmpdir, pattern))
        download_url = f"https://github.com/{owner}/{repo}/releases/download/v{version}/{pattern}"
        _download_file(download_url, archive_path)
        if not archive_path.exists() or archive_path.stat().st_size == 0:
            print(f"ERROR: download failed for {download_url}", file=sys.stderr)
            sys.exit(1)

        # Verify checksum if requested
        if verify_checksum and version:
            checksum_url = f"https://github.com/{owner}/{repo}/releases/download/v{version}/{pattern.replace('.tar.gz', '')}_checksums.txt"
            cs_result = run_cmd(['curl', '-sSfL', checksum_url])
            if cs_result.returncode == 0 and cs_result.stdout.strip():
                actual = hashlib.sha256(Path(archive_path).read_bytes()).hexdigest()
                for line in cs_result.stdout.strip().split('\n'):
                    parts = line.strip().split()
                    if len(parts) >= 2:
                        expected = parts[0]
                        cs_file = parts[1].lstrip('*')
                        if cs_file == pattern or pattern in cs_file:
                            if expected != actual:
                                print(f"ERROR: checksum mismatch for {pattern}", file=sys.stderr)
                                sys.exit(1)
                            print(f"  Checksum verified")
                            break

        # Extract
        if pattern.endswith(('.tar.gz', '.tgz')):
            run_cmd(['tar', '-xzf', archive_path, '-C', tmpdir])
        elif pattern.endswith('.zip'):
            run_cmd(['unzip', '-o', archive_path, '-d', tmpdir])
        else:
            print(f"ERROR: unsupported archive format: {pattern}", file=sys.stderr)
            sys.exit(1)

        # Find and install binary
        bin_path = None
        for root, dirs, files in os.walk(tmpdir):
            for f in files:
                if f == bin_name:
                    bin_path = os.path.join(root, f)
                    break
            if bin_path:
                break

        if bin_path and os.path.isfile(bin_path):
            print(f"  Installing {bin_name} to /usr/local/bin/")
            run_cmd(['sudo', 'install', '-m', '755', bin_path, f'/usr/local/bin/{bin_name}'])
        else:
            print(f"WARNING: could not find {bin_name} in archive", file=sys.stderr)


def _install_cbmc_deb(tool, params, config, platform_str, dry_run, version):
    """Install CBMC from GitHub release (Ubuntu-specific deb)."""
    if dry_run:
        print(f"  [DRY-RUN] Would install cbmc deb from GitHub release")
        return

    # Only on Linux
    if "linux" not in platform_str:
        print(f"WARNING: CBMC is Linux-only, skipping on {platform_str}", file=sys.stderr)
        return

    # Determine Ubuntu version and architecture
    try:
        with open('/etc/os-release') as f:
            for line in f:
                if line.startswith('VERSION_ID='):
                    ubuntu_ver = line.split('=')[1].strip().strip('"')
                    break
            else:
                ubuntu_ver = None
    except FileNotFoundError:
        ubuntu_ver = None

    if ubuntu_ver not in ('22.04', '24.04'):
        print(f"WARNING: CBMC requires Ubuntu 22.04 or 24.04 (got {ubuntu_ver}), skipping", file=sys.stderr)
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
        print(f"WARNING: unsupported arch {platform_str} for CBMC, skipping", file=sys.stderr)
        return

    with tempfile.TemporaryDirectory() as tmpdir:
        # Fetch latest release and find matching asset
        result = run_cmd(['curl', '-sSfL', 'https://api.github.com/repos/diffblue/cbmc/releases/latest'])
        if result.returncode != 0:
            print(f"WARNING: could not fetch CBMC releases", file=sys.stderr)
            return

        release = json.loads(result.stdout)
        assets = release.get('assets', [])
        matching = [a for a in assets if a['name'].startswith(prefix) and a['name'].endswith('-Linux.deb')]
        if not matching:
            matching = [a for a in assets if a['name'].startswith(prefix) and a['name'].endswith('.deb')]
        if not matching:
            print(f"WARNING: no matching CBMC asset found for {prefix}", file=sys.stderr)
            return

        url = matching[0]['browser_download_url']
        deb_path = Path(os.path.join(tmpdir, 'cbmc.deb'))
        _download_file(url, deb_path)

        # Also get litani URL for batch install
        litani_result = run_cmd(['curl', '-sSfL', 'https://api.github.com/repos/awslabs/aws-build-accumulator/releases/latest'])
        litani_release = json.loads(litani_result.stdout) if litani_result.returncode == 0 else {'assets': []}
        litani_assets = litani_release.get('assets', [])
        litani_match = [a for a in litani_assets if a['name'].startswith('litani-') and a['name'].endswith('.deb')]
        if litani_match:
            litani_url = litani_match[0]['browser_download_url']
            litani_path = Path(os.path.join(tmpdir, 'litani.deb'))
            _download_file(litani_url, litani_path)
            run_cmd(['sudo', 'apt-get', 'install', '-y', '--no-install-recommends', deb_path, litani_path, 'universal-ctags'])
        else:
            run_cmd(['sudo', 'apt-get', 'install', '-y', '--no-install-recommends', deb_path, 'universal-ctags'])


def _install_litani_deb(tool, params, config, platform_str, dry_run, version):
    """Install Litani from GitHub release."""
    if dry_run:
        print(f"  [DRY-RUN] Would install litani deb from GitHub release")
        return
    # Litani is installed alongside CBMC, so this is a no-op here
    # The CBMC install method handles both
    print("[INFO] Litani is installed with CBMC; skipping standalone install")


def install_binary_download(tool, params, config, platform_str, dry_run=False):
    """Install via arbitrary binary download."""
    url_pattern = params.get('url_pattern', '')
    install_dir = params.get('install_dir', '/usr/local')
    version_ref = params.get('version_ref')
    bin_dirs = params.get('bin_dirs', [])

    version = resolve_version(config, version_ref)
    if not version:
        print(f"ERROR: no version for {tool['name']}", file=sys.stderr)
        sys.exit(1)

    # Resolve platform string to os/arch for URL substitution
    os_name = None
    arch = None
    for part in platform_str.split('-'):
        if part in ('linux', 'macos', 'windows', 'darwin'):
            os_name = part
        elif part in ('x86', 'arm', 'x86_64', 'aarch64', 'arm64'):
            arch = part

    # Normalize os/arch to canonical names expected by binary_download tools.
    # Go uses darwin/linux/windows + amd64/arm64, not macos/linux/windows + x86/arm.
    if os_name == 'macos':
        os_name = 'darwin'
    arch_map = {'x86': 'amd64', 'x86_64': 'amd64', 'arm': 'arm64', 'arm64': 'arm64', 'aarch64': 'arm64'}
    if arch is not None:
        arch = arch_map.get(arch, arch)

    url = url_pattern.replace('{version}', version)
    url = url.replace('{{.os}}', os_name).replace('{{.arch}}', arch)

    if dry_run:
        print(f"  [DRY-RUN] Would download {url} to {install_dir}")
        return

    with tempfile.TemporaryDirectory() as tmpdir:
        archive = Path(os.path.join(tmpdir, 'download.tar.gz'))
        _download_file(url, archive)

        # Install to target directory
        if install_dir == '/usr/local/go':
            print(f"  Installing Go to {install_dir}...")
            run_cmd(['sudo', 'rm', '-rf', install_dir])
            run_cmd(['sudo', 'tar', '-C', '/usr/local', '-xzf', archive])
        else:
            run_cmd(['tar', '-xzf', archive, '-C', tmpdir])

        # Add bin dirs to PATH
        for bin_dir in bin_dirs:
            expanded = bin_dir.replace('$HOME', os.path.expanduser('~'))
            path_parts = os.environ.get('PATH', '').split(':')
            if os.path.isdir(expanded) and expanded not in path_parts:
                os.environ['PATH'] = f"{expanded}:{os.environ['PATH']}"
                print(f"  Added {expanded} to PATH")


def install_python_script(tool, params, config, platform_str, dry_run=False):
    """Run a Python installer script."""
    script = params.get('script', '')
    args = params.get('args', [])
    version_ref = params.get('version_ref')
    install_root = params.get('install_root', os.path.expanduser('~/.local'))

    script_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'helpers', script)
    if not os.path.isfile(script_path):
        print(f"ERROR: script not found: {script_path}", file=sys.stderr)
        sys.exit(1)

    if dry_run:
        print(f"  [DRY-RUN] Would run python3 '{script_path}' --platform {platform_str} {' '.join(args)}")
        return

    # Build command — pass --platform to the helper so it never detects on its own.
    cmd = ['python3', script_path, '--platform', platform_str]
    version = resolve_version(config, version_ref)
    if version:
        cmd.append(version)
    cmd.extend(args)

    print(f"[PYTHON] Running {script_path}...")
    result = run_cmd(cmd)
    if result.returncode != 0:
        print(f"ERROR: python installer failed", file=sys.stderr)
        sys.exit(1)


def install_build_from_source(tool, params, config, platform_str, dry_run=False):
    """Build from source."""
    source_type = params.get('type', '')
    script = params.get('script')
    install_dir = params.get('install_dir', './opt')

    if dry_run:
        print(f"  [DRY-RUN] Would build {source_type} from source (script={script})")
        return

    if source_type == 'firedancer_deps':
        deps_script = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'helpers', 'deps.sh')
        if os.path.isfile(deps_script):
            print("[DEPS] Running deps.sh check...")
            result = run_cmd(['bash', deps_script, 'check'])
            if result.returncode != 0:
                print(f"WARNING: deps.sh check failed (exit {result.returncode})")
        else:
            print(f"WARNING: deps.sh not found at {deps_script}, skipping", file=sys.stderr)

    elif source_type == 'kcov':
        print("[BUILD] Building kcov from source...")
        try:
            with tempfile.TemporaryDirectory() as tmpdir:
                result = run_cmd(['git', 'clone', '--depth', '1',
                                  'https://github.com/SimonKagstrom/kcov.git', tmpdir])
                if result.returncode != 0:
                    print("WARNING: kcov clone failed — skipping")
                    return
                build_dir = os.path.join(tmpdir, 'build')
                run_cmd(['cmake', '-S', tmpdir, '-B', build_dir,
                         '-DCMAKE_BUILD_TYPE=Release'])
                run_cmd(['make', '-C', build_dir, '-j', str(os.cpu_count() or 1)])
                run_cmd(['sudo', 'make', '-C', build_dir, 'install'])
        except Exception as e:
            print(f"WARNING: kcov build failed — skipping: {e}", file=sys.stderr)

    elif source_type == 'llama-cpp':
        print("[BUILD] Building llama.cpp from source...")
        try:
            with tempfile.TemporaryDirectory() as tmpdir:
                result = run_cmd(['git', 'clone', '--depth', '1',
                                  'https://github.com/ggerganov/llama.cpp.git', tmpdir])
                if result.returncode != 0:
                    print("WARNING: llama.cpp clone failed — skipping")
                    return
                build_dir = os.path.join(tmpdir, 'build')
                run_cmd(['cmake', '-S', tmpdir, '-B', build_dir,
                         '-DGGML_BLAS=ON',
                         '-DGGML_BLAS_VENDOR=OpenBLAS',
                         '-DGGML_NATIVE=ON'])
                run_cmd(['cmake', '--build', build_dir, '-j', str(os.cpu_count() or 1),
                         '--target', 'llama-server'])
                # llama.cpp installs binaries in-place under build/
        except Exception as e:
            print(f"WARNING: llama.cpp build failed — skipping: {e}", file=sys.stderr)

    elif script:
        # Call a helper script (e.g., install-openssl.sh)
        # Pass platform via env var so helper scripts can use it.
        script_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'helpers', script)
        if os.path.isfile(script_path):
            print(f"[BUILD] Running {script}...")
            env = os.environ.copy()
            env['TK_PLATFORM'] = platform_str
            result = run_cmd(['bash', script_path], env=env)
            if result.returncode != 0:
                print(f"WARNING: {script} failed (exit {result.returncode})", file=sys.stderr)
        else:
            print(f"WARNING: helper script {script_path} not found", file=sys.stderr)


def install_none(tool, params, config, platform_str, dry_run=False):
    """No-op."""
    if dry_run:
        print(f"  [DRY-RUN] Would skip (none)")


# ── Zig Install ────────────────────────────────────────────────────────────────

ZIG_INDEX_URL = "https://ziglang.org/download/index.json"
ZIG_BUILDS_BASE_URL = "https://ziglang.org/builds"
ZIG_MINISIGN_PUBKEY = "RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U"

PLATFORM_TO_ZIG_TARGET = {
    "linux-x86": "x86_64-linux",
    "linux-arm": "aarch64-linux",
    "macos-x86": "x86_64-macos",
    "macos-arm": "aarch64-macos",
    "windows-x86": "x86_64-windows",
    "windows-arm": "aarch64-windows",
}


def _zig_target(platform_str):
    """Convert platform string to Zig release target key."""
    target = PLATFORM_TO_ZIG_TARGET.get(platform_str)
    if target is None:
        print(
            f"ERROR: unknown platform '{platform_str}' for Zig; expected one of: "
            f"{', '.join(PLATFORM_TO_ZIG_TARGET.keys())}",
            file=sys.stderr,
        )
        sys.exit(1)
    return target


def _zig_verify_minisig(archive_path, sig_path, dry_run=False):
    """Verify archive with minisign. Skips with warning if minisign is unavailable."""
    if dry_run:
        print(f"[verify] minisig {archive_path.name} (dry-run)")
        return

    import shutil as _shutil

    def _find_minisign():
        for name in ("minisign", "minisign-verify", "minisig"):
            found = _shutil.which(name)
            if found:
                return found
        return None

    minisign = _find_minisign()
    if not minisign:
        print(
            f"[WARN] minisign binary not found on PATH — skipping signature "
            f"verification for {archive_path.name}",
            file=sys.stderr,
        )
        print(
            "  To enable verification, install minisign: apt install minisign "
            "(Debian/Ubuntu), brew install minisign (macOS), or "
            "winget install jedisct1.minisign (Windows)",
            file=sys.stderr,
        )
        return

    cmd = [minisign, "-V", "-P", ZIG_MINISIGN_PUBKEY, "-x", str(sig_path), "-m", str(archive_path)]
    print(f"[verify] minisig {archive_path.name} ...")
    result = run_cmd(cmd, capture=False)
    if result.returncode != 0:
        print(f"ERROR: minisig verification FAILED for {archive_path.name}", file=sys.stderr)
        sys.exit(1)
    print("[verify] minisig OK")


def install_zig(tool, params, config, platform_str, dry_run=False):
    """Install an official prebuilt Zig release."""
    version_ref = params.get('version_ref')
    install_root = params.get('install_root', os.path.expanduser('~/.local'))
    user_path = params.get('user_path', False)
    version = resolve_version(config, version_ref)
    if not version:
        print("ERROR: no zig version in tool-versions.json", file=sys.stderr)
        sys.exit(1)

    target = _zig_target(platform_str)
    index_url = ZIG_INDEX_URL

    # Resolve archive URL from index
    with urllib.request.urlopen(index_url) as resp:
        index = json.load(resp)
    version_entry = index.get(version)
    if version_entry is None:
        # Check dev build
        ext = ".zip" if target.endswith("-windows") else ".tar.xz"
        dev_url = f"{ZIG_BUILDS_BASE_URL}/zig-{target}-{version}{ext}"
        req = urllib.request.Request(dev_url, method="HEAD")
        try:
            urllib.request.urlopen(req)
            archive_url = dev_url
            shasum = None
        except Exception:
            print(f"ERROR: Zig version '{version}' not found in {index_url} and no dev build at {dev_url}", file=sys.stderr)
            sys.exit(1)
    else:
        target_entry = version_entry.get(target)
        if target_entry is None:
            print(f"ERROR: Zig version '{version}' has no prebuilt archive for target '{target}'", file=sys.stderr)
            sys.exit(1)
        archive_url = target_entry.get("tarball") or target_entry.get("zip")
        if not archive_url:
            print(f"ERROR: Zig version '{version}' target '{target}' is missing an archive URL", file=sys.stderr)
            sys.exit(1)

    if dry_run:
        print(f"  [DRY-RUN] Would install zig {version} (target={target}) to {install_root}")
        return

    # Download
    archive_name = archive_url.rsplit("/", 1)[-1]
    cache_dir = Path(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache"))) / "zig" / "archives"
    archive_path = cache_dir / archive_name
    sig_path = cache_dir / f"{archive_name}.minisig"

    print(f"[download] {archive_name}")
    _download_file(archive_url, archive_path, dry_run=False)

    # Minisign verification
    sig_url = f"{archive_url}.minisig"
    sig_exists = False
    try:
        req = urllib.request.Request(sig_url, method="HEAD")
        urllib.request.urlopen(req)
        sig_exists = True
    except Exception:
        pass

    if sig_exists:
        _download_file(sig_url, sig_path, dry_run=False)
        _zig_verify_minisig(archive_path, sig_path, dry_run=False)
    else:
        print(f"ERROR: required minisig signature not found at {sig_url}", file=sys.stderr)
        sys.exit(1)

    # Extract
    extract_root = cache_dir / "extract" / f"{version}-{target}"
    if extract_root.exists():
        shutil.rmtree(extract_root)
    extract_root.mkdir(parents=True, exist_ok=True)

    if archive_name.endswith(".zip"):
        with zipfile.ZipFile(archive_path) as zf:
            zf.extractall(extract_root)
    else:
        with tarfile.open(archive_path, "r:xz") as tf:
            tf.extractall(extract_root)

    # Locate extracted directory
    children = [p for p in extract_root.iterdir() if p.is_dir()]
    if len(children) != 1:
        print(f"ERROR: expected exactly one extracted directory in {extract_root}, found {len(children)}", file=sys.stderr)
        sys.exit(1)
    source_dir = children[0]

    # Install
    install_dir = Path(install_root) / source_dir.name
    if install_dir.exists():
        shutil.rmtree(install_dir)
    install_dir.mkdir(parents=True, exist_ok=True)
    shutil.copytree(source_dir, install_dir)
    print(f"[install] zig -> {install_dir}")

    # PATH handling
    bin_dir = str(install_dir / "zig")
    if platform_str.startswith("windows"):
        # GitHub Actions PATH
        gh_path = os.environ.get("GITHUB_PATH")
        if gh_path:
            with open(gh_path, "a") as fh:
                fh.write(bin_dir + os.linesep)
            print(f"[github-path] {bin_dir}")
        # Windows user PATH
        if user_path:
            import subprocess as _sub
            ps = (
                f"$zigDir = '{bin_dir}'\n"
                "$current = [Environment]::GetEnvironmentVariable('Path', 'User')\n"
                "$parts = @()\n"
                "if ($current) { $parts = $current -split ';' | Where-Object { $_ -and ($_ -ne $zigDir) } }\n"
                "$new = ($zigDir + ';' + ($parts -join ';')).TrimEnd(';')\n"
                "[Environment]::SetEnvironmentVariable('Path', $new, 'User')\n"
            )
            _sub.run(["powershell.exe", "-NoProfile", "-Command", ps], check=True)
            print(f"[user-path] prepend {bin_dir}")
    else:
        # GitHub Actions PATH
        gh_path = os.environ.get("GITHUB_PATH")
        if gh_path:
            with open(gh_path, "a") as fh:
                fh.write(bin_dir + os.linesep)
            print(f"[github-path] {bin_dir}")
        # Posix: print activation hint
        if not gh_path:
            print(f"[activation] add Zig to your shell PATH with:")
            print(f'  export PATH="{bin_dir}:$PATH"')

    print(f"[done] zig version={version} target={target} install_dir={install_dir}")


# ── Dispatch ─────────────────────────────────────────────────────────────────

INSTALL_METHODS = {
    'apt': install_apt,
    'brew': install_brew,
    'winget': install_winget,
    'pip': install_pip,
    'pipx': install_pipx,
    'go_install': install_go_install,
    'github_release': install_github_release,
    'binary_download': install_binary_download,
    'python_script': install_python_script,
    'build_from_source': install_build_from_source,
    'install_zig': install_zig,
    'none': install_none,
}


def install_tool(tool, config, platform_str, dry_run=False):
    """Install a single tool using its configured method."""
    name = tool['name']
    method = tool['install_method']

    # Idempotency check
    check = tool.get('idempotent_check', '')
    if check and idempotent_check(check):
        print(f"[OK] {name} already installed")
        return

    print(f"[INSTALL] {name} (method={method}, category={tool.get('category', '?')})")

    if dry_run:
        print(f"  [DRY-RUN] Would install {name} via {method}")
        return

    install_fn = INSTALL_METHODS.get(method)
    if install_fn is None:
        print(f"ERROR: unknown install_method '{method}' for {name}", file=sys.stderr)
        sys.exit(1)

    install_fn(tool, tool.get('parameters', {}), config, platform_str, dry_run=False)


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description='CI tool orchestrator')
    parser.add_argument('categories', nargs='?', help='Comma-separated category list')
    parser.add_argument('--deps', help='Show resolved dependency graph for a category')
    parser.add_argument('--list', help='List all tools in a category')
    parser.add_argument('--dry-run', action='store_true', help='Preview without installing')
    parser.add_argument('--platform', help='Platform string from contrib/platform.sh (e.g. linux-x86, macos-arm)')

    args = parser.parse_args()

    if args.deps:
        config = load_config()
        cats = resolve_deps([args.deps], config['dependencies'])
        print(f"Dependencies for '{args.deps}': {', '.join(cats)}")
        return

    if args.list:
        config = load_config()
        cat_config = config['categories']
        tools_config = config['tools']
        for t in cat_config.get(args.list, {}).get('tools', []):
            print(f"  {t}")
        return

    if not args.categories:
        parser.print_help()
        sys.exit(1)

    config = load_config()
    requested = [c.strip() for c in args.categories.split(',')]

    # Resolve dependencies
    resolved = resolve_deps(requested, config['dependencies'])
    print(f"Resolved categories: {', '.join(resolved)}")

    # Determine platform: use --platform arg, or detect via platform.sh
    if args.platform:
        plat = args.platform
    else:
        try:
            # platform.sh lives at <repo_root>/contrib/platform.sh
            repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
            plat = subprocess.check_output(
                ['bash', 'contrib/platform.sh', 'platform'],
                stderr=subprocess.DEVNULL,
                cwd=repo_root,
            ).decode().strip()
        except Exception:
            print("ERROR: could not detect platform. Use --platform linux-x86 etc.", file=sys.stderr)
            sys.exit(1)
    print(f"Platform: {plat}")

    # Collect tools
    tools = collect_tools(resolved, config['categories'], config['tools'])

    # Filter by platform
    tools = [t for t in tools if matches_platform(t, plat)]
    print(f"Platform: {plat}, tools to install: {len(tools)}")

    # Install each tool
    for tool in tools:
        install_tool(tool, config, plat, dry_run=args.dry_run)

    if not args.dry_run:
        print(f"\n[COMPLETE] Installation finished (platform={plat})")
    else:
        print(f"\n[DRY-RUN] Would install {len(tools)} tools on {plat}")


if __name__ == '__main__':
    main()
