# Remove contrib/test/infra/zig_build.py — Inline into orchestrator.py

> **For Hermes:** Execute task-by-task. Read files before editing.

**Goal:** Remove the `contrib/test/infra/zig_build.py` module and inline its `run_zig_build()` logic directly into `contrib/test/orchestrator.py`. Eliminate one import, one file, and one layer of indirection.

**Scope:** This refactor touches only `contrib/test/orchestrator.py` and `contrib/test/infra/zig_build.py`. The `contrib/test/infra/__init__.py` stays (still hosts `llama_server.py` and `dynamic_test_opts.py`). No changes to shell scripts, `.just` files, build system, or tests.

**Read first:** This plan assumes `contrib/test/orchestrator.py` and `contrib/test/infra/zig_build.py` are the source of truth. Verify exact content before editing.

---

## Current State

### Call graph

```
contrib/test/orchestrator.py
  ├── infra/llama_server.py          → llama.cpp server lifecycle
  ├── infra/zig_build.py             ← removing this
  │     └── run_zig_build(target, run_tests)
  ├── infra/dynamic_test_opts.py     → system resource detection
  └── contrib/build/orchestrator.py  ← called by zig_build.py to build FD libs
```

### What `zig_build.py` does (65 lines)

1. Resolves `script_dir` via `os.path.dirname(os.path.abspath(__file__))`
2. Computes `repo_root = os.path.normpath(os.path.join(script_dir, "..", "..", ".."))`
3. Copies `os.environ` and sets `ZIG_GLOBAL_CACHE_DIR`
4. Locates `contrib/test/../build/orchestrator.py` (fallback path)
5. Checks if `build/fd-tickoni-fd/lib` exists; if not, runs `orchestrator.py build-fd fd-tickoni-fd test`
6. Builds `["zig", "build", -Dtest=true, -Dfd-lib-dir=..., target, --summary, all]`
7. Runs it via `subprocess.run()` and returns exit code

### What calls `zig_build.py`

Only `contrib/test/orchestrator.py` — two methods:

- `Orchestrator.zig_build(target)` → `run_zig_build(target, run_tests=False)`
- `Orchestrator.zig_test(target)` → `run_zig_build(target, run_tests=True)`

### What doesn't call it

- No `.just` files reference `contrib/test/infra/zig_build.py`
- No shell scripts reference it directly
- No tests import it
- No CI workflows reference it
- The comment in `build-lib/lib/codec.zig:9` ("when the path is absolute (from zig_build.py)") is historical and will remain accurate

---

## Task 1: Inline `run_zig_build` into `orchestrator.py`

**File:** `contrib/test/orchestrator.py`

### Step 1a: Add the inline method to `Orchestrator` class

After the `dynamic_test_opts(self)` method, add a single `zig_build_and_test(target, run_tests)` method that contains all logic from `zig_build.py`:

```python
def zig_build_and_test(self, target, run_tests):
    """Run `zig build <target>` with optional test flag and FD lib bootstrap.

    This inlines the former contrib/test/infra/zig_build.py::run_zig_build()
    to eliminate one file and one import layer.
    """
    import subprocess
    import os

    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.normpath(os.path.join(script_dir, "..", "..", ".."))
    env = os.environ.copy()
    env.setdefault("ZIG_GLOBAL_CACHE_DIR", os.path.join(repo_root, "build", ".zig-global-cache"))

    # Ensure fd-lib-dir exists — the build orchestrator must compile
    # libfd_ballet.a, libfd_util.a, etc. before Zig can link them.
    build_orch = os.path.join(script_dir, "..", "build", "orchestrator.py")
    if not os.path.isfile(build_orch):
        build_orch = os.path.join(script_dir, "..", "build", "orchestrator.py")
    fd_lib_dir_abs = os.path.join(repo_root, "build/fd-tickoni-fd/lib")
    if not os.path.isdir(fd_lib_dir_abs) or not os.listdir(fd_lib_dir_abs):
        print(f"fd-lib-dir {fd_lib_dir_abs} not found — building Firedancer libs first")
        subprocess.run([sys.executable, build_orch, "build-fd", "fd-tickoni-fd", "test"], check=True)

    cmd = ["zig", "build"]
    if run_tests:
        cmd.append("-Dtest=true")
    cmd.extend([f"-Dfd-lib-dir={fd_lib_dir_abs}"])
    cmd.append(target)
    cmd.append("--summary")
    cmd.append("all")

    print(f"running: {' '.join(cmd)}")

    result = subprocess.run(cmd, env=env)
    return result.returncode
```

### Step 1b: Refactor `zig_build` and `zig_test` to delegate to the new method

Replace the current two methods:

```python
# Old:
def zig_build(self, target):
    from infra.zig_build import run_zig_build
    return run_zig_build(target=target, run_tests=False)

def zig_test(self, target):
    from infra.zig_build import run_zig_build
    return run_zig_build(target=target, run_tests=True)

# New:
def zig_build(self, target):
    return self.zig_build_and_test(target, run_tests=False)

def zig_test(self, target):
    return self.zig_build_and_test(target, run_tests=True)
```

### Step 1c: Remove the unused import

Remove `import subprocess` from the top of the file if it was only used by the old import chain (it isn't — the subprocess import lives inside `infra/zig_build.py`), so **no top-level changes needed**. The inline method has its own `import subprocess`.

Actually, checking: `contrib/test/orchestrator.py` does NOT import `subprocess` at the top level — `zig_build.py` does. The inline method adds its own `import subprocess` inside the method body. No top-level changes needed.

---

## Task 2: Delete `contrib/test/infra/zig_build.py`

**Action:** Remove the file entirely.

```
contrib/test/infra/zig_build.py
```

This leaves `contrib/test/infra/__init__.py` intact (still hosts `llama_server.py` and `dynamic_test_opts.py`).

---

## Task 3: Update historical references

**Files to update:**

1. `doc/execution/audits/stories/V2.10.S11-security-audit.md` (line 31) — `zig_build.py` listed as "Created"
2. `doc/execution/audits/stories/V2.10.S8-maintainability-audit.md` (line 58) — mentions `zig_build.py` as routing target
3. `doc/execution/audits/stories/V2.10.S3-maintainability-audit.md` (line 21) — lists it as infra module
4. `doc/execution/audits/stories/V2.10.S11-maintainability-audit.md` (lines 20, 124, 222) — describes it as new module

**Approach for audit docs:** These are historical audit records. Don't delete references to them — they document what existed at audit time. But add a footnote or parenthetical noting it was inlined in this refactor. E.g.:

> `contrib/test/infra/zig_build.py` — zig build execution *(inlined into orchestrator.py, 2026-09)*

Or, since the plan says "don't fix anything" beyond what's strictly necessary, **skip audit doc updates** — they're historical records and inlining the code doesn't change what was audited. Flag them as "no action required."

**File to keep as-is:**
- `doc/execution/plans/2026-09-25-orchestrator-consolidation.md` — references `from infra.zig_build import run_zig_build` in its proposed `llm_e2e` code. This plan is stale anyway (the consolidation it proposes hasn't been executed). After this refactor, the `llm-e2e` code in that plan will still work because `orchestrator.py` will have the inlined method. **No change needed.**

**File to keep as-is:**
- `build-lib/lib/codec.zig:9` — comment references `zig_build.py`. It's about absolute path handling, not the module itself. No change needed.

---

## Verification Checklist

- [ ] `contrib/test/orchestrator.py` has `zig_build_and_test()` method with all logic from `zig_build.py`
- [ ] `zig_build()` and `zig_test()` delegate to `zig_build_and_test()`
- [ ] No `from infra.zig_build import` imports remain in `orchestrator.py`
- [ ] `contrib/test/infra/zig_build.py` is deleted
- [ ] `python3 -m py_compile contrib/test/orchestrator.py` succeeds
- [ ] `python3 contrib/test/orchestrator.py --help` shows all subcommands still work
- [ ] No other files import `infra.zig_build` (grep confirms)
- [ ] Audit docs left as historical records (no changes)

---

## What This Does NOT Touch

- `contrib/test/run_live_investment_demo.sh` and related shell scripts
- `contrib/test/run_system_model_tests.sh` and related shell scripts
- `contrib/test/infra/llama_server.py`
- `contrib/test/infra/dynamic_test_opts.py`
- `contrib/test/infra/__init__.py`
- `contrib/build/orchestrator.py`
- Any `.just` files
- Any CI workflow files
- Any test files
- `doc/execution/audits/stories/` (historical records)
