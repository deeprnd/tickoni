#!/usr/bin/env python3
"""Badge updater for README.md.

Walks parent commits on main to find the last SHA where all aggregated
CI jobs succeeded, then updates README badge URLs between marker comments.

Usage (called from badge-update.yml):
    python3 contrib/tool/readme/badge_updater.py <commit-sha>

Usage (local dry-run):
    python3 contrib/tool/readme/badge_updater.py <commit-sha> --dry-run

Usage (reset all badges to unknown):
    python3 contrib/tool/readme/badge_updater.py --reset
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

# ── constants ────────────────────────────────────────────────────────────────

REPO_ROOT = Path(__file__).parents[3]
README_PATH = REPO_ROOT / "README.md"
COVERAGE_JSON_PATH = REPO_ROOT / "build/coverage/tk/coverage-summary.json"
API_BASE = "https://api.github.com"
AGGREGATED_JOBS = [
    "Project Build",
    "Project Tests",
    "Project Security",
    "Tests / Coverage",
]
MAX_PARENTS = 50


# ── GitHub API helpers ───────────────────────────────────────────────────────

def _api_headers(token: str) -> dict:
    return {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }


def get_check_runs(repo_owner: str, repo_name: str, sha: str, token: str) -> list:
    """List check-runs for a commit. Returns list of dicts with 'name' and 'conclusion'."""
    import urllib.request

    url = f"{API_BASE}/repos/{repo_owner}/{repo_name}/commits/{sha}/check-runs"
    req = urllib.request.Request(url, headers=_api_headers(token))
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode())
            return data.get("check_runs", [])
    except Exception:
        return []


def get_commit_parents(repo_owner: str, repo_name: str, sha: str, token: str) -> list:
    """Get parent commit SHAs for a commit."""
    import urllib.request

    url = f"{API_BASE}/repos/{repo_owner}/{repo_name}/commits/{sha}"
    req = urllib.request.Request(url, headers=_api_headers(token))
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode())
            parents = data.get("parents", [])
            return [{"sha": p["sha"]} for p in parents]
    except Exception:
        return []


def get_blob_content(repo_owner: str, repo_name: str, sha: str, path: str, token: str) -> str | None:
    """Download a file from the repo at a given commit SHA."""
    import urllib.request
    import base64

    url = f"{API_BASE}/repos/{repo_owner}/{repo_name}/contents/{path}"
    headers = {**_api_headers(token), "If-None-Match": ""}
    req = urllib.request.Request(f"{url}?ref={sha}", headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode())
            content = data.get("content", "")
            import base64 as _b64
            return _b64.b64decode(content).decode("utf-8")
    except Exception:
        return None


# ── parent-commit walk ───────────────────────────────────────────────────────

def find_last_successful_sha(
    repo_owner: str,
    repo_name: str,
    start_sha: str,
    token: str,
    max_parents: int = MAX_PARENTS,
) -> str | None:
    """Walk backwards from start_sha, returning the first SHA where all
    aggregated jobs report 'success'.  Returns None if none found."""
    sha = start_sha
    for _ in range(max_parents):
        check_runs = get_check_runs(repo_owner, repo_name, sha, token)
        if not check_runs:
            # No check-runs for this SHA — skip to parent
            parents = get_commit_parents(repo_owner, repo_name, sha, token)
            if not parents:
                break
            sha = parents[0]["sha"]
            continue

        # Filter to aggregated jobs only
        aggregated = [
            cr for cr in check_runs if cr["name"] in AGGREGATED_JOBS
        ]

        if not aggregated:
            # Aggregated jobs don't exist yet for this SHA — skip
            parents = get_commit_parents(repo_owner, repo_name, sha, token)
            if not parents:
                break
            sha = parents[0]["sha"]
            continue

        if all(cr["conclusion"] == "success" for cr in aggregated):
            return sha

        parents = get_commit_parents(repo_owner, repo_name, sha, token)
        if not parents:
            break
        sha = parents[0]["sha"]

    return None  # no successful merge found within walk limit


# ── badge resolution ─────────────────────────────────────────────────────────

def _encode_segment(value: str) -> str:
    """Percent-encode a badge URL segment (space and percent only)."""
    return value.replace(" ", "%20").replace("%", "%25")


def _coverage_color(pct: float) -> str:
    """Return color based on coverage percentage thresholds."""
    if pct < 40:
        return "red"
    if pct < 60:
        return "yellow"
    if pct < 80:
        return "orange"
    return "brightgreen"


def badge_url(label: str, message: str, color: str) -> str:
    """Construct a shields.io badge URL."""
    return (
        f"https://img.shields.io/badge/{_encode_segment(label)}"
        f"-{_encode_segment(message)}"
        f"-{_encode_segment(color)}?style=flat-square"
    )


def _read_coverage_pct() -> float | None:
    """Read coverage percentage from coverage-summary.json."""
    if not COVERAGE_JSON_PATH.exists():
        return None
    try:
        data = json.loads(COVERAGE_JSON_PATH.read_text(encoding="utf-8"))
    except Exception:
        return None
    total = data.get("total", {})
    lines = total.get("lines", {})
    covered = lines.get("covered", 0)
    total_count = lines.get("total", 0)
    if total_count == 0:
        return None
    return round(covered / total_count * 100, 1)


def resolve_badges(
    repo_owner: str,
    repo_name: str,
    sha: str,
    token: str,
) -> dict:
    """Resolve badge statuses for all four badges.
    Returns dict: {badge_name: {"status": ..., "color": ..., "url": ...}}
    """
    # Get aggregated check-run statuses for this SHA
    check_runs = get_check_runs(repo_owner, repo_name, sha, token)
    aggregated = {}
    for cr in check_runs:
        if cr["name"] in AGGREGATED_JOBS:
            aggregated[cr["name"]] = cr["conclusion"]

    results = {}

    # ── build badge ──
    if aggregated.get("Project Build") == "success":
        results["build"] = {
            "status": "passing",
            "color": "brightgreen",
            "url": badge_url("build", "passing", "brightgreen"),
        }
    elif aggregated.get("Project Build") in ("failure",):
        results["build"] = {
            "status": "failing",
            "color": "red",
            "url": badge_url("build", "failing", "red"),
        }
    else:
        results["build"] = {
            "status": "unknown",
            "color": "lightgrey",
            "url": badge_url("build", "unknown", "lightgrey"),
        }

    # ── unit badge ──
    if aggregated.get("Project Tests") == "success":
        results["unit"] = {
            "status": "passing",
            "color": "brightgreen",
            "url": badge_url("unit tests", "passing", "brightgreen"),
        }
    elif aggregated.get("Project Tests") in ("failure",):
        results["unit"] = {
            "status": "failing",
            "color": "red",
            "url": badge_url("unit tests", "failing", "red"),
        }
    else:
        results["unit"] = {
            "status": "unknown",
            "color": "lightgrey",
            "url": badge_url("unit tests", "unknown", "lightgrey"),
        }

    # ── security badge ──
    if aggregated.get("Project Security") == "success":
        results["security"] = {
            "status": "passing",
            "color": "brightgreen",
            "url": badge_url("security", "passing", "brightgreen"),
        }
    elif aggregated.get("Project Security") in ("failure",):
        results["security"] = {
            "status": "failing",
            "color": "red",
            "url": badge_url("security", "failing", "red"),
        }
    else:
        results["security"] = {
            "status": "unknown",
            "color": "lightgrey",
            "url": badge_url("security", "unknown", "lightgrey"),
        }

    # ── cov-tk badge ──
    cov_ok = aggregated.get("Tests / Coverage") == "success"
    if cov_ok:
        pct = _read_coverage_pct()
        if pct is not None:
            color = _coverage_color(pct)
            results["cov-tk"] = {
                "status": f"{pct:.1f}%",
                "color": color,
                "url": badge_url("harness coverage", f"{pct:.1f}%", color),
            }
        else:
            results["cov-tk"] = {
                "status": "unknown",
                "color": "lightgrey",
                "url": badge_url("harness coverage", "unknown", "lightgrey"),
            }
    else:
        results["cov-tk"] = {
            "status": "unknown",
            "color": "lightgrey",
            "url": badge_url("harness coverage", "unknown", "lightgrey"),
        }

    return results


# ── README update ────────────────────────────────────────────────────────────

def replace_badge_block(doc_text: str, name: str, img_tag: str) -> str:
    """Replace the img line between badge markers with a new img tag."""
    start_marker = f"<!-- badge:{name}:start -->"
    end_marker = f"<!-- badge:{name}:end -->"

    start = doc_text.find(start_marker)
    end = doc_text.find(end_marker)

    if start == -1 or end == -1:
        raise ValueError(f"Badge markers missing for '{name}'")
    if end < start:
        raise ValueError(f"Badge markers out of order for '{name}'")

    img_pos = doc_text.find("<img", start, end)
    if img_pos == -1:
        raise ValueError(f"No img tag found for badge '{name}'")

    # Find the full line containing the img tag
    line_start = doc_text.rfind("\n", 0, img_pos)
    line_start = line_start + 1 if line_start != -1 else 0
    leading = doc_text[line_start:img_pos]
    line_end = doc_text.find("\n", img_pos)
    if line_end == -1:
        line_end = len(doc_text)

    return doc_text[:line_start] + leading + img_tag + doc_text[line_end:]


def update_readme(readme_text: str, badges: dict, dry_run: bool = False) -> str:
    """Update README.md with resolved badge URLs. Returns updated text."""
    badge_map = {
        "build": "build",
        "unit": "unit",
        "security": "security",
        "cov-tk": "cov-tk",
    }

    for badge_key, readme_key in badge_map.items():
        if badge_key in badges:
            url = badges[badge_key]["url"]
            img_tag = f'<img alt="{readme_key.title()} Tests" src="{url}" />'
            # Use appropriate alt text for each badge
            if badge_key == "cov-tk":
                img_tag = f'<img alt="AI Harness Coverage" src="{url}" />'
            readme_text = replace_badge_block(readme_text, badge_key, img_tag)

    return readme_text


# ── git commit & push ────────────────────────────────────────────────────────

def git_commit_and_push(readme_path: Path, sha: str, dry_run: bool = False) -> None:
    """Stage, commit, and push README.md to origin main."""
    if dry_run:
        print(f"[dry-run] Would commit and push README.md for SHA {sha}")
        return

    subprocess.run(
        ["git", "add", str(readme_path)],
        check=True,
        capture_output=True,
    )
    subprocess.run(
        ["git", "commit", "-m", f"ci: update badges for {sha}"],
        check=True,
        capture_output=True,
    )
    subprocess.run(
        ["git", "push", "origin", "main"],
        check=True,
        capture_output=True,
    )


# ── main ─────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Update README.md badges based on CI check-runs."
    )
    parser.add_argument(
        "sha",
        nargs="?",
        help="Commit SHA to evaluate (from workflow_run.payload)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print resolved badges without modifying README.md",
    )
    parser.add_argument(
        "--reset",
        action="store_true",
        help="Reset all badges to unknown/lightgrey",
    )

    args = parser.parse_args()

    if args.reset:
        # Reset mode: set all badges to unknown
        readme_text = README_PATH.read_text(encoding="utf-8")
        badge_names = ["build", "unit", "security", "cov-tk"]
        for name in badge_names:
            img_tag = f'<img alt="{name.title()}" src="https://img.shields.io/badge/{name}-unknown-lightgrey?style=flat-square" />'
            if name == "cov-tk":
                img_tag = f'<img alt="AI Harness Coverage" src="https://img.shields.io/badge/harness%20coverage-unknown-lightgrey?style=flat-square" />'
            if name == "unit":
                img_tag = f'<img alt="Unit Tests" src="https://img.shields.io/badge/unit%20tests-unknown-lightgrey?style=flat-square" />'
            readme_text = replace_badge_block(readme_text, name, img_tag)
        README_PATH.write_text(readme_text, encoding="utf-8")
        print("Reset all badges to unknown/lightgrey")
        if not args.dry_run:
            git_commit_and_push(README_PATH, "reset", dry_run=args.dry_run)
        return

    if not args.sha:
        print("Usage: badge_updater.py <commit-sha> [--dry-run]", file=sys.stderr)
        sys.exit(1)

    # Read repo info from environment (set by GitHub Actions)
    import os
    github_repo = os.environ.get("GITHUB_REPOSITORY", "deeprnd/tickoni")
    repo_owner, repo_name = github_repo.split("/", 1)
    token = os.environ.get("GITHUB_TOKEN", "")

    # Step 1: Walk parent commits to find last successful SHA
    print(f"Starting parent-commit walk from {args.sha}")
    success_sha = find_last_successful_sha(repo_owner, repo_name, args.sha, token)

    if success_sha:
        print(f"Found last successful merge at {success_sha}")
    else:
        print(
            "No successful merge found within walk limit. "
            "All badges will show 'unknown/lightgrey'."
        )
        success_sha = args.sha  # use current SHA for badge resolution (will show unknown)

    # Step 2: Resolve badge statuses
    badges = resolve_badges(repo_owner, repo_name, success_sha, token)

    print("\nResolved badges:")
    for name, info in badges.items():
        print(f"  {name}: {info['status']} ({info['color']})")

    # Step 3: Update README.md
    if args.dry_run:
        print("\n[Dry run] Would update README.md with new badge URLs:")
        for name, info in badges.items():
            print(f"  {name}: {info['url']}")
        return

    readme_text = README_PATH.read_text(encoding="utf-8")
    updated = update_readme(readme_text, badges, dry_run=False)
    README_PATH.write_text(updated, encoding="utf-8")

    # Step 4: Commit and push
    print(f"\nCommitted and pushed README.md update for SHA {success_sha}")
    git_commit_and_push(README_PATH, success_sha)


if __name__ == "__main__":
    main()
