# Plan: Migrate run_cli_demo_tests.sh → pytest

## Current state

`contrib/test/run_cli_demo_tests.sh` is a bash wrapper with embedded `python3 - <<'PY'`
heredocs. It:

1. Builds `tickoni` + `tickoni-supervisor` via `zig build`
2. Runs 6 test groups against the built binaries

The existing test pattern in the repo is: Python test files in `contrib/test/` using
`pytest`, importing Zig project modules via `sys.path`. Example: `contrib/test/test_setup_msvc.py`,
`contrib/test/test_dynamic_test_opts.py`.

## Target state

Replace the bash script with a single Python test file:

```
tests/test_demo_cli.py          (or contrib/test/test_demo_cli.py)
```

The justfile recipe `test-demo-tk` switches from calling the shell script to:
```
test-demo-tk:
    {{ python }} -m pytest tests/test_demo_cli.py -v
```

## Test groups → pytest mapping

The bash script runs 6 test groups. Each becomes a standalone `pytest` test:

| # | Bash section | pytest function | Notes |
|---|---|---|---|
| 1 | `tickoni --version` contract | `test_tickoni_version()` | Run `tickoni --version`, assert all needle strings present |
| 2 | `tickoni doctor --plain/--json` | `test_tickoni_doctor_plain()` and `test_tickoni_doctor_json()` | Two tests for the two output formats |
| 3 | bare `demo` invocation fails closed | `test_demo_bare_usage_fails()` | Assert non-zero exit code, check stderr |
| 4 | JSON conformance suite | `test_demo_conformance_json()` | Parse JSON output, assert suite structure, scenarios, comparison |
| 5 | plain-text conformance suite | `test_demo_conformance_plain()` | Assert key strings in plain output |
| 6 | fail-closed preflight | `test_preflight_fail_closed()` | 5 sub-cases: unsupported_runtime_tier, missing_fixture, stale_manifest, missing_isolation_prerequisite, attempted_live_execution |

## Implementation approach

### Step 1: Create `tests/test_demo_cli.py` (or `contrib/test/test_demo_cli.py`)

Structure:

```python
"""Tests for tickoni CLI and tickoni-supervisor demo conformance."""

import json
import pathlib
import subprocess
import sys

import pytest

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent  # adjusts if in contrib/test/
ZIG_PREFIX = REPO_ROOT / "build" / "zig-out"
TICKONI_BIN = ZIG_PREFIX / "bin" / "tickoni"
SUPERVISOR_BIN = ZIG_PREFIX / "bin" / "tickoni-supervisor"
MANIFEST = REPO_ROOT / "src" / "tickoni" / "demo" / "fixtures" / "demo.manifest.json"


def _run(cmd, **kwargs):
    """Run a subprocess, return CompletedProcess."""
    return subprocess.run(cmd, cwd=REPO_ROOT, text=True, capture_output=True, **kwargs)


class TestTickoniVersion:
    @pytest.fixture(autouse=True, scope="class")
    def build_binaries(self):
        result = subprocess.run(
            ["zig", "build", "-p", str(ZIG_PREFIX),
             "-Dfd-lib-dir=" + str(REPO_ROOT / "build" / "fd-tickoni-fd" / "lib"),
             "-Dtest=true", "--summary", "all"],
            cwd=REPO_ROOT,
            capture_output=True, text=True,
        )
        assert result.returncode == 0, f"zig build failed: {result.stderr}"

    def test_version_has_all_fields(self):
        proc = _run([str(TICKONI_BIN), "--version"])
        assert proc.returncode == 0
        for needle in [
            "Tickoni ", "Build ID:", "Git:", "OS:", "Runtime Tier:",
            "Isolation Tier:", "Policy Schema:", "Replay Schema:",
            "Demo Manifest:", "Compiler:",
        ]:
            assert needle in proc.stdout, f"missing {needle!r} in version output"
```

Key design decisions:

- **Single class fixture** (`scope="class"`) does one `zig build` for all tests. No
  per-test rebuild. The build is the expensive step; test assertions are fast.
- **`REPO_ROOT`** resolves from the test file's location, not from `__file__` of
  the script. Works regardless of whether pytest is invoked from repo root or
  elsewhere.
- **`ZIG_PREFIX`** uses the default `build/zig-out` (same as the bash script
  fallback). The justfile recipe already passes `ZIG_PREFIX` if set.
- **No inline Python** — pure pytest + subprocess + json module.

### Step 2: Wire into justfile

Change `just/test/demo.just`:

```diff
 test-demo-tk:
-	ZIG_PREFIX={{ ZIG_PREFIX }} ZIG_PREFIX_REL={{ ZIG_PREFIX_REL }} bash {{ justfile_dir }}/contrib/test/run_cli_demo_tests.sh
+	ZIG_PREFIX={{ ZIG_PREFIX }} {{ python }} -m pytest tests/test_demo_cli.py -v
```

Remove the per-platform aliases (they were all aliases to `test-demo-tk` anyway).

### Step 3: Delete the bash script

Remove `contrib/test/run_cli_demo_tests.sh`.

### Step 4: Update references in docs

Files that mention `run_cli_demo_tests.sh`:
- `just/test/demo.just` (covered by Step 2)
- `doc/strategy/roadmap/backlog/proposals/build-tooling-consolidation.md` — mention in table
- `doc/execution/audits/stories/V2.10.S11-security-audit.md` — audit finding references
- `doc/execution/audits/stories/V2.10.S6-security-audit.md` — SEC-05 finding
- `doc/execution/audits/stories/V2.10.S8-security-audit.md` — SEC-05 resolution
- `doc/execution/testing-tickoni.md` — may reference the script name

Update: audit docs get a note that the file was migrated to pytest (no need to
rewrite audit history, just flag the change). The backlog proposal table gets
"migrated to pytest" status. The testing doc gets the new test name.

### Step 5: Verify

Run:
```bash
zig build -p build/zig-out -Dfd-lib-dir=build/fd-tickoni-fd/lib -Dtest=true
pytest tests/test_demo_cli.py -v
```

All tests should pass on the platform where this runs.

## Files touched

| File | Action |
|---|---|
| `tests/test_demo_cli.py` (or `contrib/test/test_demo_cli.py`) | **create** |
| `just/test/demo.just` | edit: update `test-demo-tk` recipe |
| `contrib/test/run_cli_demo_tests.sh` | **delete** |
| `doc/strategy/roadmap/backlog/proposals/build-tooling-consolidation.md` | edit: note migration |
| `doc/execution/audits/stories/V2.10.S11-security-audit.md` | edit: note migration |
| `doc/execution/audits/stories/V2.10.S6-security-audit.md` | edit: note resolution |
| `doc/execution/audits/stories/V2.10.S8-security-audit.md` | edit: note resolution |
| `doc/execution/testing-tickoni.md` | edit: update test reference |

## Open questions

1. **Test file location** — `contrib/test/` (with existing pytest tests) or
   `tests/` at repo root? `contrib/test/` keeps infra tests together.
2. **Should `export_demo_conformance_bundle.py` and `compare_demo_conformance.py`
   also get pytest wrappers?** They serve CI compare jobs, which is a different
   use case. Leave them as-is for now.
