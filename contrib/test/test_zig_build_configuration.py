"""Regression tests for Zig build configuration wiring."""

from pathlib import Path


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
