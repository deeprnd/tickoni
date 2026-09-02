"""Llama.cpp build strategy — cross-platform clone + cmake + build (CPU + OpenBLAS)."""
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


def _is_windows():
    """Detect Windows (native, MSYS2, Cygwin, or WSL on Windows)."""
    # Use sys.platform instead of platform.system() to avoid stdlib platform
    # module corruption on Ubuntu (apport calls platform.freedesktop_os_release()
    # which doesn't exist in Python 3.12).
    return sys.platform in ('win32', 'cygwin')


def _resolve_llama_dir(tool: dict, config: dict) -> str:
    """Resolve the llama.cpp clone directory.

    Resolution order:
    1. TK_LLAMA_CPP_DIR env var
    2. parameters.clone_dir from tool-versions.json
    3. Default: ~/work/models/llama.cpp (~/work/git/llama.cpp on Windows)
    """
    env_dir = os.environ.get('TK_LLAMA_CPP_DIR')
    if env_dir:
        return _expand_home(env_dir)

    clone_dir = tool.get('parameters', {}).get('clone_dir')
    if clone_dir:
        return _expand_home(clone_dir)

    default = os.path.join(os.environ.get('HOME', os.path.expanduser('~')), 'work', 'models', 'llama.cpp')
    if _is_windows():
        default = os.path.join(os.environ.get('HOME', os.path.expanduser('~')), 'work', 'git', 'llama.cpp')
    return default


@register('llama_cpp_build')
class LlamaCppBuildStrategy(InstallStrategy):
    """Clone, configure, and build llama.cpp (CPU + OpenBLAS only)."""

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        llama_dir = _resolve_llama_dir(tool, config)
        server_name = 'llama-server.exe' if _is_windows() else 'llama-server'
        server_bin = os.path.join(llama_dir, server_name)

        # Check if already built
        if os.path.isfile(server_bin) and os.access(server_bin, os.X_OK):
            print(f"llama.cpp already built: {llama_dir}")
            return

        if dry_run:
            print(f"  [DRY-RUN] Would build llama.cpp into {llama_dir}")
            return

        # Verify build tools
        for cmd in ['git', 'cmake']:
            if not shutil.which(cmd):
                print(f"ERROR: {cmd} is required but not found in PATH", file=sys.stderr)
                sys.exit(1)

        if _is_windows():
            if not shutil.which('ninja'):
                print("ERROR: ninja is required for Windows llama.cpp build but not found in PATH", file=sys.stderr)
                sys.exit(1)

        # Clone if needed
        if not os.path.isdir(llama_dir):
            clone_url = tool.get('parameters', {}).get(
                'clone_url', 'https://github.com/ggml-org/llama.cpp'
            )
            print(f"cloning llama.cpp into {llama_dir}")
            result = subprocess.run(
                ['git', 'clone', clone_url, llama_dir],
                capture_output=True, text=True
            )
            if result.returncode != 0:
                print(f"ERROR: git clone failed: {result.stderr}", file=sys.stderr)
                sys.exit(1)
        else:
            print(f"directory exists, skipping clone: {llama_dir}")

        # Ensure OpenBLAS is available
        self._ensure_openblas(tool, platform_str)

        # Build
        self._build(llama_dir, _is_windows())

        # Verify binary
        if not os.path.isfile(server_bin):
            print(f"build finished but {server_name} is missing: {server_bin}", file=sys.stderr)
            sys.exit(1)

        print(f"llama.cpp built: {llama_dir}")

    def _ensure_openblas(self, tool: dict, platform_str: str) -> None:
        """Ensure OpenBLAS is installed on the system."""
        # macOS — brew
        if 'macos' in platform_str:
            result = subprocess.run(
                ['brew', 'list', 'openblas'],
                capture_output=True
            )
            if result.returncode != 0:
                print("Installing OpenBLAS via brew...")
                result = subprocess.run(
                    ['brew', 'install', 'openblas'],
                    capture_output=True, text=True
                )
                if result.returncode != 0:
                    print(f"ERROR: brew install openblas failed: {result.stderr}", file=sys.stderr)
                    sys.exit(1)
            # Set PKG_CONFIG_PATH so cmake's FindBLAS can locate the pkg-config file
            openblas_prefix = subprocess.run(
                ['brew', '--prefix', 'openblas'],
                capture_output=True, text=True
            )
            if openblas_prefix.returncode == 0:
                prefix = openblas_prefix.stdout.strip()
                pc_path = os.path.join(prefix, 'lib', 'pkgconfig')
                existing = os.environ.get('PKG_CONFIG_PATH', '')
                if pc_path not in existing:
                    os.environ['PKG_CONFIG_PATH'] = pc_path + os.pathsep + existing if existing else pc_path
                print(f"Set PKG_CONFIG_PATH={pc_path} for OpenBLAS discovery by cmake")
            return

        # Linux — apt
        pkg = tool.get('parameters', {}).get('openblas_pkg')
        if pkg and 'linux' in platform_str:
            result = subprocess.run(
                ['pkg-config', '--exists', 'openblas'],
                capture_output=True
            )
            if result.returncode != 0:
                print(f"Installing OpenBLAS package: {pkg}")
                subprocess.run(['sudo', 'apt-get', 'update', '-qq'], check=True)
                subprocess.run(
                    ['sudo', 'apt-get', 'install', '-y', '--no-install-recommends', pkg],
                    check=True
                )

    def _build(self, llama_dir: str, is_win: bool) -> None:
        """Run cmake to configure and build llama.cpp."""
        if is_win:
            self._build_windows(llama_dir)
        else:
            self._build_unix(llama_dir)

    def _build_unix(self, llama_dir: str) -> None:
        """Build on Linux/macOS with direct cmake flags."""
        build_dir = os.path.join(llama_dir, 'build')
        os.makedirs(build_dir, exist_ok=True)

        print(f"configuring llama.cpp with cmake (CPU + OpenBLAS)...")
        cmake_args = [
            'cmake', '-B', build_dir, '-S', llama_dir,
            '-DGGML_BLAS=ON',
            '-DGGML_BLAS_VENDOR=OpenBLAS',
            '-DGGML_NATIVE=OFF',
            '-DLLAMA_BUILD_TESTS=OFF',
            '-DLLAMA_BUILD_TOOLS=ON',
            '-DLLAMA_BUILD_SERVER=ON',
            '-DLLAMA_BUILD_APP=OFF',
            '-DLLAMA_BUILD_EXAMPLES=OFF',
        ]
        result = subprocess.run(cmake_args, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"ERROR: cmake configure failed: {result.stderr}", file=sys.stderr)
            sys.exit(1)

        threads = os.cpu_count() or 1
        print(f"building llama.cpp with {threads} threads...")
        result = subprocess.run(
            ['cmake', '--build', build_dir, '--config', 'Release', '-j', str(threads)],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            print(f"ERROR: cmake build failed: {result.stderr}", file=sys.stderr)
            sys.exit(1)

        # Copy binaries to llama_dir root
        bin_src = os.path.join(build_dir, 'bin')
        if os.path.isdir(bin_src):
            for f in os.listdir(bin_src):
                src = os.path.join(bin_src, f)
                dst = os.path.join(llama_dir, f)
                if os.path.isfile(src):
                    shutil.copy2(src, dst)

    def _build_windows(self, llama_dir: str) -> None:
        """Build on Windows using cmake presets."""
        build_dir = os.path.join(llama_dir, 'build-x64-windows-llvm-release')
        os.makedirs(build_dir, exist_ok=True)

        print("configuring llama.cpp with cmake preset (x64-windows-llvm-release)...")
        # cd into llama_dir for cmake preset to work
        orig = os.getcwd()
        try:
            os.chdir(llama_dir)
            result = subprocess.run(
                ['cmake', '--preset', 'x64-windows-llvm-release'],
                capture_output=True, text=True
            )
            if result.returncode != 0:
                print(f"ERROR: cmake preset failed: {result.stderr}", file=sys.stderr)
                sys.exit(1)

            print("building llama.cpp...")
            result = subprocess.run(
                ['cmake', '--build', 'build-x64-windows-llvm-release',
                 '--target', 'llama-server'],
                capture_output=True, text=True
            )
            if result.returncode != 0:
                print(f"ERROR: cmake build failed: {result.stderr}", file=sys.stderr)
                sys.exit(1)

            # Copy binaries to llama_dir root
            bin_src = os.path.join(llama_dir, 'build-x64-windows-llvm-release', 'bin', 'Release')
            if os.path.isdir(bin_src):
                for f in os.listdir(bin_src):
                    src = os.path.join(bin_src, f)
                    dst = os.path.join(llama_dir, f)
                    if os.path.isfile(src):
                        shutil.copy2(src, dst)
            # Also copy DLLs
            for f in os.listdir(bin_src):
                if f.endswith('.dll'):
                    shutil.copy2(os.path.join(bin_src, f), llama_dir)
        finally:
            os.chdir(orig)
