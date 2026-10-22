---
story: V2.25.S2
title: Remove scripts/dispatch + dispatch-map.json, use justfile case dispatchers
date: 2026-09-25
status: done
---

# Plan: Remove scripts/dispatch + dispatch-map.json

> **Context:** `scripts/dispatch` and `scripts/dispatch-map.json` provide cross-platform routing for `build-tk`, `build-fd`, and `test-integration-tk`. They call a Python script that reads `contrib/platform.sh`, looks up a JSON map, then runs `just <recipe>`. This is a two-hop indirection (just → python → just).

The same pattern already exists directly in `justfile` — `test-unit-tk` and `test-unit-fd` use a bash `case` with `{{ os }}` and `{{ arch }}` from `contrib/platform.sh`, routing in one hop. `setup-quality` does the same. The Python dispatcher adds unnecessary complexity: a JSON file, a Python dependency, subprocess overhead, and a layer that can go stale independently of the actual recipes.

This plan removes the Python dispatcher and JSON map, replacing the callers with inline bash case dispatchers following the established pattern in justfile.

**Note:** Task 0 was completed before this plan was written — `build-tk` (in `just/build/tk.just`), `build-fd` (in `just/build/fd.just`), and `test-integration-tk` (in `just/test/integration.just`) already have inline case dispatchers. Tasks 1–5 remain.

---

## Task 0: Add bare dispatchers to justfile for build-tk, build-fd, test-integration-tk

**Status:** ✅ **DONE** — All three dispatchers migrated to inline `case` statements in justfile before this plan was created.

- `build-tk:` in `just/build/tk.just` lines 5-16
- `build-fd:` in `just/build/fd.just` lines 5-16
- `test-integration-tk:` in `just/test/integration.just` lines 9-20

---

## Task 1: Delete scripts/dispatch, scripts/dispatch-map.json

Remove both files. They are no longer referenced by any justfile after Task 0.

**Status:** ✅ **DONE** — Deleted both files. Verified no remaining callers in code (justfiles, shell scripts, CI YAMLs).

---

## Task 2: Delete contrib/test/test_dispatch_map.py

This test file (120 lines) validates dispatch-map.json. With the JSON gone, the tests are dead code.

**Status:** ✅ **DONE** — Deleted file.

---

## Task 3: Update doc/execution/plans/tests-all-template.md

Replace the dispatcher pattern references:
- Line 294: Remove `python3 ../../scripts/dispatch build-fd` example
- Line 974: Update the dispatcher pattern note — replace `python3 ../../scripts/dispatch` with inline bash case dispatchers in justfile (same pattern as `test-unit-tk` and `test-unit-fd`)

**Status:** ✅ **DONE** — Updated line 294 (`python3 ../../scripts/dispatch build-fd` → inline `just build-fd`), updated line 974 (dispatcher pattern note now reflects inline bash case dispatchers, notes dispatch-map removal).

---

## Task 4: Update doc/execution/audits/stories/V2.10.S10-maintainability-audit.md

Remove Finding M-2 (the "textbook factory pattern" praise for dispatch-map). Update references to `dispatch-map.json` in sections 2.4, 3.2, and 5.4.

**Status:** ✅ **DONE** — Marked Finding M-2 as REMOVED by V2.25.S2 with resolution note. Updated all 12 dispatch-related references in the audit doc with (*REMOVED by V2.25.S2*) markers.

---

## Task 5: Verify nothing else references the dispatcher

**Steps:**
1. `grep -r "scripts/dispatch" --include="*.sh" --include="*.yml" --include="*.yaml" --include="*.json" --include="*.md" --include="*.py" --include="*.just" --include="Makefile" .` — verify no remaining callers
2. `grep -r "dispatch-map" --include="*.md" --include="*.py" --include="*.json" .` — verify no remaining references

**Verification:** Only the audit doc (Task 4) and plan doc (this file) reference dispatch-map.json. All runtime code paths go through justfile case dispatchers.

**Status:** ✅ **DONE** — Verified zero callers in code (justfiles, shell scripts, CI YAMLs, Python, JSON). References remain only in markdown docs (this plan and the audit doc — Task 4).

---

## Risk assessment

- **Low risk.** The bare dispatchers in justfile follow the exact same pattern as `test-unit-tk` and `test-unit-fd`. The platform routing logic is identical — just bash `case` vs Python+JSON.
- **test-unit-tk** and **test-unit-fd** already have this pattern. It's battle-tested.
- **No CI changes needed.** CI calls exact platform recipes (e.g. `just build-fd-linux-x86-gcc`) directly, not the bare dispatcher names.
- **The Python script adds zero value.** It does `platform.sh → JSON lookup → just <recipe>`. The `case` in justfile does `{{ os }}-{{ arch }} → just <recipe>` in one process.

**Status:** ✅ **DONE** — All tasks complete. Files deleted, docs updated, verification passed.
