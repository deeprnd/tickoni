"""Abstract base class and Template Method skeleton for install strategies."""
from abc import ABC, abstractmethod
import os
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path


def _download_file(url, dest, dry_run=False):
    """Download a file from url to dest, with retries."""
    if dry_run:
        print(f"[download] {url} -> {dest} (dry-run)")
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    attempts = 0
    while attempts < 3:
        result = _run_cmd(['curl', '-sSfL', '--retry', '3', '-o', str(dest), url])
        if result.returncode == 0 and dest.is_file() and dest.stat().st_size > 0:
            return
        attempts += 1
    print(f"ERROR: download failed for {url}", file=sys.stderr)
    sys.exit(1)


def _activate_path(bin_dirs):
    """Put *bin_dirs* on PATH for this process, ``$GITHUB_PATH``, and the shell.

    Toolchains installed outside a directory that is already on PATH (Go under
    ``/usr/local/go/bin``, ``go install`` binaries under ``~/go/bin``) must be
    reachable by later tools in this same orchestrator run, by subsequent CI
    steps (via ``$GITHUB_PATH``), and by an interactive developer (printed
    activation line when there is no ``$GITHUB_PATH``).
    """
    gh_path = os.environ.get('GITHUB_PATH')
    for raw in bin_dirs:
        bin_dir = os.path.expanduser(os.path.expandvars(raw))
        if bin_dir not in os.environ.get('PATH', '').split(os.pathsep):
            os.environ['PATH'] = f"{bin_dir}{os.pathsep}{os.environ.get('PATH', '')}"
        if gh_path:
            try:
                with open(gh_path) as fh:
                    already = any(line.strip() == bin_dir for line in fh)
            except OSError:
                already = False
            if not already:
                with open(gh_path, 'a') as fh:
                    fh.write(bin_dir + os.linesep)
                print(f"[github-path] {bin_dir}")
        else:
            print(f'[activation] add to PATH with:\n  export PATH="{bin_dir}:$PATH"')


def _log_version(tool_name, pkg_name):
    """Log the installed version of a tool after installation.

    Shared by the apt and brew strategies; only a handful of toolchain tools
    are mapped, everything else is a silent no-op.
    """
    version_map = {
        'gcc': 'gcc',
        'clang-llvm': 'clang',
        'make': 'make',
        'cmake': 'cmake',
    }
    binary = version_map.get(tool_name)
    if not binary:
        return
    try:
        result = subprocess.run(
            [binary, '--version'],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            print(f"[VERSION] {binary}: {result.stdout.splitlines()[0].strip()}")
    except Exception:
        pass


def _run_cmd(cmd, capture=True, shell=False, **kwargs):
    """Run a command and print its output."""
    cmd = [str(c) for c in cmd]
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


class InstallStrategy(ABC):
    """Abstract base class for install strategies."""

    @abstractmethod
    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        """Install the tool using this strategy."""
        ...


class DownloadInstallStrategy(InstallStrategy):
    """Template Method base class for archive-based installs."""

    @abstractmethod
    def _resolve_url(self, tool: dict, config: dict, platform_str: str) -> tuple[str, str, str, bool]:
        """Resolve archive URL, version, pattern, and checksum flag.

        Returns (download_url, version, pattern, verify_checksum).
        """
        ...

    def _find_binary(self, tmpdir: str, bin_name: str) -> str | None:
        """Walk extracted tree to find a binary by name."""
        for root, dirs, files in __import__('os').walk(tmpdir):
            for f in files:
                if f == bin_name:
                    return __import__('os').path.join(root, f)
            # Early exit if found
            if __import__('os').path.join(root, bin_name) in [
                __import__('os').path.join(root, x) for x in files
            ]:
                return __import__('os').path.join(root, bin_name)
        return None

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        download_url, version, pattern, verify_checksum = self._resolve_url(tool, config, platform_str)

        # Already handled by a specialized handler in _resolve_url (e.g. cbmc_deb)
        if not download_url:
            return

        bin_name = tool['parameters'].get('bin_name', 'downloaded_binary')

        if dry_run:
            print(f"  [DRY-RUN] Would download v{version}/{pattern}")
            return

        with tempfile.TemporaryDirectory() as tmpdir:
            archive_path = Path(tmpdir) / pattern
            self._download_file(download_url, archive_path)
            if not archive_path.exists() or archive_path.stat().st_size == 0:
                print(f"ERROR: download failed for {download_url}", file=sys.stderr)
                sys.exit(1)

            self._verify_checksum(tool, config, archive_path, verify_checksum)
            self._extract(archive_path, tmpdir)
            self._install_binary(tmpdir, bin_name)

    def _download_file(self, url: str, dest: Path) -> None:
        _download_file(url, dest, dry_run=False)

    def _verify_checksum(self, tool: dict, config: dict, archive_path: Path, verify: bool) -> None:
        if not verify:
            return
        params = tool.get('parameters', {})
        owner = params.get('owner')
        repo = params.get('repo')
        version = tool.get('_version', '')
        if owner and repo and version:
            cs_pattern = archive_path.name.replace('.tar.gz', '')
            checksum_url = f"https://github.com/{owner}/{repo}/releases/download/v{version}/{cs_pattern}_checksums.txt"
            result = _run_cmd(['curl', '-sSfL', checksum_url])
            if result.returncode == 0 and result.stdout.strip():
                import hashlib
                actual = hashlib.sha256(archive_path.read_bytes()).hexdigest()
                for line in result.stdout.strip().split('\n'):
                    parts = line.strip().split()
                    if len(parts) >= 2:
                        expected, cs_file = parts[0], parts[1].lstrip('*')
                        if cs_file == archive_path.name or archive_path.name in cs_file:
                            if expected != actual:
                                print(f"ERROR: checksum mismatch for {archive_path.name}", file=sys.stderr)
                                sys.exit(1)
                            print(f"  Checksum verified")
                            break

    def _extract(self, archive_path: Path, tmpdir: str) -> None:
        name = archive_path.name
        if name.endswith(('.tar.gz', '.tgz')):
            _run_cmd(['tar', '-xzf', archive_path, '-C', tmpdir])
        elif name.endswith('.zip'):
            _run_cmd(['unzip', '-o', archive_path, '-d', tmpdir])
        else:
            print(f"ERROR: unsupported archive format: {name}", file=sys.stderr)
            sys.exit(1)

    def _install_binary(self, tmpdir: str, bin_name: str) -> None:
        bin_path = self._find_binary(tmpdir, bin_name)
        if bin_path and __import__('os').path.isfile(bin_path):
            print(f"  Installing {bin_name} to /usr/local/bin/")
            _run_cmd(['sudo', 'install', '-m', '755', bin_path, f'/usr/local/bin/{bin_name}'])
        else:
            print(f"WARNING: could not find {bin_name} in archive", file=sys.stderr)
