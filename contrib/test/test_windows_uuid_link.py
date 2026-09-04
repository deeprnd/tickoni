"""Regression tests for the Windows UUID compatibility archive link."""

from pathlib import Path


BUILD_ZIG = Path(__file__).resolve().parents[2] / "build.zig"


def test_windows_supervisor_links_uuid_archive_from_fd_lib_dir():
    text = BUILD_ZIG.read_text()

    supervisor_branch = text.split(
        "if (target.result.os.tag == .windows) {", 1
    )[1].split("    } else if (target.result.cpu.arch == .aarch64) {", 1)[0]
    assert "linkTickoniSystemLibraries(b, exe, fd_lib_dir," in supervisor_branch
    assert "fn linkTickoniWindowsUuid" in text
    assert '"{s}/libuuid.a"' in text


def test_windows_supervisor_links_all_firedancer_archives():
    text = BUILD_ZIG.read_text()

    supervisor_branch = text.split(
        "if (target.result.os.tag == .windows) {", 1
    )[1].split("    } else if (target.result.cpu.arch == .aarch64) {", 1)[0]
    assert (
        'linkTickoniSystemLibraries(b, exe, fd_lib_dir, '
        '&.{ "fd_disco", "fd_waltz", "fd_tango", "fd_ballet", "fd_util" });'
    ) in supervisor_branch


def test_windows_uuid_stub_build_uses_canonical_arm64_target_and_fails_loudly():
    windows_strategy = (
        Path(__file__).resolve().parents[1] / "build" / "strategies" / "windows.py"
    ).read_text()
    assert '"arm64": "--target=aarch64-pc-windows-msvc"' in windows_strategy
    assert "failed to compile Windows UUID compatibility stub" in windows_strategy
    assert "return" not in windows_strategy.split(
        "except subprocess.CalledProcessError", 1
    )[1].split("# Archive", 1)[0]
