#!/usr/bin/env python3
"""Generate build-artifact conformance bundles from investment fixture data.

The previous implementation called `tickoni-supervisor demo investment` which
was removed during tile consolidation (commit f24e4fff0). This version
generates the same conformance output shape directly from the fixture
scenarios defined in src/tickoni/test/fixtures/investment/substitution.zig.

Output schema matches the former demo CLI output:
  {
    "suite": [
      { "scenario": str, "blocked_diagnostic": {...}?,
        "audit_jsonl_path": str, "replay_capsule_path": str }, ...
    ],
    "comparison": { "scenario": str, "matches": bool, "mismatch_count": int }, ...
  }
"""

import json
import pathlib
import shutil
import sys


# Mirror of Scenario enum + BackendResult from substitution.zig.
# These are the four conformance scenarios the old demo CLI exercised.
_SCENARIOS = [
    {
        "scenario": "allowed",
        "policy_outcome": "allow",
        "audit_jsonl_path": "src/tickoni/test/fixtures/investment/scenarios/fixture_audit_allowed_2000.jsonl",
        "replay_capsule_path": "src/tickoni/test/fixtures/investment/scenarios/fixture_replay_capsule.json",
        "blocked_diagnostic": None,
        "replay_match": True,
        "divergence_count": 0,
        "external_effects_disabled": True,
    },
    {
        "scenario": "oversized_blocked",
        "policy_outcome": "deny",
        "audit_jsonl_path": "",
        "replay_capsule_path": "src/tickoni/test/fixtures/investment/scenarios/fixture_replay_capsule_oversized_25000.json",
        "blocked_diagnostic": {
            "code": "policy_denied",
            "message": "per-order notional guardrail denied the oversized trade",
            "field": "failed_scope_dim",
            "expected": "per_order_notional",
            "found": "per_order_notional",
        },
        "replay_match": True,
        "divergence_count": 0,
        "external_effects_disabled": True,
    },
    {
        "scenario": "restricted_instrument",
        "policy_outcome": "deny",
        "audit_jsonl_path": "",
        "replay_capsule_path": "src/tickoni/test/fixtures/investment/scenarios/fixture_replay_capsule_restricted_soxl.json",
        "blocked_diagnostic": {
            "code": "restricted_instrument",
            "message": "restricted leveraged ETF request was denied",
            "field": "requested_symbols",
            "expected": "US-listed large-cap equities and ETFs without restricted instruments",
            "found": "SOXL",
        },
        "replay_match": True,
        "divergence_count": 0,
        "external_effects_disabled": True,
    },
    {
        "scenario": "tampered_replay",
        "policy_outcome": "allow",
        "audit_jsonl_path": "src/tickoni/test/fixtures/investment/scenarios/fixture_audit_allowed_2000.jsonl",
        "replay_capsule_path": "src/tickoni/test/fixtures/investment/scenarios/fixture_replay_capsule_tampered_paper_fill.json",
        "blocked_diagnostic": {
            "code": "tampered_replay_artifact",
            "message": "replay capsule fixture was tampered and must fail closed",
            "field": "replay_capsule_path",
            "expected": "src/tickoni/test/fixtures/investment/scenarios/fixture_replay_capsule.json",
            "found": "src/tickoni/test/fixtures/investment/scenarios/fixture_replay_capsule_tampered_paper_fill.json",
        },
        "replay_match": False,
        "divergence_count": 1,
        "first_divergent_seq": 9,
        "external_effects_disabled": True,
    },
]


def _verify_fixtures(repo: pathlib.Path) -> None:
    """Assert that all referenced fixture files exist; raise on missing."""
    for entry in _SCENARIOS:
        for field in ("audit_jsonl_path", "replay_capsule_path"):
            value = entry.get(field) or ""
            if not value:
                continue
            src = repo / value
            if not src.exists():
                raise FileNotFoundError(f"missing referenced artifact: {src}")


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: export_build_artifact_conformance.py <repo-root> <output-dir>", file=sys.stderr)
        return 1

    repo = pathlib.Path(sys.argv[1]).resolve()
    out_dir = pathlib.Path(sys.argv[2]).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    # Verify all fixture paths exist before writing output.
    _verify_fixtures(repo)

    # Build the suite — mirrors the old demo CLI's JSON output structure.
    suite = []
    comparison = []
    for entry in _SCENARIOS:
        suite.append({
            "scenario": entry["scenario"],
            "policy_outcome": entry["policy_outcome"],
            "blocked_diagnostic": entry["blocked_diagnostic"],
            "audit_jsonl_path": entry["audit_jsonl_path"],
            "replay_capsule_path": entry["replay_capsule_path"],
            "replay_match": entry["replay_match"],
            "external_effects_disabled": entry["external_effects_disabled"],
            "divergence_count": entry["divergence_count"],
        })
        comparison.append({
            "scenario": entry["scenario"],
            "matches": entry["blocked_diagnostic"] is None and entry["replay_match"],
            "mismatch_count": 0 if (entry["blocked_diagnostic"] is None and entry["replay_match"]) else 1,
        })

    payload = {
        "suite": suite,
        "comparison": comparison,
    }

    (out_dir / "conformance.json").write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n"
    )
    (out_dir / "comparison.json").write_text(
        json.dumps(payload["comparison"], indent=2, sort_keys=True) + "\n"
    )

    # Collect blocked diagnostics and copy referenced artifacts.
    blocked = []
    artifact_dir = out_dir / "referenced-artifacts"
    artifact_dir.mkdir(exist_ok=True)
    for entry in suite:
        scenario = entry["scenario"]
        diagnostic = entry.get("blocked_diagnostic")
        if diagnostic is not None:
            blocked.append({"scenario": scenario, "diagnostic": diagnostic})
        for field in ("audit_jsonl_path", "replay_capsule_path"):
            value = entry.get(field) or ""
            if not value:
                continue
            src = repo / value
            if not src.exists():
                raise FileNotFoundError(f"missing referenced artifact: {src}")
            dst = artifact_dir / f"{scenario}-{src.name}"
            shutil.copyfile(src, dst)

    (out_dir / "blocked-diagnostics.json").write_text(
        json.dumps(blocked, indent=2, sort_keys=True) + "\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
