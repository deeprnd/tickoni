# Plan: Delete contrib/test/infra/zig_build.py

## Problem

`contrib/test/infra/zig_build.py` is a dead-end abstraction:

- It is only imported by `contrib/test/orchestrator.py` line 51 (`from infra.zig_build import run_zig_build`).
- Nobody calls it from CI, justfile, or shell scripts — all production test paths run `zig build` directly through justfile recipes.
- Its sole caller (`orchestrator.py system-test`) uses it as a convenience to auto-build Firedancer C libs before running Zig tests. That is a boundary violation — the test orchestrator should not build infrastructure.
- The FD lib auto-build path (`subprocess.run([orchestrator.py build-fd ...])`) is redundant because `build-all` (and all CI workflows) always run `build-fd` before any test.

## Impact surface

| File | Contact | Action |
|---|---|---|
| `contrib/test/orchestrator.py:51` | `from infra.zig_build import run_zig_build` | Replace impl inline |
| `contrib/test/infra/zig_build.py` | (the file itself) | Delete |
| `contrib/test/orchestrator.py:10` | docstring lists `zig-test` CLI | Update |
| `build-lib/lib/codec.zig:20` | comment mentions zig_build.py | Drop reference |
| `doc/execution/audits/V2.10.S3-maintainability.md` | lists zig_build.py | Will be stale (audit doc) |
| `doc/execution/audits/V2.10.S8-maintainability.md` | references zig_build.py | Will be stale (audit doc) |
| `doc/execution/audits/V2.10.S11-maintainability.md` | references zig_build.py | Will be stale (audit doc) |
| `doc/execution/audits/V2.10.S11-security.md` | lists zig_build.py as "Created" | Will be stale (audit doc) |

Audit docs (`V2.10.S3`, `V2.10.S8`, `V2.10.S11`) will become stale references. They are historical audit records, not runtime code. Leave them as-is — they document what was created at the time.

## Changes

### 1. Replace `orchestrator.py.zig_test()` with inline implementation

In `contrib/test/orchestrator.py`, replace lines 49-52:

```python
def zig_test(self, target):
    """Run `zig build <target>` with tests enabled."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.normpath(os.path.join(script_dir, "..", ".."))

    fd_lib_dir_abs = os.path.join(repo_root, "build/fd-tickoni-fd/lib")
    if not os.path.isdir(fd_lib_dir_abs):
        print(f"ERROR: fd-lib-dir {fd_lib_dir_abs} not found", file=sys.stderr)
        print("Run 'just build-fd' before system tests.", file=sys.stderr)
        return 1

    import subprocess
    env = os.environ.copy()
    env.setdefault("ZIG_LOCAL_CACHE_DIR",
                   os.path.join(repo_root, "build", ".zig-cache"))
    env.setdefault("ZIG_GLOBAL_CACHE_DIR",
                   os.path.join(repo_root, "build", ".zig-global-cache"))

    cmd = ["zig", "build", "-Dtest=true",
           f"-Dfd-lib-dir={fd_lib_dir_abs}", target,
           "--summary", "all"]
    print(f"running: {' '.join(cmd)}")
    return subprocess.run(cmd, env=env).returncode
```

Add `import subprocess` to the top-level imports (line 9 area).

Move the `import subprocess` to module level (it is currently only inside the method).

### 2. Delete `contrib/test/infra/zig_build.py`

No consumers remain after step 1.

### 3. Clean up `orchestrator.py`

- Update docstring (line 10) to remove reference to `zig-test` CLI subcommand, or keep it since the CLI arg `--target` still exists and is valid.
- The CLI `zig-test --target` command (line 89-90) is still valid and useful for running arbitrary Zig test targets through the orchestrator. Keep it.

### 4. Update codec.zig comment

In `build-lib/lib/codec.zig` line 20, drop the `zig_build.py` reference if the comment still makes sense without it. Read the full context to decide.

## Verification

- `just build-all test-system-tk` — the full system test flow still works (build-fd → build-tk → system-test).
- `python3 contrib/test/orchestrator.py zig-test --target test-unit-tk` — still works.
- No references to `infra.zig_build` or `zig_build` remain in the codebase.
- `git grep -i zig_build` should return nothing (except this plan and audit docs).
