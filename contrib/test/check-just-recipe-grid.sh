#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

python3 - <<'PY'
import re
import subprocess
from pathlib import Path

expected = [
    "build-fd-linux-x86-gcc",
    "build-fd-linux-x86-clang",
    "build-fd-linux-arm-gcc",
    "build-fd-macos-x86",
    "build-fd-macos-arm",
    "build-fd-windows-x86",
    "build-fd-windows-arm",
    "build-tk-linux-x86",
    "build-tk-linux-arm",
    "build-tk-macos-x86",
    "build-tk-macos-arm",
    "build-tk-windows-x86",
    "build-tk-windows-arm",
    "test-unit-fd-linux-x86-gcc",
    "test-unit-fd-macos-x86",
    "test-unit-fd-macos-arm",
    "test-unit-fd-windows-x86",
    "test-unit-fd-windows-arm",
    "test-unit-tk-linux-x86",
    "test-unit-tk-linux-arm",
    "test-unit-tk-macos-x86",
    "test-unit-tk-macos-arm",
    "test-unit-tk-windows-x86",
    "test-unit-tk-windows-arm",
    "test-integration-tk-linux-x86",
    "test-integration-tk-linux-arm",
    "test-integration-tk-macos-x86",
    "test-integration-tk-macos-arm",
    "test-integration-tk-windows-x86",
    "test-integration-tk-windows-arm",
]

justfile = Path("justfile").read_text()
listing = subprocess.run(
    ["just", "--list"], check=False, text=True, capture_output=True
)
if listing.returncode:
    raise SystemExit(f"just --list failed: {listing.stderr.strip()}")
recipes = {
    match.group(1)
    for line in listing.stdout.splitlines()
    if (match := re.match(r"^\s{2}([^\s:#]+)", line))
}
missing = [name for name in expected if name not in recipes]
if missing:
    print("missing qualified recipes:")
    print("\n".join(f"  {name}" for name in missing))
    raise SystemExit(1)

for aggregate, required in {
    "test-unit-all": ["test-unit-tk", "test-unit-fd"],
    "test-integration-all": ["test-integration-tk", "test-integration-fd"],
}.items():
    match = re.search(
        rf"(?m)^{re.escape(aggregate)}:\n(?P<body>(?:    .*\n|\n)*)", justfile
    )
    body = match.group("body") if match else ""
    missing_calls = [name for name in required if f"just {name}" not in body]
    if missing_calls:
        print(f"{aggregate} is missing bare dispatcher calls: {', '.join(missing_calls)}")
        raise SystemExit(1)

recipe_bodies = {}
recipe_matches = list(re.finditer(r"(?m)^([a-zA-Z0-9_-]+):[^\n]*\n", justfile))
for index, match in enumerate(recipe_matches):
    start = match.end()
    end = recipe_matches[index + 1].start() if index + 1 < len(recipe_matches) else len(justfile)
    recipe_bodies[match.group(1)] = justfile[start:end]

linux_fd = recipe_bodies.get("test-unit-fd-linux-x86-gcc", "")
if "-Wl,-z,shstk" not in linux_fd:
    print("test-unit-fd-linux-x86-gcc must retain -Wl,-z,shstk")
    raise SystemExit(1)
for name, body in recipe_bodies.items():
    if name.startswith("test-unit-fd-") and not name.startswith("test-unit-fd-linux-x86-gcc"):
        if "-Wl,-z,shstk" in body:
            print(f"{name} contains Linux-only -Wl,-z,shstk")
            raise SystemExit(1)
        if "test-unit-tk" in body:
            print(f"{name} falls back to Tickoni tests")
            raise SystemExit(1)

print(f"recipe grid OK: {len(expected)} qualified recipes")
PY
