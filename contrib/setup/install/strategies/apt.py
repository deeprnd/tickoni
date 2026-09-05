"""apt-get install strategy (Linux)."""
import re
import subprocess
import sys
from ..base import InstallStrategy, _log_version
from .. import register


def _is_versioned_package(pkg_name):
    """Check if a package name already contains a version number.

    Examples:
        'clang-18' → True
        'llvm-18' → True
        'gcc' → False
        'cmake' → False
        'python3' → False (the '3' is part of the name, not a version suffix)
    """
    # Match package names ending with -<digits> where digits >= 2 chars
    # This avoids matching 'python3', 'gcc-12-base', etc.
    return bool(re.search(r'-\d{2,}$', pkg_name))


def _resolve_version(tool_name, platform_str, config):
    """Resolve a platform-scoped version from config.versions.<tool_name>.
    Returns the version string or None if not found."""
    versions = config.get('versions', {})
    tool_versions = versions.get(tool_name, {})
    if not isinstance(tool_versions, dict):
        return None
    raw = tool_versions.get(platform_str)
    if raw is None:
        return None
    return str(raw)


def _apt_install(pkg_name):
    """Install one package, trying non-interactive sudo first."""
    print(f"[APT] Installing {pkg_name}...")
    # Try sudo -n first (non-interactive). If sudo requires a password,
    # fall back to apt-get without sudo (works for already-downloaded
    # packages or if the user has passwordless sudo).
    result = subprocess.run([
        'sudo', '-n', 'apt-get', 'install', '-y', '--no-install-recommends', pkg_name
    ], capture_output=True, text=True)
    if result.returncode != 0 and 'password' in (result.stderr or '').lower():
        print("  [WARN] sudo -n failed (password required), retrying without sudo")
        result = subprocess.run([
            'apt-get', 'install', '-y', '--no-install-recommends', pkg_name
        ], capture_output=True, text=True)
    return result


@register('apt')
class AptInstallStrategy(InstallStrategy):
    """Install via apt-get (Linux).

    Version resolution:
    - For tools with platform-scoped versions in config.versions (e.g. gcc),
      the package name is constructed as <name>-<version>.
    - Packages that already contain a version number (e.g. clang-18, llvm-18)
      are left as-is — the version is baked into the package name.
    - If the versioned package fails to install, we fall back to the unversioned
      package name.
    """

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        params = tool.get('parameters', {})
        pkg = params.get('package', '')
        packages = params.get('packages', [])
        if not isinstance(packages, list):
            packages = [pkg]
        # Single-package tools (e.g. gcc) have 'package' but no 'packages' key,
        # so packages=[] here. Fall back to the single package name.
        if not packages and pkg:
            packages = [pkg]

        if dry_run:
            for p in packages:
                print(f"  [DRY-RUN] Would apt-get install {p}")
            return

        tool_name = tool.get('name', '')

        from config import _apt_update
        _apt_update()
        for pkg_name in packages:
            # Determine final package name with version if applicable
            if _is_versioned_package(pkg_name):
                # Already versioned (e.g. clang-18, llvm-18) — use as-is
                final_pkg = pkg_name
            else:
                # Check for platform-scoped version (e.g. gcc: linux-x86=12, linux-arm=14)
                versioned_pkg = _resolve_version(tool_name, platform_str, config)
                if versioned_pkg:
                    final_pkg = f"{pkg_name}-{versioned_pkg}"
                else:
                    final_pkg = pkg_name

            result = _apt_install(final_pkg)
            if result.returncode != 0:
                # Fallback: if versioned install fails, try without version
                if final_pkg != pkg_name:
                    print(f"  [WARN] {final_pkg} not available, trying {pkg_name}",
                          file=sys.stderr)
                    result = _apt_install(pkg_name)
                    if result.returncode != 0:
                        print(f"ERROR: apt install failed for {pkg_name}",
                              file=sys.stderr)
                        sys.exit(1)
                else:
                    print(f"ERROR: apt install failed for {pkg_name}",
                          file=sys.stderr)
                    sys.exit(1)
            _log_version(tool_name, final_pkg)
