# Orchestrator Consolidation — Remove 4 Shell Indirection Scripts

> **For Hermes:** Implement this plan task-by-task.

**Goal:** Remove the 4-line-deep shell indirection chain (`justfile → run_live_investment_demo → run_system_model_tests → orchestrator.py`) by adding an `llm-e2e` subcommand to `orchestrator.py` and wiring justfile entries directly.

**Architecture:** One orchestrator.py subcommand (`llm-e2e`) encapsulates the 4-phase e2e flow. Justfile recipes call it directly. The 4 shell scripts are deleted.

**Tech Stack:** Python 3, bash, justfile, orchestrator.py facade

---

## Task 1: Add `llm-e2e` subcommand to orchestrator.py

**Files:**
- Modify: `contrib/test/orchestrator.py`
- Modify: `contrib/test/test/orchestrator_tests.py` (if it exists — check first)

**Step 1: Read the current orchestrator.py**

Read `contrib/test/orchestrator.py` to confirm exact structure before editing.

**Step 2: Add `llm-e2e` method to Orchestrator class**

After `dynamic_test_opts(self)` method, add:

```python
def llm_e2e(self, platform_str: str = "linux-x86"):
    """Full end-to-end: setup → start server → run system test → cleanup."""
    from infra.llama_server import start_server, pid_file_path, stop_server
    from infra.zig_build import run_zig_build

    # Phase 1: Setup — ensure llama.cpp + download model
    print("[PHASE 1] Setup: llama.cpp + model")
    # Call setup/orchestrator.py llm-server
    import subprocess, os
    setup_orch = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "setup", "orchestrator.py")
    result = subprocess.run(
        [sys.executable, setup_orch, "llm-server", "--platform", platform_str],
        capture_output=False,
    )
    if result.returncode != 0:
        print("[PHASE 1] Setup failed", file=sys.stderr)
        sys.exit(result.returncode)

    # Phase 2: Start server
    print("[PHASE 2] Starting llama.cpp server")
    start_server(
        llama_dir=self.LLAMA_DIR,
        model_dir=self.MODEL_DIR,
        model_file=self.MODEL_FILE,
        endpoint=self.ENDPOINT,
        port=self.PORT,
    )

    # Phase 3: Run system test
    print("[PHASE 3] Running system test")
    run_zig_build(target="system-test", run_tests=True)

    # Phase 4: Cleanup — stop server
    print("[PHASE 4] Stopping server")
    pid_file = pid_file_path()
    stop_server(pid_file)

    print("[E2E] Complete")
```

**Step 3: Add argparse subparser + routing**

After the `dynamic-test-opts` subparser, add:

```python
# llm-e2e
llm_e2e_p = sub.add_parser("llm-e2e", help="Full e2e: setup → start → test → cleanup")
llm_e2e_p.add_argument("--platform", default="linux-x86", help="Target platform (windows-x86, linux-x86, etc.)")
```

After the `elif args.command == "dynamic-test-opts":` block, add:

```python
elif args.command == "llm-e2e":
    sys.exit(orch.llm_e2e(args.platform))
```

**Step 4: Verify syntax**

```bash
cd contrib/test && python3 -c "import orchestrator; print('OK')"
```

Expected: no output, exit 0.

---

## Task 2: Update justfile entries

**Files:**
- Modify: `just/test/system.just`
- Modify: `just/build/windows.just`

**Step 1: Update `just/test/system.just`**

Replace line 6:

```
# Old:
bash {{ justfile_dir }}/contrib/test/run_live_investment_demo.sh

# New:
{{ python }} {{ justfile_dir }}/contrib/test/orchestrator.py llm-e2e --platform {{ os }}-{{ arch }}
```

**Step 2: Update `just/build/windows.just`**

Replace lines 34 and 37:

```
# Old:
bash {{ justfile_dir }}/contrib/test/run_live_investment_demo_win.sh windows-x86
bash {{ justfile_dir }}/contrib/test/run_live_investment_demo_win.sh windows-arm

# New:
{{ python }} {{ justfile_dir }}/contrib/test/orchestrator.py llm-e2e --platform {{ arg1 }}
```

Note: `{{ arg1 }}` passes the platform string from the recipe parameter (the existing recipes pass `windows-x86` / `windows-arm` as `$1`).

Actually, looking at the existing recipes:
```
test-system-tk-windows-x86:
    bash {{ justfile_dir }}/contrib/test/run_live_investment_demo_win.sh windows-x86
```

The `windows-x86` is a positional argument passed to the bash script, not a justfile variable. We need to change to:

```
test-system-tk-windows-x86:
    {{ python }} {{ justfile_dir }}/contrib/test/orchestrator.py llm-e2e --platform windows-x86

test-system-tk-windows-arm:
    {{ python }} {{ justfile_dir }}/contrib/test/orchestrator.py llm-e2e --platform windows-arm
```

**Step 3: Verify justfile parses**

```bash
just --list | grep llm-e2e
```

Expected: no error, recipes visible.

---

## Task 3: Delete 4 shell scripts

**Files to delete:**
- `contrib/test/run_live_investment_demo.sh`
- `contrib/test/run_live_investment_demo_win.sh`
- `contrib/test/run_system_model_tests.sh`
- `contrib/test/run_system_model_tests_win.sh`

**Step 1: Remove files**

```bash
git rm contrib/test/run_live_investment_demo.sh
git rm contrib/test/run_live_investment_demo_win.sh
git rm contrib/test/run_system_model_tests.sh
git rm contrib/test/run_system_model_tests_win.sh
```

**Step 2: Update stale docs (if needed)**

Check `doc/execution/testing-tickoni.md` for references. These are documentation references to the scripts as historical context — leave them as-is unless they describe current behavior that changed. The audit docs (V2.10) are historical, no change needed.

---

## Task 4: Verification

**Step 1: Syntax check orchestrator.py**

```bash
python3 -m py_compile contrib/test/orchestrator.py
```

**Step 2: Verify justfile parses**

```bash
just --list | head -5
```

Expected: no parse errors.

**Step 3: Dry-run the old flow**

```bash
# This should fail (no llama.cpp installed), but proves the orchestrator entry point is valid
python3 contrib/test/orchestrator.py llm-e2e --platform linux-x86
```

Expected: fails at Phase 1 (no llama.cpp installed) — that's fine, the entry point works.

**Step 4: Verify no remaining references to deleted scripts**

```bash
grep -r "run_live_investment_demo\|run_system_model_tests" --include="*.just" --include="*.py" --include="*.sh" --include="*.yaml" --include="*.yml" .
```

Expected: only doc/execution/audits/ and doc/execution/testing-tickoni.md (historical references).

---

## Verification Checklist

- [ ] orchestrator.py compiles: `python3 -m py_compile contrib/test/orchestrator.py`
- [ ] justfile parses: `just --list`
- [ ] llm-e2e subcommand registered: `just --list | grep llm-e2e` (or `orchestrator.py --help | grep llm-e2e`)
- [ ] 4 shell scripts deleted
- [ ] No remaining .just/.py/.sh/.yaml references to deleted scripts
- [ ] git status clean (only expected changes)
