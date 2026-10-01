"""Regression tests for Zig build configuration wiring."""

import os
from pathlib import Path
import subprocess

import pytest


REPO_ROOT = Path(__file__).resolve().parents[2]


def test_c_compile_check_uses_complete_platform_shim_flags():
    helpers = (REPO_ROOT / "build-lib" / "lib" / "helpers.zig").read_text(
        encoding="utf-8"
    )

    assert (
        'std.mem.join(b.allocator, " ", shims.shimCFlagsFor(target.result))'
        in helpers
    )
    assert "shims.shimCFlagsFor(target.result)[0]" not in helpers
    assert helpers.count("shim_c_flags") >= 3


@pytest.mark.skipif(os.name != "nt", reason="requires a native Windows path")
def test_build_accepts_windows_absolute_fd_library_path():
    fd_lib_dir = REPO_ROOT / "build" / "fd-tickoni-fd" / "lib"

    result = subprocess.run(
        [
            "zig",
            "build",
            "-Dtest=true",
            f"-Dfd-lib-dir={fd_lib_dir}",
            "--help",
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, result.stdout + result.stderr
