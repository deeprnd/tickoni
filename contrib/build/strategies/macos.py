#!/usr/bin/env python3
"""macOS platform strategy for Firedancer build."""

import os
import re
import subprocess


def resolve_make() -> str:
    """Resolve GNU make on macOS — prefer Homebrew gmake.

    Firedancer's makefiles use the ``$(file ...)`` builtin, added in GNU
    Make 4.0.  macOS ships ``/usr/bin/make`` (GNU Make 3.81), which would
    silently drop ``fd_version.o`` and fail ``libfd_util.a``; reject it so
    the failure is a clear message instead.
    """
    if (make := os.environ.get("JUST_GMAKE")) and os.path.isfile(make):
        return make
    if _which("gmake") and _is_gnu_make_4plus("gmake"):
        return "gmake"
    # Homebrew keg-only llvm / make — try common prefixes
    for prefix in _homebrew_prefixes():
        bin_dir = os.path.join(prefix, "bin")
        for name in ("gmake", "make"):
            path = os.path.join(bin_dir, name)
            if os.path.isfile(path) and os.access(path, os.X_OK) \
                    and _is_gnu_make_4plus(path):
                return path
    if _which("make") and _is_gnu_make_4plus("make"):
        return "make"
    raise RuntimeError(
        "cannot find GNU Make >= 4.0 on macOS (system /usr/bin/make is 3.81) — "
        "run: just setup-build-macos-arm  (installs Homebrew gmake)"
    )


def _is_gnu_make_4plus(make: str) -> bool:
    """True if *make* is GNU Make 4.0 or newer."""
    try:
        out = subprocess.check_output([make, "--version"], text=True,
                                      stderr=subprocess.DEVNULL)
    except (subprocess.CalledProcessError, FileNotFoundError, OSError):
        return False
    m = re.search(r"GNU Make (\d+)", out)
    return bool(m) and int(m.group(1)) >= 4


def resolve_llvm_ar() -> str:
    """Resolve llvm-ar on macOS (Homebrew keg-only formula).

    Homebrew's llvm formula is keg-only — not symlinked into PATH.
    We check the Homebrew prefix directly instead of relying on PATH.
    """
    for prefix in _homebrew_prefixes():
        llvm_bin = os.path.join(prefix, "opt", "llvm", "bin")
        ar_path = os.path.join(llvm_bin, "llvm-ar")
        if os.path.isfile(ar_path) and os.access(ar_path, os.X_OK):
            return ar_path
    raise RuntimeError(
        "cannot find llvm-ar on macOS — run: just setup-fd-deps-macos-x86"
    )


def resolve_cc(platform_name: str, compiler: str) -> str:
    """Return compiler path, resolving Homebrew keg-only clang."""
    if compiler.lower() == "clang":
        # Homebrew's llvm is keg-only — not symlinked into PATH.
        # Resolve to the actual Homebrew llvm clang binary.
        for prefix in _homebrew_prefixes():
            clang_path = os.path.join(prefix, "opt", "llvm", "bin", "clang")
            if os.path.isfile(clang_path) and os.access(clang_path, os.X_OK):
                return clang_path
        # Direct Homebrew paths as fallback
        for path in ("/opt/homebrew/opt/llvm/bin/clang",
                     "/usr/local/opt/llvm/bin/clang"):
            if os.path.isfile(path) and os.access(path, os.X_OK):
                return path
        # Fall back to PATH resolution (Apple clang)
    return compiler


def nproc() -> int:
    """Return CPU count (sysctl on macOS, no nproc)."""
    try:
        return int(subprocess.check_output(
            ["sysctl", "-n", "hw.ncpu"], text=True).strip())
    except (subprocess.CalledProcessError, FileNotFoundError):
        return 1


def _homebrew_prefixes() -> list[str]:
    """Return Homebrew prefix paths for this machine."""
    prefixes = []
    try:
        out = subprocess.check_output(["brew", "--prefix", "llvm"],
                                      text=True, stderr=subprocess.DEVNULL)
        prefixes.append(out.strip())
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    try:
        out = subprocess.check_output(["brew", "--prefix"],
                                      text=True, stderr=subprocess.DEVNULL)
        prefixes.append(out.strip())
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    return prefixes


def _which(cmd: str) -> str | None:
    import shutil
    return shutil.which(cmd)
