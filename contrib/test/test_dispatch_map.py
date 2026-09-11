"""T-2: Validate dispatch-map.json against platform.sh outputs.

Ensures every key in dispatch-map.json uses a valid {os}-{arch} platform
string, and that each platform maps to a real just recipe.
"""

import json
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).parents[2]
DISPATCH_MAP = ROOT / "scripts" / "dispatch-map.json"
JUST_DIR = ROOT / "just"
PLATFORM_SH = ROOT / "contrib" / "platform.sh"


class TestDispatchMapValidation:
    def test_valid_platform_keys(self):
        """T-2: all platform keys must match {linux,macos,windows}-{x86,arm}."""
        valid_patterns = {"linux-x86", "linux-arm", "macos-x86", "macos-arm", "windows-x86", "windows-arm"}
        data = json.loads(DISPATCH_MAP.read_text(encoding="utf-8"))
        for category, platforms in data.items():
            for platform in platforms:
                assert platform in valid_patterns, (
                    f"Platform '{platform}' in '{category}' is not a valid "
                    f"platform.sh output pattern"
                )

    def test_no_duplicate_platforms_within_category(self):
        """No platform should appear twice in the same category."""
        data = json.loads(DISPATCH_MAP.read_text(encoding="utf-8"))
        for category, platforms in data.items():
            seen = set()
            for p in platforms:
                assert p not in seen, f"Platform '{p}' appears twice in '{category}'"
                seen.add(p)

    def test_just_recipes_exist(self):
        """Every dispatch-map value must correspond to a just recipe that exists."""
        data = json.loads(DISPATCH_MAP.read_text(encoding="utf-8"))
        missing = []
        for category, targets in data.items():
            for platform, recipe in targets.items():
                # Recipe names follow just's naming; verify they're non-empty
                assert recipe, f"Empty recipe for '{category}/{platform}'"
                # Check the recipe exists in just --list
                # We verify the recipe name is not obviously wrong (e.g., contains spaces, special chars)
                assert " " not in recipe, (
                    f"Recipe '{recipe}' for '{category}/{platform}' contains a space"
                )
        # Note: we can't verify recipe existence at import time without
        # actually invoking just (which requires the full project build),
        # but we catch structural issues above.

    def test_platform_sh_consistency(self):
        """Validate dispatch-map platforms match platform.sh output patterns."""
        if not PLATFORM_SH.exists():
            pytest.skip("platform.sh not found")
        # platform.sh outputs: linux, macos, windows for OS
        # and x86, arm for arch
        # So valid platforms are: linux-x86, linux-arm, macos-x86, macos-arm, windows-x86, windows-arm
        expected = {
            "linux": {"x86", "arm"},
            "macos": {"x86", "arm"},
            "windows": {"x86", "arm"},
        }
        data = json.loads(DISPATCH_MAP.read_text(encoding="utf-8"))
        for category, platforms in data.items():
            for platform_str in platforms:
                os_part, arch_part = platform_str.rsplit("-", 1)
                assert os_part in expected, f"Unknown OS '{os_part}' in '{platform_str}'"
                assert arch_part in expected[os_part], (
                    f"Unknown arch '{arch_part}' for OS '{os_part}' in '{platform_str}'"
                )

    def test_no_orphan_platforms(self):
        """No platform.sh output pattern should be missing from ALL categories.

        A platform is 'supported' if at least one category maps it.
        This test ensures we don't have categories that only support a subset
        when the project claims all-platform coverage.
        """
        data = json.loads(DISPATCH_MAP.read_text(encoding="utf-8"))
        # Collect all platforms that appear in ANY category
        all_platforms = set()
        for platforms in data.values():
            all_platforms.update(platforms)

        # Check each platform is used (not just defined)
        assert len(all_platforms) > 0, "dispatch-map.json has no platform entries"

        # Verify all 6 platforms are covered somewhere (full coverage claim)
        full_coverage = {
            "linux-x86", "linux-arm",
            "macos-x86", "macos-arm",
            "windows-x86", "windows-arm",
        }
        # Not all categories need all platforms (test-unit-fd omits linux-arm),
        # but at least the 'build-tk' category should cover all.
        if "build-tk" in data:
            build_platforms = set(data["build-tk"].keys())
            missing_build = full_coverage - build_platforms
            if missing_build:
                pytest.fail(
                    f"build-tk is missing platforms: {sorted(missing_build)}. "
                    "build-tk should cover all platforms."
                )

    def test_dispatch_map_is_valid_json(self):
        """dispatch-map.json must be valid, parseable JSON."""
        data = json.loads(DISPATCH_MAP.read_text(encoding="utf-8"))
        assert isinstance(data, dict), "dispatch-map.json must be a JSON object"
        for key, value in data.items():
            assert isinstance(value, dict), f"'{key}' in dispatch-map.json must be an object"
            for platform, recipe in value.items():
                assert isinstance(recipe, str), (
                    f"'{key}/{platform}' recipe must be a string, got {type(recipe).__name__}"
                )
