"""Regression tests for portable GNU make command construction."""

import sys
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from contrib.build.orchestrator import make_assignment, make_path


def test_make_path_uses_forward_slashes():
    assert make_path(r"build\fd-tickoni-fd\lib\libfd_tango.a") == (
        "build/fd-tickoni-fd/lib/libfd_tango.a"
    )


def test_windows_compiler_assignment_quotes_paths_with_spaces():
    compiler = "/c/Program Files/LLVM/bin/clang.EXE"
    assert make_assignment("CC", compiler, "windows-arm") == (
        'CC="/c/Program Files/LLVM/bin/clang.EXE"'
    )


def test_non_windows_compiler_assignment_is_not_quoted():
    compiler = "/opt/llvm/bin/clang"
    assert make_assignment("CC", compiler, "linux-x86") == (
        "CC=/opt/llvm/bin/clang"
    )


def test_windows_make_profile_detects_absolute_clang_path():
    profile = Path(__file__).resolve().parents[2] / "config/machine/tickoni_fd.mk"
    text = profile.read_text()
    assert "ifneq (,$(findstring clang,$(CC)))" in text
    assert "ifeq ($(CC),clang)" not in text