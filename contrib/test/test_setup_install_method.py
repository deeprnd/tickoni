"""Tests for orchestrator install-method resolution.

``install_method`` is normally a strategy name. A tool reachable on several
platforms through different system package managers instead maps OS -> strategy
(``{"linux": "apt", "macos": "brew", "windows": "winget"}``); picking one for the
target platform is orchestrator logic, not a strategy.
"""

import importlib.util
import json
import sys
from pathlib import Path

import pytest

setup_dir = Path(__file__).resolve().parents[1] / "setup"
sys.path.insert(0, str(setup_dir))
# orchestrator imports ``platform``; shadow the stdlib module with setup/platform.py
platform_spec = importlib.util.spec_from_file_location("platform", setup_dir / "platform.py")
platform_module = importlib.util.module_from_spec(platform_spec)
sys.modules["platform"] = platform_module
platform_spec.loader.exec_module(platform_module)

from platform import matches_platform  # noqa: E402
from install import get as get_strategy  # noqa: E402
from orchestrator import _resolve_install_method  # noqa: E402

_OS_MAP = {"linux": "apt", "macos": "brew", "windows": "winget"}


def test_string_method_passes_through():
    assert _resolve_install_method("pip", "linux-x86", "yamllint") == "pip"


@pytest.mark.parametrize(
    "platform_str,expected",
    [
        ("linux-x86", "apt"),
        ("linux-arm", "apt"),
        ("macos-arm", "brew"),
        ("macos-x86", "brew"),
        ("windows-arm", "winget"),
        ("windows-x86", "winget"),
    ],
)
def test_os_map_selects_strategy_for_platform(platform_str, expected):
    assert _resolve_install_method(dict(_OS_MAP), platform_str, "curl") == expected


def test_os_map_missing_entry_raises():
    with pytest.raises(KeyError):
        _resolve_install_method({"linux": "apt"}, "windows-arm", "curl")


def test_config_install_methods_resolve_to_registered_strategies():
    """Every tool's install_method must resolve to a registered strategy on
    each platform it declares support for."""
    cfg = json.loads((setup_dir / "tool-versions.json").read_text())
    platforms = [
        "linux-x86", "linux-arm",
        "macos-x86", "macos-arm",
        "windows-x86", "windows-arm",
    ]
    for name, tool in cfg["tools"].items():
        method = tool["install_method"]
        for platform_str in platforms:
            if not matches_platform(tool, platform_str):
                continue
            resolved = _resolve_install_method(method, platform_str, name)
            get_strategy(resolved)  # raises KeyError if not registered


def test_no_system_package_pseudo_method_in_config():
    cfg = json.loads((setup_dir / "tool-versions.json").read_text())
    methods = set()
    for tool in cfg["tools"].values():
        method = tool["install_method"]
        methods.update(method.values() if isinstance(method, dict) else [method])
    assert "system_package" not in methods
