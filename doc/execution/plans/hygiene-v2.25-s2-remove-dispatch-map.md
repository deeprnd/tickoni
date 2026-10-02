---
story: V2.25.S2
title: Remove scripts/dispatch + dispatch-map.json, use justfile case dispatchers
date: 2026-09-25
status: planned
---

# Plan: Remove scripts/dispatch + dispatch-map.json

> **Context:** `scripts/dispatch` and `scripts/dispatch-map.json` provide cross-platform routing for `build-tk`, `build-fd`, and `test-integration-tk`. They call a Python script that reads `contrib/platform.sh`, looks up a JSON map, then runs `just <recipe>`. This is a two-hop indirection (just → python → just).

The same pattern already exists directly in `justfile` — `test-unit-tk` and `test-unit-fd` use a bash `case` with `{{ os }}` and `{{ arch }}` from `contrib/platform.sh`, routing in one hop. `setup-quality` does the same. The Python dispatcher adds unnecessary complexity: a JSON file, a Python dependency, subprocess overhead, and a layer that can go stale independently of the actual recipes.

This plan removes the Python dispatcher and JSON map, replacing the 3 callers with inline bash case dispatchers following the established pattern in justfile.

---

## Task 0: Add bare dispatchers to justfile for build-tk, build-fd, test-integration-tk

**Steps:**

1. Replace `just/build/all.just` line 4-5 (`build-tk:` calling `scripts/dispatch build-tk`) with:
```
build-tk:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
      linux-x86) exec just build-tk-linux-x86 ;;
      linux-arm) exec just build-tk-linux-arm ;;
      macos-x86) exec just build-tk-macos-x86 ;;
      macos-arm) exec just build-tk-macos-arm ;;
      windows-x86) exec just build-tk-windows-x86 ;;
      windows-arm) exec just build-tk-windows-arm ;;
      *) echo "unsupported host platform for build-tk: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac
```

2. Replace `just/build/all.just` line 21-22 (`build-fd:` calling `scripts/dispatch build-fd`) with:
```
build-fd:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
      linux-x86) exec just build-fd-linux-x86-gcc ;;
      linux-arm) exec just build-fd-linux-arm-gcc ;;
      macos-x86) exec just build-fd-macos-x86 ;;
      macos-arm) exec just build-fd-macos-arm ;;
      windows-x86) exec just build-fd-windows-x86 ;;
      windows-arm) exec just build-fd-windows-arm ;;
      *) echo "unsupported host platform for build-fd: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac
```

3. Replace `just/test/integration.just` line 27-28 (`test-integration-tk:` calling `scripts/dispatch test-integration-tk`) with:
```
test-integration-tk:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
      linux-x86) exec just test-integration-tk-linux-x86 ;;
      linux-arm) exec just test-integration-tk-linux-arm ;;
      macos-x86) exec just test-integration-tk-macos-x86 ;;
      macos-arm) exec just test-integration-tk-macos-arm ;;
      windows-x86) exec just test-integration-tk-windows-x86 ;;
      windows-arm) exec just test-integration-tk-windows-arm ;;
      *) echo "unsupported host platform for test-integration-tk: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac
```

**Verification:** `just build-tk`, `just build-fd`, `just test-integration-tk` all work on the current platform (linux-x86) and route to the correct platform-specific recipe. `just --list` shows all dispatcher names.

**Status:**

---

## Task 1: Delete scripts/dispatch, scripts/dispatch-map.json

Remove both files. They are no longer referenced by any justfile after Task 0.

**Status:**

---

## Task 2: Delete contrib/test/test_dispatch_map.py

This test file (120 lines) validates dispatch-map.json. With the JSON gone, the tests are dead code.

**Status:**

---

## Task 3: Update doc/execution/plans/tests-all-template.md

Replace the dispatcher pattern references:
- Line 294: Remove `python3 ../../scripts/dispatch build-fd` example
- Line 974: Update the dispatcher pattern note — replace `python3 ../../scripts/dispatch` with inline bash case dispatchers in justfile (same pattern as `test-unit-tk` and `test-unit-fd`)

**Status:**

---

## Task 4: Update doc/execution/audits/stories/V2.10.S10-maintainability-audit.md

Remove Finding M-2 (the "textbook factory pattern" praise for dispatch-map). Update references to `dispatch-map.json` in sections 2.4, 3.2, and 5.4.

**Status:**

---

## Task 5: Verify nothing else references the dispatcher

**Steps:**
1. `grep -r "scripts/dispatch" --include="*.sh" --include="*.yml" --include="*.yaml" --include="*.json" --include="*.md" --include="*.py" --include="*.just" --include="Makefile" .` — verify no remaining callers
2. `grep -r "dispatch-map" --include="*.md" --include="*.py" --include="*.json" .` — verify no remaining references

**Verification:** Only the audit doc (Task 4) and plan doc (this file) reference dispatch-map.json. All runtime code paths go through justfile case dispatchers.

**Status:**

---

## Risk assessment

- **Low risk.** The bare dispatchers in justfile follow the exact same pattern as `test-unit-tk` (line 108-119 in justfile) and `test-unit-fd` (line 89-103). The platform routing logic is identical — just bash `case` vs Python+JSON.
- **test-unit-tk** and **test-unit-fd** already have this pattern. It's battle-tested.
- **No CI changes needed.** CI calls exact platform recipes (e.g. `just build-fd-linux-x86-gcc`) directly, not the bare dispatcher names.
- **The Python script adds zero value.** It does `platform.sh → JSON lookup → just <recipe>`. The `case` in justfile does `{{ os }}-{{ arch }} → just <recipe>` in one process.

**Status:**
