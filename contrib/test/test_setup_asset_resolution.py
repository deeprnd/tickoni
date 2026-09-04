"""Regression tests for github_release asset resolution across platforms.

Guards the macOS asset lookup: ``get_platform_from_string`` yields the OS
token ``macos`` while every ``asset_pattern_os_map`` in tool-versions.json
keys macOS assets under ``darwin`` (the GitHub release naming convention).
The strategy must bridge that gap so ``just setup-*-macos-arm`` resolves an
asset instead of exiting with "could not resolve asset for macos-arm".
"""

import importlib.util
import sys
from pathlib import Path

import pytest

setup_dir = Path(__file__).resolve().parents[1] / "setup"
sys.path.insert(0, str(setup_dir))
platform_spec = importlib.util.spec_from_file_location("platform", setup_dir / "platform.py")
platform_module = importlib.util.module_from_spec(platform_spec)
sys.modules["platform"] = platform_module
platform_spec.loader.exec_module(platform_module)

from config import load_config  # noqa: E402
from install.strategies.download import GitHubReleaseStrategy  # noqa: E402


def _resolve(tool_name, platform_str):
    config = load_config()
    tool = dict(config["tools"][tool_name])
    tool["name"] = tool_name
    _url, _version, pattern, _verify = GitHubReleaseStrategy()._resolve_url(
        tool, config, platform_str
    )
    return pattern


@pytest.mark.parametrize(
    "tool_name,platform_str,expected_token",
    [
        ("actionlint", "macos-arm", "darwin_arm64"),
        ("actionlint", "macos-x86", "darwin_amd64"),
        ("gitleaks", "macos-arm", "darwin_arm64"),
        ("gitleaks", "macos-x86", "darwin_x64"),
        ("actionlint", "linux-arm", "linux_arm64"),
        ("gitleaks", "linux-x86", "linux_x64"),
    ],
)
def test_github_release_asset_resolves(tool_name, platform_str, expected_token):
    assert expected_token in _resolve(tool_name, platform_str)
