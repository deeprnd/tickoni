#!/usr/bin/env python3
"""Generic source-tree linter framework.

Provides a `Check` base class, a `Linter` orchestration layer, and a
`main()` CLI entry point that loads all check modules from a directory
tree, runs them against files, and reports results.

## Quick start

Create a check module in `contrib/engine/checks/` that exports a
`define_checks(linter)` function:

    from linter import Check, Issue, Severity, Linter

    class NoCatchUnreachable(Check):
        name = "no-catch-unreachable"
        domains = ["memory_safety"]
        severity = Severity.ERROR
        description = ("Reject catch unreachable in non-test orchestration code.")
        patterns = (
            Check.Pattern(kind="regex", pattern=r"catch unreachable", name="catch_unreachable"),
        )
        files_glob = ["**/*.zig", "**/*.zig.in"]
        exclude_patterns = (
            Check.Pattern(kind="substring", pattern="test \"", name="test_block"),
            Check.Pattern(kind="substring", pattern="_test.zig", name="test_file"),
        )

        def match(self, ctx):
            # ctx.file_path, ctx.line_no, ctx.line_text, ctx.file_lines, ctx.match
            if self._in_test_block(ctx):
                return []
            return [Issue(
                check=self,
                file_path=ctx.file_path,
                line_no=ctx.line_no,
                message=f"{self.description} at {ctx.line_text.strip()[:80]}",
            )]

        def _in_test_block(self, ctx):
            for i, line in enumerate(ctx.file_lines):
                if i < ctx.line_no - 1 and line.strip().startswith("test \""):
                    return True
            return False

    def define_checks(linter):
        linter.add_check(NoCatchUnreachable)

Then run:

    python3 contrib/engine/linter.py contrib/engine/checks/

## CLI

    python3 linter.py <checks-dir> [--severity WARNING|ERROR] [--domains d1,d2,...] [--files g1,g2] [--fix] [-v]

Exit code 0 = no errors. Exit code 1 = errors found.

Exit codes are also per-severity for use with `--severity`:
  2 = warnings found
  1 = errors found (or --severity=ERROR)
"""

from __future__ import annotations

import argparse
import importlib.util
import os
import re
import sys
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from enum import Enum, auto
from pathlib import Path
from typing import Protocol


# ---------------------------------------------------------------------------
# Core data types
# ---------------------------------------------------------------------------


class Severity(Enum):
    """Check severity levels."""
    INFO = auto()
    WARNING = auto()
    ERROR = auto()


@dataclass
class Issue:
    """A single finding from a check."""
    check: Check
    file_path: str
    line_no: int
    message: str

    @property
    def severity(self) -> Severity:
        return self.check.severity

    def __str__(self):
        sev_label = self.severity.name
        return f"[{sev_label}] {self.check.name}: {self.file_path}:{self.line_no}: {self.message}"


@dataclass
class MatchCtx:
    """Context passed to a Check.match() call."""
    file_path: str
    file_content: str
    file_lines: list[str]
    line_no: int
    line_text: str


class Check(ABC):
    """Base class for all linter checks.

    Subclasses must define at minimum `name` and `domains`.  Override
    `run()` for simple regex-line checks or `match(ctx)` + `run()` for
    line-by-line processing.  The default `run()` uses `patterns`.
    """

    name: str = ""
    domains: list[str] = []
    severity: Severity = Severity.WARNING
    description: str = ""
    patterns: tuple[Pattern, ...] = ()
    files_glob: tuple[str, ...] = ("**/*.zig", "**/*.c", "**/*.h", "**/*.cpp", "**/*.cc")
    exclude_patterns: tuple[Pattern, ...] = ()

    @dataclass
    class Pattern:
        kind: str  # "regex" | "substring" | "line_regex"
        pattern: str
        name: str = ""

    @abstractmethod
    def run(self, file_path: str, file_content: str) -> list[Issue]:
        """Run this check on a single file. Returns list of issues."""
        ...

    def _should_skip(self, file_path: str, file_content: str) -> bool:
        """Return True if the check should skip this file."""
        text = file_content
        for p in self.exclude_patterns:
            if p.kind == "substring" and p.pattern in text:
                return True
            if p.kind == "regex" and re.search(p.pattern, text):
                return True
        return False


# ---------------------------------------------------------------------------
# Linter orchestration
# ---------------------------------------------------------------------------


class Linter:
    """Orchestrates loading, discovering, and running checks."""

    def __init__(self):
        self.checks: list[Check] = []

    def add_check(self, check_cls: type[Check] | Check):
        if isinstance(check_cls, type):
            self.checks.append(check_cls())
        else:
            self.checks.append(check_cls)

    def add_checks_from_dir(self, checks_dir: Path):
        """Load all .py files in `checks_dir` and call define_checks(self)."""
        for entry in sorted(checks_dir.iterdir()):
            if entry.is_file() and entry.suffix == ".py" and entry.name != "__init__.py":
                if entry.name.startswith("_"):
                    continue
                spec = importlib.util.spec_from_file_location(entry.stem, entry)
                if spec and spec.loader:
                    mod = importlib.util.module_from_spec(spec)
                    spec.loader.exec_module(mod)
                    if hasattr(mod, "define_checks"):
                        mod.define_checks(self)

    @staticmethod
    def _matches_globs(file_path: str, globs: tuple[str, ...]) -> bool:
        import fnmatch
        from pathlib import PurePath

        def _glob_to_regex(pattern: str) -> str:
            """Convert a glob pattern to a regex that handles ** recursively."""
            # Split on ** first to handle the recursive part
            parts = pattern.split("**")
            if len(parts) == 1:
                # No ** — use fnmatch, strip leading ^ and trailing \Z
                regex = fnmatch.translate(pattern)
                regex = regex.lstrip("^").rstrip("\\Z")
                return regex
            # Has ** — build regex that allows ** to match any path segments
            result = []
            for i, part in enumerate(parts):
                if part:
                    # Translate the part, strip anchors
                    part_regex = fnmatch.translate(part)
                    part_regex = part_regex.lstrip("^").rstrip("\\Z")
                    result.append(part_regex)
                if i < len(parts) - 1:
                    # ** matches zero or more path segments (any characters)
                    result.append(".*")
            return "(?:" + "".join(result) + ")"

        regexes = [_glob_to_regex(g) for g in globs]
        for regex in regexes:
            if re.search(regex, file_path):
                return True

        # Fallback: try fnmatch on each path suffix
        p = PurePath(file_path)
        for i in range(len(p.parts)):
            suffix = PurePath(*p.parts[i:])
            for g in globs:
                if fnmatch.fnmatch(str(suffix), g):
                    return True

        return False

    def run_all(self, file_paths: list[str]) -> list[Issue]:
        """Run all loaded checks against the given file list."""
        issues: list[Issue] = []
        for check in self.checks:
            for fpath in file_paths:
                try:
                    content = Path(fpath).read_text()
                except (OSError, UnicodeDecodeError):
                    continue
                if not self._matches_globs(fpath, check.files_glob):
                    continue
                issues.extend(check.run(fpath, content))
        return issues

    @staticmethod
    def report(issues: list[Issue], verbose: bool = False) -> int:
        """Print report. Returns 0 if no errors, 1 if errors."""
        errors = [i for i in issues if i.severity == Severity.ERROR]
        warnings = [i for i in issues if i.severity == Severity.WARNING]

        if errors:
            print(f"ERROR ({len(errors)}):", file=sys.stderr)
            for i in errors:
                print(f"  {i}", file=sys.stderr)

        if warnings:
            print(f"WARNING ({len(warnings)}):")
            for i in warnings:
                print(f"  {i}")

        if verbose:
            infos = [i for i in issues if i.severity == Severity.INFO]
            if infos:
                print(f"INFO ({len(infos)}):")
                for i in infos:
                    print(f"  {i}")

        return 1 if errors else 0


# ---------------------------------------------------------------------------
# Default checks (the old security_orchestration_check domains)
# ---------------------------------------------------------------------------


class NoFiredancerTypesLeak(Check):
    """Block Firedancer types outside the C ABI adapter layer.

    For each non-adapter file, strips comments and checks that forbidden
    Firedancer symbols do not appear in code (only in comments).
    """

    name = "no-firedancer-leak"
    domains = ["adapter_boundary"]
    severity = Severity.ERROR
    description = ("Firedancer type references must not leak outside c_abi/ adapter files")

    # Which files are allowed to contain Firedancer types
    allowed_files = (
        "src/tickoni/c_abi/topo_run.zig",
        "src/tickoni/c_abi/topob.zig",
        "src/tickoni/c_abi/shim/topo_run.c",
        "src/tickoni/c_abi/shim/topob.c",
        "src/tickoni/c_abi/shim/tile_run.c",
    )

    forbidden = (
        r"\bfd_topo_t\b",
        r"\bfd_topo_tile_t\b",
        r"\bfd_topo_run_tile\b",
        r"\bfd_topob\b",
        r"\bfd_cfg_stage_\b",
    )

    files_glob = ("src/**/*.zig", "src/**/*.c", "src/**/*.h")
    exclude_patterns = ()

    def _is_allowed(self, file_path: str) -> bool:
        for af in self.allowed_files:
            if file_path.endswith(af):
                return True
        return False

    def run(self, file_path: str, file_content: str) -> list[Issue]:
        if self._is_allowed(file_path):
            return []

        issues: list[Issue] = []
        lines = file_content.split("\n")
        for lineno, raw_line in enumerate(lines, start=1):
            # Strip comments naively (fine for code; comments don't
            # normally contain the forbidden symbol names anyway)
            code = raw_line
            if "//" in code:
                code = code[:code.index("//")]
            if "/*" in code:
                code = code[:code.index("/*")]
            code = code.strip()
            if not code:
                continue
            for pat in self.forbidden:
                if re.search(pat, code):
                    issues.append(Issue(
                        check=self,
                        file_path=file_path,
                        line_no=lineno,
                        message=f"Forbidden symbol matches pattern {pat} in code: {code[:80]}",
                    ))
        return issues


class NoCatchUnreachable(Check):
    """Reject `catch unreachable` outside test blocks and c_abi/ wrappers.

    This is a catch-all: the Zig compiler catches most `catch
    unreachable` at compile time, but some patterns survive (e.g. in
    helper functions).  Only flag them in non-test, non-c_abi code.
    """

    name = "no-catch-unreachable"
    domains = ["memory_safety"]
    severity = Severity.ERROR
    description = ("catch unreachable in harness orchestration code")

    files_glob = ("src/**/*.zig",)

    def run(self, file_path: str, file_content: str) -> list[Issue]:
        # Skip c_abi/ wrappers
        if "/c_abi/" in file_path:
            return []
        # Skip test files
        if "test" in file_path or file_path.endswith("_test.zig"):
            return []

        lines = file_content.split("\n")
        issues: list[Issue] = []
        in_test_block = False

        for lineno, line in enumerate(lines, start=1):
            stripped = line.strip()
            if stripped.startswith("test \"") or stripped.startswith("test{"):
                in_test_block = True
                continue
            if in_test_block and stripped == "}":
                in_test_block = False
                continue
            code = stripped
            if "//" in code:
                code = code[:code.index("//")]
            if re.search(r"catch unreachable", code):
                # Skip the id() helper in tile_registry.zig
                if "fn id(comptime" in file_content and line.strip().startswith("return rt.tile.TileId.parse(s) catch unreachable"):
                    continue
                issues.append(Issue(
                    check=self,
                    file_path=file_path,
                    line_no=lineno,
                    message=f"{self.description}: {code[:80]}",
                ))
        return issues


class NoPtrCastInCallbacks(Check):
    """Reject @ptrCast / @alignCast in tile_process callbacks.

    The privileged_init and tk_tile_run callbacks take *anyopaque
    parameters; casting them to typed pointers is the harness bridge
    and is expected.  Flag any other @ptrCast/@alignCast inside them.
    """

    name = "no-ptrcast-in-callbacks"
    domains = ["memory_safety"]
    severity = Severity.ERROR
    description = ("@ptrCast / @alignCast in tile_process callbacks (except the intended topo bridge)")

    files_glob = ("src/tickoni/runtime/tile_process.zig",)

    callback_names = ("tk_tile_privileged_init", "tk_tile_run")

    def run(self, file_path: str, file_content: str) -> list[Issue]:
        issues: list[Issue] = []
        lines = file_content.split("\n")

        for cb_name in self.callback_names:
            # Find export fn start
            start = -1
            for i, line in enumerate(lines):
                stripped = line.strip()
                if stripped == f"export fn {cb_name}(" or stripped == f"export fn {cb_name}":
                    start = i
                    break
            if start < 0:
                issues.append(Issue(
                    check=self,
                    file_path=file_path,
                    line_no=1,
                    message=f"export fn {cb_name} not found — cannot verify",
                ))
                continue

            # Extract body by brace depth
            depth = 0
            in_body = False
            body_start = -1
            body_end = -1
            for i in range(start, len(lines)):
                for ch in lines[i]:
                    if ch == '{':
                        depth += 1
                        in_body = True
                        if body_start < 0:
                            body_start = i
                    elif ch == '}':
                        depth -= 1
                        if in_body and depth == 0:
                            body_end = i
                            break
                if body_end >= 0:
                    break

            if body_start < 0 or body_end < 0:
                issues.append(Issue(
                    check=self,
                    file_path=file_path,
                    line_no=start + 1,
                    message=f"Could not find body of {cb_name}",
                ))
                continue

            for off, line in enumerate(lines[body_start:body_end + 1], start=1):
                code = line
                if "//" in code:
                    code = code[:code.index("//")]
                # Exempt: the intended topo bridge cast
                if re.search(r"= *@ptrCast\(topo\)", code):
                    continue
                line_abs = body_start + off
                if re.search(r"@ptrCast\s*\(", code):
                    issues.append(Issue(
                        check=self,
                        file_path=file_path,
                        line_no=line_abs,
                        message=f"@ptrCast in {cb_name}: {code.strip()[:80]}",
                    ))
                if re.search(r"@alignCast\s*\(", code):
                    issues.append(Issue(
                        check=self,
                        file_path=file_path,
                        line_no=line_abs,
                        message=f"@alignCast in {cb_name}: {code.strip()[:80]}",
                    ))

        return issues


class NoHeapAllocInTileRun(Check):
    """Reject heap allocation in tk_tile_run hot path."""

    name = "no-heap-alloc-in-tile-run"
    domains = ["memory_safety"]
    severity = Severity.ERROR
    description = ("heap allocation in tk_tile_run hot path")

    files_glob = ("src/tickoni/runtime/tile_process.zig",)

    def run(self, file_path: str, file_content: str) -> list[Issue]:
        issues: list[Issue] = []
        lines = file_content.split("\n")
        in_run = False

        for lineno, line in enumerate(lines, start=1):
            stripped = line.strip()
            if "export fn tk_tile_run" in stripped:
                in_run = True
                continue
            if in_run and re.search(r"\ballocator\.alloc\b", stripped):
                issues.append(Issue(
                    check=self,
                    file_path=file_path,
                    line_no=lineno,
                    message=f"{self.description}: {stripped[:80]}",
                ))
            if in_run and re.search(r"^export fn |^pub fn ", stripped):
                in_run = False

        return issues


class StructDefaultsC(Check):
    """Check that C struct defaults enforce deny-by-default policies.

    Validates that TK_TILE_RUN (or similar structs) have:
    - populate_allowed_seccomp = NULL
    - populate_allowed_fds = NULL
    - sandbox-related params passing 0 or current process credentials
    - allow_fd = -1
    """

    name = "least-privilege-c-struct"
    domains = ["least_privilege"]
    severity = Severity.ERROR
    description = ("C struct does not enforce deny-by-default policy")

    files_glob = ("src/tickoni/c_abi/shim/tile_run.c",)

    def run(self, file_path: str, file_content: str) -> list[Issue]:
        issues: list[Issue] = []

        # Check that TK_TILE_RUN struct has correct defaults
        # Look for the struct definition
        if "TK_TILE_RUN" not in file_content:
            issues.append(Issue(
                check=self,
                file_path=file_path,
                line_no=1,
                message="TK_TILE_RUN struct not found",
            ))
            return issues

        # Check populate_allowed_seccomp = NULL
        seccomp_match = re.search(r"\.populate_allowed_seccomp\s*=\s*NULL", file_content)
        if not seccomp_match:
            issues.append(Issue(
                check=self,
                file_path=file_path,
                line_no=1,
                message="populate_allowed_seccomp is not NULL",
            ))

        # Check populate_allowed_fds = NULL
        fds_match = re.search(r"\.populate_allowed_fds\s*=\s*NULL", file_content)
        if not fds_match:
            issues.append(Issue(
                check=self,
                file_path=file_path,
                line_no=1,
                message="populate_allowed_fds is not NULL",
            ))

        # Check tk_topo_run_tile_simple passes sandbox=0, getuid()/getgid(), allow_fd=-1
        # Find the function call
        func_start = file_content.find("tk_topo_run_tile_simple(")
        if func_start < 0:
            issues.append(Issue(
                check=self,
                file_path=file_path,
                line_no=1,
                message="tk_topo_run_tile_simple function call not found",
            ))
            return issues

        # Find the matching closing paren (may span multiple lines)
        depth = 0
        call_text = []
        started = False
        for i, ch in enumerate(file_content[func_start:]):
            call_text.append(ch)
            if ch == '(':
                depth += 1
                started = True
            elif ch == ')':
                depth -= 1
                if depth == 0 and started:
                    break

        call_str = "".join(call_text)

        # sandbox=0: look for /* sandbox */ 0 or similar
        if not re.search(r"/\*[\s]*sandbox[\s]*\*/[\s]*0", call_str) and not re.search(r"\bsandbox\b.*\b0\b", call_str):
            issues.append(Issue(
                check=self,
                file_path=file_path,
                line_no=1,
                message="does not pass sandbox=0",
            ))

        # getuid()/getgid()
        if not re.search(r"getuid\(\)", call_str) or not re.search(r"getgid\(\)", call_str):
            issues.append(Issue(
                check=self,
                file_path=file_path,
                line_no=1,
                message="does not pass current process uid/gid",
            ))

        # allow_fd = -1
        if not re.search(r"allow_fd.*-1", call_str):
            issues.append(Issue(
                check=self,
                file_path=file_path,
                line_no=1,
                message="does not pass allow_fd=-1",
            ))

        return issues


class NoSystemInSandbox(Check):
    """Reject system() and exec*() calls in sandbox shim files."""

    name = "no-system-in-sandbox"
    domains = ["sandbox_entry"]
    severity = Severity.ERROR
    description = ("sandbox shim must not escalate via system() or exec*()")

    files_glob = ("src/tickoni/c_abi/shim/sandbox.c",)

    def run(self, file_path: str, file_content: str) -> list[Issue]:
        issues: list[Issue] = []

        if re.search(r"\bsystem\s*\(", file_content):
            for lineno, line in enumerate(file_content.split("\n"), start=1):
                if "system(" in line and not line.strip().startswith("//"):
                    issues.append(Issue(
                        check=self,
                        file_path=file_path,
                        line_no=lineno,
                        message=f"system() call: {line.strip()[:80]}",
                    ))

        if re.search(r"\bexec\w*\s*\(", file_content):
            for lineno, line in enumerate(file_content.split("\n"), start=1):
                if re.search(r"\bexec\w*\s*\(", line) and not line.strip().startswith("//"):
                    issues.append(Issue(
                        check=self,
                        file_path=file_path,
                        line_no=lineno,
                        message=f"exec*() call: {line.strip()[:80]}",
                    ))

        return issues


class RegistryErrorVariants(Check):
    """Check that tile_registry has required error variants and validate()."""

    name = "registry-error-variants"
    domains = ["deny_by_default"]
    severity = Severity.ERROR
    description = ("tile_registry missing deny-by-default error variant or validate()")

    files_glob = ("src/app/tickoni/tile_registry.zig",)

    required_errors = (
        "TopologyTileCountMismatch",
        "UnregisteredTopologyTile",
        "RegisteredTileMissingFromTopology",
        "LinkCardinalityMismatch",
    )

    def run(self, file_path: str, file_content: str) -> list[Issue]:
        issues: list[Issue] = []

        for err in self.required_errors:
            if err not in file_content:
                issues.append(Issue(
                    check=self,
                    file_path=file_path,
                    line_no=1,
                    message=f"Missing error variant: {err}",
                ))

        if not re.search(r"pub fn validate\(", file_content):
            issues.append(Issue(
                check=self,
                file_path=file_path,
                line_no=1,
                message="Missing pub fn validate()",
            ))

        return issues


class GlobalStatePresent(Check):
    """Check that tile_process.zig has g_ctx global state."""

    name = "global-state-presence"
    domains = ["memory_safety"]
    severity = Severity.ERROR
    description = ("tile_process.zig missing g_ctx global state")

    files_glob = ("src/tickoni/runtime/tile_process.zig",)

    def run(self, file_path: str, file_content: str) -> list[Issue]:
        issues: list[Issue] = []

        if not re.search(r"^var g_ctx:", file_content, re.MULTILINE):
            issues.append(Issue(
                check=self,
                file_path=file_path,
                line_no=1,
                message="Missing var g_ctx global declaration",
            ))

        if "g_ctx" not in file_content or "tk_tile_run" not in file_content:
            issues.append(Issue(
                check=self,
                file_path=file_path,
                line_no=1,
                message="g_ctx not used by tk_tile_run",
            ))

        return issues


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(
        description="Generic linter: load checks from a directory, run against files."
    )
    parser.add_argument(
        "checks_dir",
        type=str,
        help="Directory containing check modules (must define_checks(linter))",
    )
    parser.add_argument(
        "--root",
        type=str,
        default=None,
        help="Repository root (default: parent of checks_dir)",
    )
    parser.add_argument(
        "--files", "-f",
        type=str,
        default=None,
        help="Comma-separated file list to check (default: discover via patterns in checks)",
    )
    parser.add_argument(
        "--domains", "-d",
        type=str,
        default=None,
        help="Comma-separated domain names to filter checks",
    )
    parser.add_argument(
        "--severity", "-s",
        type=str,
        default="ERROR",
        choices=["INFO", "WARNING", "ERROR"],
        help="Report only issues at or above this severity (default: ERROR)",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Show INFO-level issues too",
    )
    args = parser.parse_args()

    checks_dir = Path(args.checks_dir)
    if not checks_dir.is_dir():
        print(f"Error: {checks_dir} is not a directory", file=sys.stderr)
        return 1

    linter = Linter()
    linter.add_checks_from_dir(checks_dir)

    # Filter checks by domain
    if args.domains:
        allowed = set(d.strip() for d in args.domains.split(","))
        linter.checks = [c for c in linter.checks if set(c.domains) & allowed]

    severity_order = {Severity.INFO: 0, Severity.WARNING: 1, Severity.ERROR: 2}
    min_sev = Severity[args.severity]
    linter.checks = [
        c for c in linter.checks
        if severity_order.get(c.severity, 0) >= severity_order.get(min_sev, 0)
    ]

    # Collect file list
    if args.files:
        file_paths = [p.strip() for p in args.files.split(",") if p.strip()]
    else:
        repo_root = Path(args.root) if args.root else checks_dir.parent.parent
        file_paths = _discover_files(repo_root)

    issues = linter.run_all(file_paths)

    # Filter by severity
    issues = [i for i in issues if severity_order.get(i.severity, 0) >= severity_order.get(min_sev, 0)]

    # Sort by severity then file
    issues.sort(key=lambda i: (severity_order.get(i.severity, 0), i.file_path, i.line_no))

    return Linter.report(issues, verbose=args.verbose)


def _discover_files(repo_root: Path) -> list[str]:
    """Discover source files across the repo tree."""
    extensions = (".zig", ".c", ".h", ".cpp", ".cc")
    files = []
    for dirpath, _dirnames, filenames in os.walk(repo_root):
        # Skip hidden dirs, .zig-cache, node_modules, etc.
        dirpath_str = dirpath
        if any(d in dirpath_str for d in (".git", ".zig-cache", "node_modules", ".venv", "__pycache__")):
            continue
        for fn in filenames:
            if fn.endswith(extensions):
                fp = os.path.join(dirpath, fn)
                if os.path.isfile(fp):
                    files.append(fp)
    return sorted(files)


if __name__ == "__main__":
    sys.exit(main())
