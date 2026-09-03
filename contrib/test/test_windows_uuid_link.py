"""Regression tests for the Windows UUID compatibility archive link."""

from pathlib import Path


BUILD_ZIG = Path(__file__).resolve().parents[2] / "build.zig"


def test_windows_supervisor_links_uuid_archive_from_fd_lib_dir():
    text = BUILD_ZIG.read_text()

    supervisor_branch = text.split(
        "if (target.result.os.tag == .windows) {", 1
    )[1].split("    } else if (target.result.cpu.arch == .aarch64) {", 1)[0]
    assert "linkTickoniWindowsUuid(b, exe, fd_lib_dir);" in supervisor_branch
    assert "fn linkTickoniWindowsUuid" in text
    assert '"{s}/libuuid.a"' in text
