#!/usr/bin/env python3
"""Detect changes to the Firedancer harness files watched by Tickoni.

Reads doc/knowledge/engine-harness-snapshot.json, hashes the current
versions of every tracked file, and exits 1 with a diff report if
any hash diverges.  Exit 0 means the harness is still in sync.

Usage:
    python3 contrib/engine/engine_check_changes.py
    python3 contrib/engine/engine_check_changes.py --update   # refresh manifest
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path


def file_sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Check whether watched Firedancer harness files have changed."
    )
    parser.add_argument(
        "--update",
        action="store_true",
        help="Regenerate the manifest file from current sources instead of checking.",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent.parent
    manifest_path = repo_root / "doc" / "knowledge" / "engine-harness-snapshot.json"

    # Build the file list from the manifest if it exists, else hard-coded default.
    if manifest_path.exists():
        with open(manifest_path) as f:
            manifest = json.load(f)
        watched_files = list(manifest.get("files", {}).keys())
    else:
        # Canonical list from tile-orchestration.md "Orchestration Drift Guard" section.
        watched_files = [
            "src/disco/topo/fd_topo_run.c",
            "src/disco/topo/fd_topo.h",
            "src/disco/topo/fd_topo.c",
            "src/disco/stem/fd_stem.c",
            "src/app/shared/commands/run/run.c",
            "src/app/shared/commands/run/run1.c",
            "src/app/shared/boot/fd_boot.c",
            "src/util/sandbox/fd_sandbox.c",
            "src/util/sandbox/fd_sandbox.h",
            "src/util/sandbox/fd_sandbox_private.h",
            "src/disco/metrics/fd_metrics.c",
            "src/disco/metrics/fd_metrics.h",
            "src/disco/metrics/fd_metrics_base.h",
        ]

    if args.update:
        # Regenerate manifest.
        import subprocess

        result = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            capture_output=True,
            text=True,
            cwd=str(repo_root),
        )
        commit = result.stdout.strip()
        result2 = subprocess.run(
            ["git", "log", "-1", "--format=%ci"],
            capture_output=True,
            text=True,
            cwd=str(repo_root),
        )
        date = result2.stdout.strip()

        new_files: dict[str, str] = {}
        missing = []
        for rel in watched_files:
            full = repo_root / rel
            if full.exists():
                new_files[rel] = file_sha256(str(full))
            else:
                missing.append(rel)

        if missing:
            print("ERROR: missing files, cannot update manifest:", file=sys.stderr)
            for m in missing:
                print(f"  MISSING: {m}", file=sys.stderr)
            return 1

        new_manifest = {
            "commit": commit,
            "date": date,
            "files": new_files,
        }
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        with open(manifest_path, "w") as f:
            json.dump(new_manifest, f, indent=2)
            f.write("\n")
        print(f"Manifest updated: {manifest_path}")
        print(f"  Commit: {commit}")
        print(f"  Files tracked: {len(new_files)}")
        return 0

    # --- Check mode ---
    if not manifest_path.exists():
        print(
            f"ERROR: manifest not found at {manifest_path}",
            file=sys.stderr,
        )
        print(
            "Run: python3 contrib/engine/engine_check_changes.py --update",
            file=sys.stderr,
        )
        return 1

    with open(manifest_path) as f:
        manifest = json.load(f)

    expected_files = manifest.get("files", {})
    if not expected_files:
        print(
            "ERROR: manifest has no files entry. Refresh it with --update",
            file=sys.stderr,
        )
        return 1

    diffs: list[str] = []
    missing: list[str] = []

    for rel, expected_hash in expected_files.items():
        full = repo_root / rel
        if not full.exists():
            missing.append(rel)
            continue
        current_hash = file_sha256(str(full))
        if current_hash != expected_hash:
            diffs.append(
                f"  {rel}\n"
                f"    expected: {expected_hash}\n"
                f"    current:  {current_hash}"
            )

    if missing:
        print(
            "ERROR: the following watched files are missing from the workspace:",
            file=sys.stderr,
        )
        for m in missing:
            print(f"  MISSING: {m}", file=sys.stderr)
        return 1

    if diffs:
        print(
            "FAIL: watched Firedancer harness files have changed since the last "
            "snapshot.\n"
            "Review the changes and port them into Tickoni, then run:\n"
            "  python3 contrib/engine/engine_check_check_changes.py --update\n",
            file=sys.stderr,
        )
        for d in diffs:
            print(d, file=sys.stderr)
        return 1

    print(f"OK: {len(expected_files)} watched harness files are in sync.")
    print(f"  Snapshot commit: {manifest.get('commit', 'unknown')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
