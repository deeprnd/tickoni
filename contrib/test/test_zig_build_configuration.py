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


def test_linux_x86_build_and_test_recipes_pin_the_same_zig_cpu():
    common = (REPO_ROOT / "just" / "common.just").read_text(encoding="utf-8")
    linux_build = (REPO_ROOT / "just" / "build" / "linux.just").read_text(
        encoding="utf-8"
    )
    integration = (
        REPO_ROOT / "just" / "test" / "integration.just"
    ).read_text(encoding="utf-8")
    workflow = (REPO_ROOT / ".github" / "workflows" / "_ci-build.yml").read_text(
        encoding="utf-8"
    )

    assert 'zig_linux_x86_cpu := "-Dcpu=haswell"' in common
    assert linux_build.count("{{ zig_linux_x86_cpu }}") >= 3
    assert "{{ zig_linux_x86_cpu }}" in integration
    assert "zig build install --prefix build/zig-out" not in workflow


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
