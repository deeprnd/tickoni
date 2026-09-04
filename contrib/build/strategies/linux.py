#!/usr/bin/env python3
"""Linux platform strategy for Firedancer build."""

import os
import subprocess


def resolve_make() -> str:
    """Resolve GNU make on Linux."""
    if (make := os.environ.get("JUST_GMAKE")) and os.path.isfile(make):
        return make
    if _which("gmake"):
        return "gmake"
    if _which("make"):
        return "make"
    raise RuntimeError("cannot find GNU make")


def resolve_ar() -> str:
    """ar is standard on Linux; no llvm-ar needed."""
    return "ar"


def resolve_cc(platform_name: str, compiler: str) -> str:
    """Return compiler path. On Linux the compiler name is used directly."""
    return compiler


def nproc() -> int:
    """Return CPU count."""
    try:
        return int(subprocess.check_output(["nproc"], text=True).strip())
    except (subprocess.CalledProcessError, FileNotFoundError):
        return 1


def _which(cmd: str) -> str | None:
    """Return full path of executable or None."""
    import shutil
    return shutil.which(cmd)
