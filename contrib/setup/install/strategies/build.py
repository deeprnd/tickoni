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
        elif script:
            self._build_script(script, platform_str)

    def _build_firedancer_deps(self):
        script_dir = os.path.dirname(os.path.abspath(__file__))
        # __file__ is contrib/setup/install/strategies/build.py;
        # helpers/ lives at contrib/setup/helpers/deps.sh (2 levels up from strategies/)
        deps_script = os.path.join(script_dir, '..', '..', 'helpers', 'deps.sh')
        deps_script = os.path.normpath(deps_script)
        if not os.path.isfile(deps_script):
            print(f"WARNING: deps.sh not found at {deps_script}, skipping", file=sys.stderr)
            return

        # Fix ownership if ./opt is owned by root but we're not root.
        prefix = './opt'
        if os.path.isdir(prefix):
            stat = os.stat(prefix)
            if stat.st_uid == 0 and os.geteuid() != 0:
                import grp
                try:
                    user = os.environ.get('USER', os.environ.get('LOGNAME', ''))
                    gid = grp.getpwnam(user).pw_gid if user else os.getgid()
                    print(f"[DEPS] Fixing ownership of {prefix} from root to {user} (gid={gid})")
                    os.chown(prefix, -1, gid)
                except (KeyError, PermissionError) as e:
                    print(f"[DEPS] Failed to fix {prefix} ownership: {e}, proceeding anyway.")

        env = os.environ.copy()
        env['FD_AUTO_INSTALL_PACKAGES'] = '1'

        print("[DEPS] Running deps.sh check...")
        check_result = subprocess.run(
            ['bash', deps_script, 'check'],
            capture_output=True, text=True, env=env,
        )
        if check_result.returncode != 0:
            print(f"WARNING: deps.sh check failed (exit {check_result.returncode})")
            output = (check_result.stdout or '') + (check_result.stderr or '')
            if 'missing system packages' in output:
                print("NOTE: snappy/rockdb require system packages not auto-installed; skipping.")
            return

        print("[DEPS] Running deps.sh install...")
        install_result = subprocess.run(
            ['bash', deps_script, 'install'],
            capture_output=True, text=True, env=env,
        )
        if install_result.returncode != 0:
            print(f"WARNING: deps.sh install failed (exit {install_result.returncode})")
            print(install_result.stderr[-1000:] if install_result.stderr else "(no stderr)")
        else:
            print("[DEPS] Successfully built and installed snappy + rockdb")

    def _build_kcov(self):
        print("[BUILD] Building kcov from source...")
        try:
            local_bin = os.path.expanduser('~/.local/bin')
            os.makedirs(local_bin, exist_ok=True)
            with tempfile.TemporaryDirectory() as tmpdir:
                result = subprocess.run(
                    ['git', 'clone', '--depth', '1', 'https://github.com/SimonKagstrom/kcov.git', tmpdir],
                    capture_output=True, text=True,
                )
                if result.returncode != 0:
                    print("WARNING: kcov clone failed — skipping")
                    return
                build_dir = os.path.join(tmpdir, 'build')
                subprocess.run(
                    ['cmake', '-S', tmpdir, '-B', build_dir, '-DCMAKE_BUILD_TYPE=Release',
                     f'-DCMAKE_INSTALL_PREFIX={local_bin}/..'],
                    check=True,
                )
                subprocess.run(['make', '-C', build_dir, '-j', str(os.cpu_count() or 1)], check=True)
                subprocess.run(['make', '-C', build_dir, 'install'], check=True)
                # Ensure ~/.local/bin is on PATH
                if local_bin not in os.environ.get('PATH', '').split(os.pathsep):
                    os.environ['PATH'] = local_bin + os.pathsep + os.environ.get('PATH', '')
        except Exception as e:
            print(f"WARNING: kcov build failed — skipping: {e}", file=sys.stderr)

    def _build_script(self, script, platform_str):
        script_dir = os.path.dirname(os.path.abspath(__file__))
        # __file__ is contrib/setup/install/strategies/build.py;
        # helpers/ lives at contrib/setup/helpers/<script> (2 levels up from strategies/)
        script_path = os.path.join(script_dir, '..', '..', 'helpers', script)
        script_path = os.path.normpath(script_path)
        if os.path.isfile(script_path):
            print(f"[BUILD] Running {script}...")
            env = os.environ.copy()
            env['TK_PLATFORM'] = platform_str
            result = subprocess.run(['bash', script_path], env=env, capture_output=True, text=True)
            if result.returncode != 0:
                print(f"WARNING: {script} failed (exit {result.returncode})")
        else:
            print(f"WARNING: helper script {script_path} not found", file=sys.stderr)
