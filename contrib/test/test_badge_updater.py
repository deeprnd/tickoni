"""Unit tests for badge_updater.py (A-2/T-1).

Tests cover:
- _coverage_color()
- badge_url()
- _resolve_simple_badge() and resolve_badges() (with mocked API)
- replace_badge_block()
- update_readme()
"""

import json
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

# Add parent dir so we can import badge_updater without installing it
import sys
sys.path.insert(0, str(Path(__file__).parents[1] / "tool" / "readme"))
import badge_updater


# ── _coverage_color ──


class TestCoverageColor:
    def test_red_below_40(self):
        assert badge_updater._coverage_color(0.0) == "red"
        assert badge_updater._coverage_color(39.9) == "red"

    def test_yellow_below_60(self):
        assert badge_updater._coverage_color(40.0) == "yellow"
        assert badge_updater._coverage_color(59.9) == "yellow"

    def test_orange_below_80(self):
        assert badge_updater._coverage_color(60.0) == "orange"
        assert badge_updater._coverage_color(79.9) == "orange"

    def test_brightgreen_at_80_plus(self):
        assert badge_updater._coverage_color(80.0) == "brightgreen"
        assert badge_updater._coverage_color(100.0) == "brightgreen"


# ── badge_url ──


class TestBadgeUrl:
    def test_basic(self):
        url = badge_updater.badge_url("build", "passing", "brightgreen")
        assert url == "https://img.shields.io/badge/build-passing-brightgreen?style=flat-square"

    def test_spaces_encoded(self):
        url = badge_updater.badge_url("unit tests", "passing", "brightgreen")
        assert "unit%20tests" in url

    def test_percent_encoded(self):
        url = badge_updater.badge_url("x%y", "passing", "brightgreen")
        assert "x%25y" in url

    def test_special_chars_in_message(self):
        url = badge_updater.badge_url("build", "99% pass", "brightgreen")
        assert "99%25%20pass" in url


# ── _resolve_simple_badge ──


class TestResolveSimpleBadge:
    def test_success(self):
        result = badge_updater._resolve_simple_badge(
            "build", "Project Build", "build", "Build", "Build",
            {"Project Build": "success"},
        )
        assert result == {
            "status": "passing",
            "color": "brightgreen",
            "url": badge_updater.badge_url("build", "passing", "brightgreen"),
        }

    def test_failure(self):
        result = badge_updater._resolve_simple_badge(
            "build", "Project Build", "build", "Build", "Build",
            {"Project Build": "failure"},
        )
        assert result == {
            "status": "failing",
            "color": "red",
            "url": badge_updater.badge_url("build", "failing", "red"),
        }

    def test_unknown(self):
        result = badge_updater._resolve_simple_badge(
            "build", "Project Build", "build", "Build", "Build",
            {},
        )
        assert result == {
            "status": "unknown",
            "color": "lightgrey",
            "url": badge_updater.badge_url("build", "unknown", "lightgrey"),
        }

    def test_other_conclusion(self):
        # e.g. "timed_out" or "cancelled"
        result = badge_updater._resolve_simple_badge(
            "build", "Project Build", "build", "Build", "Build",
            {"Project Build": "cancelled"},
        )
        assert result["status"] == "unknown"


# ── resolve_badges (mocked) ──


class TestResolveBadges:
    def _make_check_runs(self, statuses):
        """Build a list of check-run dicts from a job-name -> conclusion mapping."""
        return [
            {"name": name, "conclusion": conclusion}
            for name, conclusion in statuses.items()
        ]

    def _patch_get_check_runs(self, mock_check_runs):
        return patch.object(
            badge_updater, "get_check_runs", return_value=mock_check_runs
        )

    @patch.object(badge_updater, "_read_coverage_pct", return_value=None)
    def test_all_success(self, mock_cov):
        runs = self._make_check_runs({
            "Project Build": "success",
            "Project Tests": "success",
            "Project Security": "success",
            "Tests / Coverage": "success",
        })
        with self._patch_get_check_runs(runs):
            result = badge_updater.resolve_badges("owner", "repo", "abc123", "token")
        assert result["build"]["status"] == "passing"
        assert result["unit"]["status"] == "passing"
        assert result["security"]["status"] == "passing"
        assert result["cov-tk"]["status"] == "unknown"  # _read_coverage_pct returns None

    @patch.object(badge_updater, "_read_coverage_pct", return_value=72.5)
    def test_coverage_badge_with_value(self, mock_cov):
        runs = self._make_check_runs({
            "Project Build": "success",
            "Project Tests": "success",
            "Project Security": "success",
            "Tests / Coverage": "success",
        })
        with self._patch_get_check_runs(runs):
            result = badge_updater.resolve_badges("owner", "repo", "abc123", "token")
        assert result["cov-tk"]["status"] == "72.5%"
        assert result["cov-tk"]["color"] == "orange"

    def test_all_failures(self):
        runs = self._make_check_runs({
            "Project Build": "failure",
            "Project Tests": "failure",
            "Project Security": "failure",
            "Tests / Coverage": "failure",
        })
        with self._patch_get_check_runs(runs):
            result = badge_updater.resolve_badges("owner", "repo", "abc123", "token")
        assert result["build"]["status"] == "failing"
        assert result["unit"]["status"] == "failing"
        assert result["security"]["status"] == "failing"
        assert result["cov-tk"]["status"] == "unknown"

    @patch.object(badge_updater, "_read_coverage_pct", return_value=45.0)
    def test_partial_success(self, mock_cov):
        runs = self._make_check_runs({
            "Project Build": "success",
            "Project Tests": "failure",
            "Project Security": "success",
            "Tests / Coverage": "success",
        })
        with self._patch_get_check_runs(runs):
            result = badge_updater.resolve_badges("owner", "repo", "abc123", "token")
        assert result["build"]["status"] == "passing"
        assert result["unit"]["status"] == "failing"
        assert result["security"]["status"] == "passing"
        assert result["cov-tk"]["status"] == "45.0%"
        assert result["cov-tk"]["color"] == "yellow"

    def test_no_check_runs(self):
        with self._patch_get_check_runs([]):
            result = badge_updater.resolve_badges("owner", "repo", "abc123", "token")
        assert all(result[k]["status"] == "unknown" for k in ("build", "unit", "security", "cov-tk"))


# ── replace_badge_block ──


class TestReplaceBadgeBlock:
    def test_basic_replace(self):
        doc = (
            "some text\n"
            "<!-- badge:build:start -->\n"
            "  <img alt=\"Build\" src=\"old-url\" />\n"
            "<!-- badge:build:end -->\n"
            "more text\n"
        )
        result = badge_updater.replace_badge_block(
            doc, "build", '<img alt="build" src="new-url" />'
        )
        assert 'src="new-url"' in result
        assert 'src="old-url"' not in result

    def test_missing_start_marker(self):
        doc = "<!-- badge:build:end -->\n"
        with pytest.raises(ValueError, match="missing"):
            badge_updater.replace_badge_block(doc, "build", "new-tag")

    def test_missing_end_marker(self):
        doc = "<!-- badge:build:start -->\n"
        with pytest.raises(ValueError, match="missing"):
            badge_updater.replace_badge_block(doc, "build", "new-tag")

    def test_out_of_order_markers(self):
        doc = "<!-- badge:build:end -->\n<!-- badge:build:start -->\n"
        with pytest.raises(ValueError, match="out of order"):
            badge_updater.replace_badge_block(doc, "build", "new-tag")

    def test_no_img_tag(self):
        doc = "<!-- badge:build:start -->\nno img here\n<!-- badge:build:end -->\n"
        with pytest.raises(ValueError, match="No img tag found"):
            badge_updater.replace_badge_block(doc, "build", "new-tag")


# ── update_readme ──


class TestUpdateReadme:
    def _make_readme(self):
        """Create a minimal README with all four badge markers."""
        return (
            "# Repo\n\n"
            "<!-- badge:build:start -->\n"
            "  <img alt=\"Build\" src=\"old-build\" />\n"
            "<!-- badge:build:end -->\n\n"
            "<!-- badge:unit:start -->\n"
            "  <img alt=\"Unit Tests\" src=\"old-unit\" />\n"
            "<!-- badge:unit:end -->\n\n"
            "<!-- badge:security:start -->\n"
            "  <img alt=\"Security\" src=\"old-security\" />\n"
            "<!-- badge:security:end -->\n\n"
            "<!-- badge:cov-tk:start -->\n"
            "  <img alt=\"AI Harness Coverage\" src=\"old-cov\" />\n"
            "<!-- badge:cov-tk:end -->\n"
        )

    @patch.object(badge_updater, "_read_coverage_pct", return_value=None)
    def test_updates_all_badges(self, mock_cov):
        readme = self._make_readme()
        badges = {
            "build": {"url": "url-build"},
            "unit": {"url": "url-unit"},
            "security": {"url": "url-security"},
            "cov-tk": {"url": "url-cov"},
        }
        result = badge_updater.update_readme(readme, badges)
        assert 'src="url-build"' in result
        assert 'src="url-unit"' in result
        assert 'src="url-security"' in result
        assert 'src="url-cov"' in result

    @patch.object(badge_updater, "_read_coverage_pct", return_value=None)
    def test_preserves_other_content(self, mock_cov):
        readme = self._make_readme()
        badges = {
            "build": {"url": "url-build"},
            "unit": {"url": "url-unit"},
            "security": {"url": "url-security"},
            "cov-tk": {"url": "url-cov"},
        }
        result = badge_updater.update_readme(readme, badges)
        assert "# Repo" in result

    def test_alt_text_consistency(self):
        """N-1: verify alt text uses badge_key, not title-cased names."""
        readme = self._make_readme()
        badges = {
            "build": {"url": "url-build"},
            "unit": {"url": "url-unit"},
            "security": {"url": "url-security"},
            "cov-tk": {"url": "url-cov"},
        }
        result = badge_updater.update_readme(readme, badges)
        # All alt texts should be badge keys, not title-cased strings
        assert 'alt="build"' in result
        assert 'alt="unit"' in result
        assert 'alt="security"' in result
        assert 'alt="cov-tk"' in result
        # Should NOT have title-cased variants
        assert 'alt="Build"' not in result
        assert 'alt="Unit Tests"' not in result
        assert 'alt="Security"' not in result
        assert 'alt="AI Harness Coverage"' not in result
