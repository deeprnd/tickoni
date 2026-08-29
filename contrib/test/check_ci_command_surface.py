#!/usr/bin/env python3
"""Validate that CI repository work uses qualified just recipes."""

from __future__ import annotations

import argparse
import re
import sys
import tempfile
from pathlib import Path

WORKFLOWS = (
    ".github/workflows/build-fd.yml",
    ".github/workflows/build-tk.yml",
    ".github/workflows/coverage.yml",
    ".github/workflows/quality.yml",
    ".github/workflows/security.yml",
    ".github/workflows/tests-long.yml",
    ".github/workflows/tests-short.yml",
    ".github/workflows/tests-xlong.yml",
)
ACTIONS = (
    ".github/actions/setup-public-gh-runner/action.yml",
    ".github/actions/build-fd-tk-libs/action.yml",
)
DELETED = (".github/workflows/benchmark.yml", ".github/workflows/book.yml")

FORBIDDEN = re.compile(
    r"\b(?:(?:sudo\s+)?(?:apt-get|apt|brew|choco|winget|zypper|pacman)\b|"
    r"(?:bash|sh|pwsh|powershell|(?<!setup-)python(?:3)?|python3\.\d+|zig|make|gmake|"
    r"prlimit)\b)|(?:\./?|\$\{[^}]+\}/)(?:contrib|scripts?)/[^\s;&|]+"
)
JUST = re.compile(r"\bjust\s+([A-Za-z0-9][A-Za-z0-9_-]*)")
UNSAFE_INPUT = re.compile(r"\$\{\{\s*inputs\.[^}]+\}\}")
RUN_KEY = re.compile(r"^(\s*)(?:-\s*)?run:\s*(.*)$")


def recipes(justfile: Path) -> set[str]:
    result: set[str] = set()
    for line in justfile.read_text().splitlines():
        match = re.match(r"^([A-Za-z][A-Za-z0-9_-]*)(?:\s+[^:]+)?\s*:", line)
        if match:
            result.add(match.group(1))
    return result


def command_blocks(path: Path) -> list[tuple[int, str]]:
    lines = path.read_text().splitlines()
    blocks: list[tuple[int, str]] = []
    for number, line in enumerate(lines, 1):
        match = RUN_KEY.match(line)
        if not match:
            continue
        indent, inline = match.groups()
        text = inline
        for continuation in lines[number:]:
            if continuation.strip() and len(continuation) - len(continuation.lstrip()) <= len(indent):
                break
            text += "\n" + continuation
        blocks.append((number, text))
    return blocks


def matrix_commands(path: Path) -> list[tuple[int, str]]:
    lines = path.read_text().splitlines()
    return [
        (number, line.split("command:", 1)[1].strip().strip("'\""))
        for number, line in enumerate(lines, 1)
        if re.search(r"\bcommand:\s*just\s+", line)
    ]


def inspect(root: Path) -> list[str]:
    errors: list[str] = []
    known = recipes(root / "justfile")
    covered = [root / path for path in (*WORKFLOWS, *ACTIONS)]

    for relative in (*WORKFLOWS, *ACTIONS):
        path = root / relative
        if not path.is_file():
            errors.append(f"missing covered CI file: {relative}")
            continue
        for line, command in command_blocks(path):
            command_for_scan = command.replace("setup-python-tools", "setup-pytools").replace("inputs.python-tools", "inputs.pytools")
            for match in UNSAFE_INPUT.finditer(command_for_scan):
                errors.append(f"{relative}:{line}: untrusted input interpolated into shell: {match.group(0)}")
            for match in FORBIDDEN.finditer(command_for_scan):
                errors.append(f"{relative}:{line}: direct command: {match.group(0).strip()}")
            for recipe in JUST.findall(command):
                if recipe not in known:
                    errors.append(f"{relative}:{line}: missing just recipe: {recipe}")
                elif not is_qualified(recipe, known):
                    errors.append(f"{relative}:{line}: bare just recipe: {recipe}")
        for line, command in matrix_commands(path):
            for recipe in JUST.findall(command):
                if recipe not in known:
                    errors.append(f"{relative}:{line}: missing just recipe: {recipe}")
                elif not is_qualified(recipe, known):
                    errors.append(f"{relative}:{line}: bare just recipe: {recipe}")

    for relative in DELETED:
        if (root / relative).exists():
            errors.append(f"deleted workflow still exists: {relative}")

    for relative in DELETED:
        for path in covered:
            if path.is_file() and relative in path.read_text():
                errors.append(f"{path.relative_to(root)} references deleted workflow {relative}")
    return sorted(set(errors))


def is_qualified(recipe: str, known: set[str]) -> bool:
    if recipe not in known:
        return False
    prefixes = ("build-", "test-", "setup-", "quality-", "security-")
    if not recipe.startswith(prefixes):
        return True
    if recipe in {"build-fd-tk-libs", "setup-python-tools"}:
        return True
    if any(platform in recipe for platform in ("-linux-", "-macos-", "-windows-")):
        return True
    return any(candidate.startswith(recipe + "-") for candidate in known)


def self_test(root: Path) -> None:
    with tempfile.TemporaryDirectory() as directory:
        fixture = Path(directory)
        (fixture / ".github/workflows").mkdir(parents=True)
        (fixture / ".github/actions/setup-public-gh-runner").mkdir(parents=True)
        (fixture / "justfile").write_text("build-linux-x86:\n    true\n")
        for relative in WORKFLOWS:
            path = fixture / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("jobs:\n  test:\n    steps:\n      - run: just build-linux-x86\n")
        for relative in ACTIONS:
            path = fixture / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("runs:\n  steps:\n    - run: just build-linux-x86\n")
        bad = fixture / WORKFLOWS[0]
        bad.write_text(bad.read_text() + "\n      - run: zig build\n")
        errors = inspect(fixture)
        if not any("direct command" in error for error in errors):
            raise AssertionError("synthetic direct command was not rejected")

        bad.write_text(bad.read_text() + "\n      - run: just \"${{ inputs.recipe }}\"\n")
        errors = inspect(fixture)
        if not any("untrusted input interpolated into shell" in error for error in errors):
            raise AssertionError("synthetic input interpolation was not rejected")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test(args.root)
        print("self-test: PASS")
        return 0
    errors = inspect(args.root)
    print(f"covered files: {len(WORKFLOWS) + len(ACTIONS)}")
    print(f"retained workflows: {len(WORKFLOWS)}")
    print(f"deleted workflows: {len(DELETED)}")
    if errors:
        print("command-surface: FAIL")
        print("\n".join(errors))
        return 1
    print("command-surface: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
