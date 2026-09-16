#!/usr/bin/env python3
import json
import os
import pathlib
import shutil
import subprocess
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: export_demo_conformance_bundle.py <repo-root> <output-dir>", file=sys.stderr)
        return 1
    repo = pathlib.Path(sys.argv[1]).resolve()
    out_dir = pathlib.Path(sys.argv[2]).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    binary = repo / "build/zig-out/bin/tickoni-supervisor"
    manifest = repo / "src/tickoni/demo/fixtures/demo.manifest.json"

    proc = subprocess.run(
        [str(binary), "demo", "investment", "--json", "--manifest", str(manifest)],
        cwd=repo,
        text=True,
        capture_output=True,
        check=True,
    )
    payload = json.loads(proc.stdout)
    (out_dir / "conformance.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    (out_dir / "comparison.json").write_text(json.dumps(payload["comparison"], indent=2, sort_keys=True) + "\n")

    blocked = []
    artifact_dir = out_dir / "referenced-artifacts"
    artifact_dir.mkdir(exist_ok=True)
    for entry in payload["suite"]:
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
    (out_dir / "blocked-diagnostics.json").write_text(json.dumps(blocked, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
