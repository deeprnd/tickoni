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


def test_macos_unit_recipes_build_fd_tests_then_run_portable_tickoni_tests():
    repo_root = Path(__file__).resolve().parents[2]
    content = (repo_root / "just" / "test" / "unit.just").read_text()

    def _extract_recipe(content: str, name: str) -> str:
        """Extract recipe body by matching name: at the start of a line."""
        import re
        match = re.search(rf"^{name}:", content, re.MULTILINE)
        if not match:
            raise ValueError(f"Recipe {name!r} not found in justfile")
        start = match.start()
        end = content.find("\n\n", start)
        section = content[start:] if end == -1 else content[start:end]
        # Follow alias: if content after "name:" doesn't start with 4+ spaces (body)
        # or # (comment), it's an alias to another recipe
        after_colon = section[section.index(":") + 1:]
        stripped = after_colon.lstrip()
        if stripped and not stripped.startswith("#") and len(after_colon) - len(stripped) < 4:
            alias_target = stripped.split()[0] if stripped.split() else None
            if alias_target and ":" not in alias_target:
                return _extract_recipe(content, alias_target)
        return section

    # Build recipes: should contain orchestrator + unit-test target, no run script
    for recipe in ("build-test-unit-fd-macos-x86", "build-test-unit-fd-macos-arm"):
        section = _extract_recipe(content, recipe)

        assert "contrib/build/orchestrator.py" in section
        assert "--build-target unit-test" in section
        assert "run_unit_tests.sh" not in section

    # Run recipes: should contain run script, no build commands
    for recipe in ("test-unit-fd-macos-x86", "test-unit-fd-macos-arm"):
        section = _extract_recipe(content, recipe)

        assert "run_unit_tests.sh" in section
        assert "--page-sz normal" in section
        assert "GNUmakefile" not in section


def _extract_just_recipe(content: str, name: str) -> str:
    """Extract recipe body, following aliases to their base."""
    start = content.index(f"{name}:")
    end = content.find("\n\n", start)
    section = content[start:] if end == -1 else content[start:end]
    # Follow alias: if content after "name:" doesn't start with 4+ spaces (body)
    # or # (comment), it's an alias to another recipe
    after_colon = section[section.index(":") + 1:]
    stripped = after_colon.lstrip()
    if stripped and not stripped.startswith("#") and len(after_colon) - len(stripped) < 4:
        # Alias to another recipe
        alias_target = stripped.split()[0] if stripped.split() else None
        if alias_target and ":" not in alias_target:
            return _extract_just_recipe(content, alias_target)
    return section


def test_macos_integration_recipes_build_fd_libraries_before_zig_tests():
    repo_root = Path(__file__).resolve().parents[2]
    content = (repo_root / "just" / "test" / "integration.just").read_text()

    recipes = (
        "test-integration-tk-macos-x86",
        "test-integration-tk-macos-arm",
    )
    for recipe in recipes:
        section = _extract_just_recipe(content, recipe)
        assert "zig build" in section


def test_hosted_linker_flags_are_linux_only():
    repo_root = Path(__file__).resolve().parents[2]
    hosted = (repo_root / "config/extra/with-hosted.mk").read_text()

    linux_guard = hosted.index("ifeq ($(FD_HAS_LINUX),1)")
    linker_flags = hosted.index("LDFLAGS+=-z noexecstack -lrt")
    guard_end = hosted.index("endif", linker_flags)

    assert linux_guard < linker_flags < guard_end


def test_linux_only_firedancer_tests_are_platform_guarded():
    repo_root = Path(__file__).resolve().parents[2]

    cpuset_local_mk = (repo_root / "src/util/tile/Local.mk").read_text()
    cpuset_guard = cpuset_local_mk.index("ifdef FD_HAS_LINUX")
    cpuset_test = cpuset_local_mk.index("make-unit-test,test_cpuset")
    cpuset_guard_end = cpuset_local_mk.index("endif", cpuset_test)
    assert cpuset_guard < cpuset_test < cpuset_guard_end

    bundle_local_mk = (repo_root / "src/disco/bundle/Local.mk").read_text()
    bundle_guard = bundle_local_mk.index("ifdef FD_HAS_LINUX")
    bundle_guard_end = bundle_local_mk.index("endif", bundle_guard)
    for test_name in ("test_bundle_client", "test_bundle_tile"):
        bundle_test = bundle_local_mk.index(f"make-unit-test,{test_name}")
        assert bundle_guard < bundle_test < bundle_guard_end

    diag_local_mk = (repo_root / "src/disco/diag/Local.mk").read_text()
    diag_guard = diag_local_mk.index("ifdef FD_HAS_LINUX")
    diag_test = diag_local_mk.index("make-unit-test,test_proc_interrupts")
    diag_guard_end = diag_local_mk.index("endif", diag_test)
    assert diag_guard < diag_test < diag_guard_end

    event_local_mk = (repo_root / "src/disco/events/Local.mk").read_text()
    event_guard = event_local_mk.index("ifdef FD_HAS_LINUX")
    event_test = event_local_mk.index("make-unit-test,test_event_client")
    event_guard_end = event_local_mk.index("endif", event_test)
    assert event_guard < event_test < event_guard_end

    udpsock_local_mk = (repo_root / "src/waltz/udpsock/Local.mk").read_text()
    udpsock_guard = udpsock_local_mk.index("ifdef FD_HAS_LINUX")
    udpsock_test = udpsock_local_mk.index("make-unit-test,test_udpsock_echo")
    udpsock_guard_end = udpsock_local_mk.index("endif", udpsock_test)
    assert udpsock_guard < udpsock_test < udpsock_guard_end
