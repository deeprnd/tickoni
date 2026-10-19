"""Shared utilities and pytest hooks for the Tickoni test suite.

Platform detection: all tests should import ``detect_platform`` from this
module rather than calling ``platform.sh`` directly — it centralises the
subprocess call and makes mocking trivial.
"""
from __future__ import annotations

import os
import platform as _platform_module
import subprocess
import sys
from pathlib import Path


# ── Monkey-patch pytest bestrelpath (Windows CI) ──────────────────────

def _patched_bestrelpath(directory: Path, base: Path) -> str:
    try:
        return str(directory.relative_to(base))
    except ValueError:
        return str(directory)


_pytest_pathlib = sys.modules.get("_pytest.pathlib")
if _pytest_pathlib is not None:
    _pytest_pathlib.bestrelpath = _patched_bestrelpath

for _mod_name in ("_pytest.config", "_pytest.terminal"):
    _mod = sys.modules.get(_mod_name)
    if _mod is not None:
        _mod.bestrelpath = _patched_bestrelpath


# ── Platform detection ────────────────────────────────────────────────

def _detect_platform_windows() -> str:
    """Detect Windows platform using Python's platform module."""
    system = "windows"
    machine = _platform_module.machine().lower()
    if "arm" in machine or "aarch64" in machine:
        arch = "arm"
    elif "x86_64" in machine or "amd64" in machine or "x64" in machine:
        arch = "x86"
    else:
        arch = "x86"  # fallback
    return f"{system}-{arch}"


def _detect_platform_posix() -> str:
    """Detect Linux/macOS platform by calling platform.sh."""
    repo_root = Path(__file__).resolve().parent.parent.parent
    result = subprocess.run(
        ["bash", str(repo_root / "contrib" / "platform.sh"), "platform"],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def detect_platform() -> str:
    """Detect current platform.

    Returns a string like 'linux-x86', 'macos-arm', 'windows-x86', etc.
    """
    if sys.platform == "win32":
        return _detect_platform_windows()
    return _detect_platform_posix()
