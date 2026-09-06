"""Unit tests for install.strategies.qt_installer (config resolution).

Tests the pure config-resolution path of QtInstallerStrategy without
hitting the network, filesystem, or subprocess.
"""

import sys
from pathlib import Path
from unittest.mock import patch

import pytest

# Ensure setup/ is on sys.path so the install/strategies package imports work
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from contrib.setup.install.strategies.qt_installer import (
    QtInstallerStrategy,
    _extract_qt_version,
)


# ── Config resolution ───────────────────────────────────────────────


class TestResolveFromConfig:
    """Test _resolve_from_config validation paths."""

    def _build_config(self, qt_module, asset_name, sha256, base_url):
        return {
            "versions": {
                "qt-installer": {
                    "options": {
                        "qt_module": {"linux-x86": qt_module},
                        "asset_name": {"linux-x86": asset_name},
                        "sha256": {"linux-x86": sha256},
                        "base_url": base_url,
                    }
                }
            }
        }

    def test_resolves_linux_x86(self):
        config = self._build_config(
            "qt.qt6.6112.linux_gcc_64",
            "qt-online-installer-linux-x64-{version}.run",
            "abc123",
            "https://download.qt.io",
        )
        result = QtInstallerStrategy._resolve_from_config("linux-x86", config)
        assert result["qt_module"] == "qt.qt6.6112.linux_gcc_64"
        assert (
            result["asset_name"] == "qt-online-installer-linux-x64-{version}.run"
        )
        assert result["sha256"] == "abc123"
        assert result["base_url"] == "https://download.qt.io"

    def test_missing_qt_module_exits(self):
        config = {"versions": {"qt-installer": {"options": {}}}}
        with pytest.raises(SystemExit):
            QtInstallerStrategy._resolve_from_config("linux-x86", config)

    def test_missing_asset_name_exits(self):
        config = {"versions": {"qt-installer": {"options": {"qt_module": {}}}}}
        with pytest.raises(SystemExit):
            QtInstallerStrategy._resolve_from_config("linux-x86", config)

    def test_legacy_string_version_exits(self):
        config = {"versions": {"qt-installer": "6.5.0"}}
        with pytest.raises(SystemExit):
            QtInstallerStrategy._resolve_from_config("linux-x86", config)


# ── Qt version extraction ───────────────────────────────────────────


class TestExtractQtVersion:
    """Test _extract_qt_version helper.

    Qt module IDs use a 4-digit version encoding: qt.qtN.NNNN.subdir
    where NNNN encodes X.Y.Z (e.g. 6112 → 6.11.2).
    """

    def test_6112(self):
        assert _extract_qt_version("qt.qt6.6112.linux_gcc_64") == "6.11.2"

    def test_6031(self):
        # Encoding: major=6, minor=03, patch=1 → "6.03.1"
        assert _extract_qt_version("qt.qt6.6031.macos_clang_64") == "6.03.1"

    def test_6100(self):
        # Encoding: major=6, minor=10, patch=0 → "6.10.0"
        assert _extract_qt_version("qt.qt6.6100.win64_msvc2019_64") == "6.10.0"


# ── Platform canonical names ────────────────────────────────────────


class TestCanonicalNames:
    """Test _CANONICAL covers all supported platforms."""

    def test_all_platforms_have_canonical_names(self):
        from contrib.setup.install.strategies.qt_installer import _CANONICAL

        expected = {
            "linux-x86",
            "linux-arm",
            "macos-x86",
            "macos-arm",
            "windows-x86",
            "windows-arm",
        }
        assert set(_CANONICAL.keys()) == expected

    def test_canonical_names_have_flags(self):
        from contrib.setup.install.strategies.qt_installer import _CANONICAL

        for platform, (name, flags) in _CANONICAL.items():
            assert name, f"{platform} has empty canonical name"
            assert flags, f"{platform} has empty flags"
