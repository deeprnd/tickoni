#!/usr/bin/env python3
"""Verify that build-artifact conformance JSON was written by the system suite test.

The conformance JSON is produced by the Zig integration test
(test_investment_fixture_system_suite.zig) when the env var
TICKONI_CONFORMANCE_JSON is set. This script simply validates that the
expected files exist in the output directory and that the JSON is parseable.
"""

import json
import pathlib
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "usage: export_build_artifact_conformance.py <repo-root> <output-dir>",
            file=sys.stderr,
        )
        return 1

    repo = pathlib.Path(sys.argv[1]).resolve()
    out_dir = pathlib.Path(sys.argv[2]).resolve()

    # Verify conformance.json exists and is valid JSON.
    conformance = out_dir / "conformance.json"
    if not conformance.exists():
        print(f"ERROR: missing {conformance}", file=sys.stderr)
        return 1

    try:
        data = json.loads(conformance.read_text())
    except json.JSONDecodeError as exc:
        print(f"ERROR: invalid JSON in {conformance}: {exc}", file=sys.stderr)
        return 1

    # Validate required top-level keys.
    if "suite" not in data:
        print("ERROR: conformance.json missing 'suite' key", file=sys.stderr)
        return 1
    if "comparison" not in data:
        print("ERROR: conformance.json missing 'comparison' key", file=sys.stderr)
        return 1

    # Verify all 3 scenarios are present.
    scenario_names = {entry["scenario"] for entry in data["suite"]}
    expected = {"allowed", "oversized_blocked", "restricted_instrument"}
    if scenario_names != expected:
        print(
            f"ERROR: expected scenarios {expected}, got {scenario_names}",
            file=sys.stderr,
        )
        return 1

    print(f"conformance: {len(data['suite'])} scenarios OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
