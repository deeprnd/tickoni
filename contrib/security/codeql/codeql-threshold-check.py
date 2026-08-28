#!/usr/bin/env python3

import json
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "[security-codeql] usage: python3 contrib/codeql-threshold-check.py "
            "<sarif-path> <high-security-threshold>",
            file=sys.stderr,
        )
        return 1

    sarif_path = Path(sys.argv[1])
    try:
        high_security_threshold = float(sys.argv[2])
    except ValueError:
        print("[security-codeql] threshold must be a number", file=sys.stderr)
        return 1

    sarif = json.loads(sarif_path.read_text(encoding="utf-8"))
    run = (sarif.get("runs") or [{}])[0]
    driver_rules = run.get("tool", {}).get("driver", {}).get("rules", [])
    extension_rules = []
    for extension in run.get("tool", {}).get("extensions", []):
        extension_rules.extend(extension.get("rules", []))

    rule_map = {rule.get("id"): rule for rule in [*driver_rules, *extension_rules]}
    results = run.get("results", [])

    high_or_higher_findings = []
    for result in results:
        rule = rule_map.get(result.get("ruleId"), {})
        level = result.get("level") or rule.get("defaultConfiguration", {}).get("level") or "warning"
        try:
            security_severity = float(rule.get("properties", {}).get("security-severity", "0"))
        except (TypeError, ValueError):
            security_severity = 0.0

        if level != "error" and security_severity < high_security_threshold:
            continue

        uri = (
            result.get("locations", [{}])[0]
            .get("physicalLocation", {})
            .get("artifactLocation", {})
            .get("uri", "unknown")
        )
        high_or_higher_findings.append(
            {
                "level": level,
                "rule_id": result.get("ruleId"),
                "security_severity": security_severity,
                "uri": uri,
            }
        )

    if high_or_higher_findings:
        print(
            "[security-codeql] analysis failed with "
            f"{len(high_or_higher_findings)} high-threshold result(s). "
            f"Review {sarif_path}.",
            file=sys.stderr,
        )
        for finding in high_or_higher_findings[:10]:
            print(
                "[security-codeql] high_threshold "
                f"ruleId={finding['rule_id']} "
                f"level={finding['level']} "
                f"security_severity={finding['security_severity']:.1f} "
                f"location={finding['uri']}",
                file=sys.stderr,
            )
        return 1

    print(
        "[security-codeql] analysis passed with "
        f"{len(results)} total result(s) and 0 high-threshold result(s). "
        f"Report: {sarif_path}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
