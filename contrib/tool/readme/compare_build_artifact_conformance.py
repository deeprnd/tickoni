#!/usr/bin/env python3
"""Compare build artifact conformance bundles across platforms.

Accepts 2+ conformance JSON files and does pairwise comparison of
deterministic fields.  Platform-specific fields (runtime_tier,
isolation_tier, baseline_runtime_tier, all_match) are ignored so that
bundles from different OS/arch pairs can be compared cleanly.
"""
import json
import pathlib
import sys


IGNORED_ARTIFACT_FIELDS = {"runtime_tier", "isolation_tier"}
IGNORED_TOP_LEVEL_FIELDS = {"comparison"}


def normalize_artifact(entry: dict) -> dict:
    return {k: v for k, v in entry.items() if k not in IGNORED_ARTIFACT_FIELDS}


def compare_two(lhs_path: str, rhs_path: str, label1: str, label2: str) -> int:
    """Compare two conformance bundles.  Returns 0 on match, 1 on mismatch."""
    lhs = json.loads(pathlib.Path(lhs_path).read_text())
    rhs = json.loads(pathlib.Path(rhs_path).read_text())

    for key in (set(lhs.keys()) | set(rhs.keys())) - IGNORED_TOP_LEVEL_FIELDS:
        if key == "suite":
            continue
        if key in ("comparison",):
            # comparison fields (baseline_runtime_tier, all_match, scenarios)
            # are platform-specific; skip cross-platform comparison
            continue
        if lhs.get(key) != rhs.get(key):
            print(f"[{label1}] vs [{label2}] top-level mismatch: {key}", file=sys.stderr)
            return 1

    lhs_suite = {entry["scenario"]: normalize_artifact(entry) for entry in lhs["suite"]}
    rhs_suite = {entry["scenario"]: normalize_artifact(entry) for entry in rhs["suite"]}
    if lhs_suite.keys() != rhs_suite.keys():
        print(f"[{label1}] vs [{label2}] scenario set mismatch", file=sys.stderr)
        return 1

    mismatches = []
    for scenario in sorted(lhs_suite.keys()):
        left = lhs_suite[scenario]
        right = rhs_suite[scenario]
        if left != right:
            for field in sorted(set(left.keys()) | set(right.keys())):
                if left.get(field) != right.get(field):
                    mismatches.append(
                        f"{scenario}.{field}: {left.get(field)!r} != {right.get(field)!r}"
                    )
    if mismatches:
        print(f"[{label1}] vs [{label2}] conformance mismatch:", file=sys.stderr)
        for item in mismatches:
            print(f"  - {item}", file=sys.stderr)
        return 1

    print(f"[{label1}] vs [{label2}] conformance OK")
    return 0


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: compare_build_artifact_conformance.py <json1> <json2> [json3 ...]", file=sys.stderr)
        return 1

    paths = sys.argv[1:]
    all_ok = True

    # Pairwise comparison against first file (baseline)
    baseline = paths[0]
    baseline_label = pathlib.Path(baseline).stem
    for p in paths[1:]:
        label = pathlib.Path(p).stem
        if compare_two(baseline, p, baseline_label, label) != 0:
            all_ok = False

    # Also pairwise compare remaining files against each other
    for i in range(1, len(paths)):
        for j in range(i + 1, len(paths)):
            label_i = pathlib.Path(paths[i]).stem
            label_j = pathlib.Path(paths[j]).stem
            if compare_two(paths[i], paths[j], label_i, label_j) != 0:
                all_ok = False

    if all_ok:
        print("all platform conformance bundles match on deterministic fields")
    else:
        print("conformance mismatch detected across platforms", file=sys.stderr)
    return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
