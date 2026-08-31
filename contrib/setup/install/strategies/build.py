"""Build from source strategy."""
import os
import subprocess
import sys
import tempfile
from ..base import InstallStrategy
from .. import register


@register('build_from_source')
class BuildFromSourceStrategy(InstallStrategy):
    """Build from source."""

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        source_type = tool['parameters'].get('type', '')
        script = tool['parameters'].get('script')
        install_dir = tool['parameters'].get('install_dir', './opt')

        if dry_run:
            print(f"  [DRY-RUN] Would build {source_type} from source (script={script})")
            return

        if source_type == 'firedancer_deps':
            self._build_firedancer_deps()
        elif source_type == 'kcov':
            self._build_kcov()
        elif source_type == 'llama-cpp':
            self._build_llama_cpp()
        elif script:
            self._build_script(script, platform_str)

    def _build_firedancer_deps(self):
        script_dir = os.path.dirname(os.path.abspath(__file__))
        parent_dir = os.path.dirname(os.path.dirname(os.path.dirname(script_dir)))
        deps_script = os.path.join(parent_dir, 'helpers', 'deps.sh')
        if os.path.isfile(deps_script):
            print("[DEPS] Running deps.sh check...")
            result = subprocess.run(['bash', deps_script, 'check'], capture_output=True, text=True)
            if result.returncode != 0:
                print(f"WARNING: deps.sh check failed (exit {result.returncode})")
        else:
            print(f"WARNING: deps.sh not found at {deps_script}, skipping", file=sys.stderr)

    def _build_kcov(self):
        print("[BUILD] Building kcov from source...")
        try:
            with tempfile.TemporaryDirectory() as tmpdir:
                result = subprocess.run(
                    ['git', 'clone', '--depth', '1', 'https://github.com/SimonKagstrom/kcov.git', tmpdir],
                    capture_output=True, text=True,
                )
                if result.returncode != 0:
                    print("WARNING: kcov clone failed — skipping")
                    return
                build_dir = os.path.join(tmpdir, 'build')
                subprocess.run(['cmake', '-S', tmpdir, '-B', build_dir, '-DCMAKE_BUILD_TYPE=Release'], check=True)
                subprocess.run(['make', '-C', build_dir, '-j', str(os.cpu_count() or 1)], check=True)
                subprocess.run(['sudo', 'make', '-C', build_dir, 'install'], check=True)
        except Exception as e:
            print(f"WARNING: kcov build failed — skipping: {e}", file=sys.stderr)

    def _build_llama_cpp(self):
        print("[BUILD] Building llama.cpp from source...")
        try:
            with tempfile.TemporaryDirectory() as tmpdir:
                result = subprocess.run(
                    ['git', 'clone', '--depth', '1', 'https://github.com/ggerganov/llama.cpp.git', tmpdir],
                    capture_output=True, text=True,
                )
                if result.returncode != 0:
                    print("WARNING: llama.cpp clone failed — skipping")
                    return
                build_dir = os.path.join(tmpdir, 'build')
                subprocess.run([
                    'cmake', '-S', tmpdir, '-B', build_dir,
                    '-DGGML_BLAS=ON', '-DGGML_BLAS_VENDOR=OpenBLAS', '-DGGML_NATIVE=ON'
                ], check=True)
                subprocess.run([
                    'cmake', '--build', build_dir, '-j', str(os.cpu_count() or 1),
                    '--target', 'llama-server'
                ], check=True)
        except Exception as e:
            print(f"WARNING: llama.cpp build failed — skipping: {e}", file=sys.stderr)

    def _build_script(self, script, platform_str):
        script_dir = os.path.dirname(os.path.abspath(__file__))
        parent_dir = os.path.dirname(os.path.dirname(script_dir))
        script_path = os.path.join(parent_dir, 'helpers', script)
        if os.path.isfile(script_path):
            print(f"[BUILD] Running {script}...")
            env = os.environ.copy()
            env['TK_PLATFORM'] = platform_str
            result = subprocess.run(['bash', script_path], env=env, capture_output=True, text=True)
            if result.returncode != 0:
                print(f"WARNING: {script} failed (exit {result.returncode})")
        else:
            print(f"WARNING: helper script {script_path} not found", file=sys.stderr)
