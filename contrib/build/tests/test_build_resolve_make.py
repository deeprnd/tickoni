"""Regression tests for GNU Make resolution in the macOS build strategy.

Firedancer's makefiles use the ``$(file ...)`` builtin (GNU Make >= 4.0).
macOS ships ``/usr/bin/make`` = GNU Make 3.81; picking it makes the FD build
silently drop ``fd_version.o`` and fail ``libfd_util.a`` with no diagnostic.
``resolve_make`` must skip anything older than 4.0.
"""

import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "build"))
import strategies.macos as macos  # noqa: E402


def test_rejects_gnu_make_3_81(monkeypatch):
    monkeypatch.delenv("JUST_GMAKE", raising=False)
    monkeypatch.setattr(macos, "_which", lambda cmd: f"/usr/bin/{cmd}")
    monkeypatch.setattr(macos, "_homebrew_prefixes", lambda: [])

    def fake_version(args, **kwargs):
        return "GNU Make 3.81\n"

    monkeypatch.setattr(macos.subprocess, "check_output", fake_version)

    with pytest.raises(RuntimeError, match="GNU Make >= 4.0"):
        macos.resolve_make()


def test_accepts_gnu_make_4plus(monkeypatch):
    monkeypatch.delenv("JUST_GMAKE", raising=False)
    monkeypatch.setattr(macos, "_which", lambda cmd: "/opt/homebrew/bin/gmake" if cmd == "gmake" else None)
    monkeypatch.setattr(macos, "_homebrew_prefixes", lambda: [])
    monkeypatch.setattr(macos.subprocess, "check_output", lambda args, **kw: "GNU Make 4.4.1\n")

    assert macos.resolve_make() == "gmake"


def test_just_gmake_env_wins(monkeypatch, tmp_path):
    gmake = tmp_path / "gmake"
    gmake.touch()
    monkeypatch.setenv("JUST_GMAKE", str(gmake))

    assert macos.resolve_make() == str(gmake)


@pytest.mark.parametrize(
    "version_line,expected",
    [
        ("GNU Make 4.4.1", True),
        ("GNU Make 4.0", True),
        ("GNU Make 3.81", False),
        ("GNU Make 3.82", False),
        ("some other make", False),
    ],
)
def test_is_gnu_make_4plus(monkeypatch, version_line, expected):
    monkeypatch.setattr(macos.subprocess, "check_output", lambda args, **kw: version_line + "\n")
    assert macos._is_gnu_make_4plus("make") is expected
