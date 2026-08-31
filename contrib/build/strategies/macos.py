#!/usr/bin/env python3
"""macOS platform strategy for Firedancer build."""

import os
import subprocess


def resolve_make() -> str:
    """Resolve GNU make on macOS — prefer Homebrew gmake."""
    if (make := os.environ.get("JUST_GMAKE")) and os.path.isfile(make):
        return make
    if _which("gmake"):
        return "gmake"
    # Homebrew keg-only llvm / make — try common prefixes
    for prefix in _homebrew_prefixes():
        bin_dir = os.path.join(prefix, "bin")
        for name in ("gmake", "make"):
            path = os.path.join(bin_dir, name)
            if os.path.isfile(path) and os.access(path, os.X_OK):
                return path
    if _which("make"):
        return "make"
    raise RuntimeError("cannot find GNU make on macOS")


def resolve_llvm_ar() -> str:
    """Resolve llvm-ar on macOS (Homebrew keg-only formula).

    Homebrew's llvm formula does NOT symlink llvm-ar into the Homebrew bin
    prefix — only under opt/Cellar paths.
    """
    if (llvm_ar := _which("llvm-ar")):
        return llvm_ar
    for prefix in _homebrew_prefixes():
        llvm_bin = os.path.join(prefix, "opt", "llvm", "bin")
        ar_path = os.path.join(llvm_bin, "llvm-ar")
        if os.path.isfile(ar_path) and os.access(ar_path, os.X_OK):
            return ar_path
    # Direct Homebrew paths
    for path in ("/opt/homebrew/opt/llvm/bin/llvm-ar",
                 "/usr/local/opt/llvm/bin/llvm-ar"):
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    raise RuntimeError(
        "cannot find llvm-ar on macOS — run: brew install llvm"
    )


def resolve_cc(platform_name: str, compiler: str) -> str:
    """Return compiler path."""
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
