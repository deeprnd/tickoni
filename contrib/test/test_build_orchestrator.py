"""Regression tests for portable GNU make command construction."""

import sys
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from contrib.build.orchestrator import clear_object_dir, make_assignment, make_path


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


def test_clear_object_dir_removes_nested_stale_objects(tmp_path):
    obj_dir = tmp_path / "obj"
    stale_object = obj_dir / "third_party" / "cjson" / "cJSON.o"
    stale_object.parent.mkdir(parents=True)
    stale_object.write_bytes(b"x86-64 COFF")

    clear_object_dir(str(obj_dir))

    assert obj_dir.is_dir()
    assert not stale_object.exists()


def test_windows_make_profile_detects_absolute_clang_path():
    profile = Path(__file__).resolve().parents[2] / "config/machine/tickoni_fd.mk"
    text = profile.read_text()
    assert "ifneq (,$(findstring clang,$(CC)))" in text
    assert "ifeq ($(CC),clang)" not in text


def test_linux_x86_make_profile_uses_fixed_haswell_baseline():
    repo_root = Path(__file__).resolve().parents[2]
    profile = (repo_root / "config/machine/tickoni_fd.mk").read_text()

    assert "ifeq ($(UNAME_M),x86_64)" in profile
    assert "include config/machine/linux_clang_x86_64.mk" in profile
    assert "include config/machine/linux_gcc_x86_64.mk" in profile
    assert profile.index("ifeq ($(UNAME_M),x86_64)") < profile.index(
        "include config/machine/native.mk"
    )

    for fixed_profile in (
        "config/machine/linux_clang_x86_64.mk",
        "config/machine/linux_gcc_x86_64.mk",
    ):
        text = (repo_root / fixed_profile).read_text()
        assert "-march=haswell" in text
        assert "-march=native" not in text
