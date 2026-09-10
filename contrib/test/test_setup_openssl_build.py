"""Regression tests for the Windows OpenSSL build strategy."""

from pathlib import Path
from types import SimpleNamespace
import importlib.util
import sys

import pytest

setup_dir = Path(__file__).resolve().parents[1] / "setup"
sys.path.insert(0, str(setup_dir))
# The setup package imports ``platform`` by its short name; bind its local
# module before importing an install strategy.
platform_spec = importlib.util.spec_from_file_location("platform", setup_dir / "platform.py")
platform_module = importlib.util.module_from_spec(platform_spec)
sys.modules["platform"] = platform_module
platform_spec.loader.exec_module(platform_module)

from install.strategies import openssl_build  # noqa: E402


@pytest.mark.parametrize(
    ("platform_str", "expected_arch"),
    [("windows-x86", "x86"), ("windows-arm", "arm")],
)
def test_openssl_build_passes_requested_windows_target_to_helper(
    monkeypatch, tmp_path, platform_str, expected_arch
):
    """The helper must not infer its target from an emulated host shell."""
    captured = {}

    def extract(_archive, destination, _extract_dir, version):
        (Path(destination) / version).mkdir()

    def run(command, **kwargs):
        captured["command"] = command
        captured["env"] = kwargs["env"]
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    monkeypatch.setattr(openssl_build, "resolve_version", lambda *_: "openssl-3.6.4")
    monkeypatch.setattr(
        openssl_build.OpenSSLBuildStrategy,
        "_resolve_from_config",
        lambda *_: {
            "base_url": "https://example.invalid",
            "filename": "openssl.tar.gz",
            "sha256": None,
            "extract_dir": "openssl-3.6.4",
        },
    )
    monkeypatch.setattr(openssl_build, "_download_and_verify", lambda **_: None)
    monkeypatch.setattr(openssl_build, "_extract_archive", extract)
    monkeypatch.setattr(openssl_build.subprocess, "run", run)

    openssl_build.OpenSSLBuildStrategy().execute(
        {"parameters": {"install_dir": str(tmp_path / "opt")}},
        {},
        platform_str,
        False,
    )

    assert captured["env"]["FD_WINDOWS_ARCH"] == expected_arch
