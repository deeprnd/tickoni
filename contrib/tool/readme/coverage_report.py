#!/usr/bin/env python3
"""Parse coverage data, write Istanbul-format summary JSON, and check thresholds.

Thresholds are read from a per-component config file (vitest-style):
  { "coverage": { "thresholds": { "lines": 20, "statements": 20, "branches": 20, "functions": 20 } } }

Usage:
  python3 contrib/readme/coverage_report.py coverage-fd <covdir> <output.json> --config contrib/test/coverage-fd.json
  python3 contrib/readme/coverage_report.py coverage-tk <kcov-merged-dir> <output.json> --config contrib/test/coverage-tk.json
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
REPO_ROOT = SCRIPT_DIR.parent.parent

METRICS = ("lines", "statements", "branches", "functions")


# ── helpers ────────────────────────────────────────────────────────────────

def _pct(covered: int, total: int) -> float:
    if total == 0:
        return 100.0
    return round(covered / total * 100, 1)


def _color_label(pct: float) -> str:
    if pct < 40:
        return "red"
    if pct < 80:
        return "orange"
    if pct < 90:
        return "yellowgreen"
    return "brightgreen"


def _load_thresholds(config_path: Path) -> dict:
    if not config_path.exists():
        raise FileNotFoundError(f"Coverage config not found: {config_path}")
    data = json.loads(config_path.read_text(encoding="utf-8"))
    thresholds = data.get("coverage", {}).get("thresholds", {})
    return {m: thresholds.get(m, 0) for m in METRICS}


def _write_summary(summary: dict, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")


def _check_thresholds(summary: dict, thresholds: dict) -> int:
    """Check all metrics. Metrics with total==0 are skipped (not measured)."""
    failed = False
    for metric in METRICS:
        threshold = thresholds.get(metric, 0)
        stats = summary.get("total", {}).get(metric, {})
        total = stats.get("total", 0)
        pct = stats.get("pct", 0.0)

        if total == 0:
            print(f"  {metric:<12s}  N/A (not measured by this tool)")
            continue

        color = _color_label(pct)
        ok = pct >= threshold
        status = "ok" if ok else "FAIL"
        print(f"  {metric:<12s}  {pct:5.1f}%  (threshold {threshold:.1f}%)  [{color}]  {status}")
        if not ok:
            failed = True

    return 1 if failed else 0


def _build_summary(
    lines_covered: int, lines_total: int,
    branches_covered: int = 0, branches_total: int = 0,
    functions_covered: int = 0, functions_total: int = 0,
) -> dict:
    return {
        "total": {
            "lines":      {"total": lines_total,     "covered": lines_covered,     "skipped": 0, "pct": _pct(lines_covered,     lines_total)},
            "statements": {"total": lines_total,     "covered": lines_covered,     "skipped": 0, "pct": _pct(lines_covered,     lines_total)},
            "branches":   {"total": branches_total,  "covered": branches_covered,  "skipped": 0, "pct": _pct(branches_covered,  branches_total)},
            "functions":  {"total": functions_total, "covered": functions_covered, "skipped": 0, "pct": _pct(functions_covered, functions_total)},
        }
    }


# ── fd (LLVM source-based coverage) ───────────────────────────────────────

def cmd_coverage_fd(covdir: Path, output: Path, config: Path) -> int:
    profdata = covdir / "cov.profdata"
    unitdir = covdir / "unit-test"

    if not profdata.exists():
        print(f"ERROR: {profdata} not found — run the unit tests with EXTRAS=llvm-cov first", file=sys.stderr)
        return 1

    # Use compiled test binaries instead of individual .o files.
    # Test binaries contain binary IDs that allow llvm-cov to match coverage
    # data directly (~0.1s). Individual .o files lack binary IDs and force
    # llvm-cov to scan all symbols in 12,918+ functions (~900s+).
    test_bins = sorted([
        str(b) for b in unitdir.iterdir()
        if b.is_file() and b.name.startswith("test_") and not b.name.startswith("bench_")
    ])

    if not test_bins:
        print(f"ERROR: no test binaries found in {unitdir}", file=sys.stderr)
        return 1

    cmd = [
        "llvm-cov", "export",
        "--format=text",
        "--summary-only",
        f"--instr-profile={profdata}",
        "--ignore-filename-regex=(test_|fuzz_)*\\.c",
    ] + test_bins

    # Disable debuginfod — llvm-cov tries to query debuginfod.ubuntu.com
    # for debug symbol data and hangs when the DNS resolver (systemd-resolved
    # stub at 127.0.0.53) is unreachable (no network, container, etc.).
    cov_env = os.environ.copy()
    cov_env["DEBUGINFOD_URLS"] = ""

    t0 = time.monotonic()
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=900,
        env=cov_env,
    )
    elapsed = round(time.monotonic() - t0, 1)
    print(f"[coverage] llvm-cov export took {elapsed}s ({len(test_bins)} test binaries)", file=sys.stderr)
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        raise RuntimeError(f"llvm-cov export failed (exit {result.returncode})")

    totals = json.loads(result.stdout)["data"][0]["totals"]
    lines     = totals["lines"]
    branches  = totals.get("branches", {"count": 0, "covered": 0})
    functions = totals["functions"]

    summary = _build_summary(
        lines_covered=lines["covered"],     lines_total=lines["count"],
        branches_covered=branches.get("covered", 0), branches_total=branches.get("count", 0),
        functions_covered=functions["covered"], functions_total=functions["count"],
    )
    _write_summary(summary, output)

    thresholds = _load_thresholds(config)
    return _check_thresholds(summary, thresholds)


# ── tk (kcov) ──────────────────────────────────────────────────────────────

def cmd_coverage_tk(kcov_dir: Path, output: Path, config: Path) -> int:
    # kcov nests coverage.json one level deep: <outdir>/kcov-merged/ or <outdir>/<name>.<hash>/
    coverage_json = kcov_dir / "coverage.json"
    if not coverage_json.exists():
        candidates = sorted(kcov_dir.glob("*/coverage.json"))
        if not candidates:
            print(f"ERROR: {coverage_json} not found — kcov did not produce output", file=sys.stderr)
            return 1
        coverage_json = candidates[0]

    data = json.loads(coverage_json.read_text(encoding="utf-8"))
    covered = int(data.get("covered_lines", 0))
    total   = int(data.get("total_lines", 0))
    # Use kcov's own percentage to avoid rounding discrepancies.
    pct = float(data.get("percent_covered", _pct(covered, total)))

    # kcov only measures line coverage. branches and functions are not tracked;
    # leaving their totals at 0 causes _check_thresholds to report them as N/A.
    summary = _build_summary(lines_covered=covered, lines_total=total)
    for m in ("lines", "statements"):
        summary["total"][m]["pct"] = round(pct, 1)

    _write_summary(summary, output)

    thresholds = _load_thresholds(config)
    return _check_thresholds(summary, thresholds)


# ── main ───────────────────────────────────────────────────────────────────

def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(
        description="Parse coverage output, write Istanbul-format JSON, check thresholds."
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    for name in ("coverage-fd", "coverage-tk"):
        sp = sub.add_parser(name)
        sp.add_argument("covdir",  type=Path, help="Coverage data directory")
        sp.add_argument("output",  type=Path, help="Output coverage-summary.json path")
        sp.add_argument("--config", type=Path, required=True,
                        help="Threshold config (e.g. contrib/test/coverage-fd.json)")

    args = parser.parse_args()

    try:
        if args.cmd == "coverage-fd":
            sys.exit(cmd_coverage_fd(args.covdir, args.output, args.config))
        elif args.cmd == "coverage-tk":
            sys.exit(cmd_coverage_tk(args.covdir, args.output, args.config))
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
