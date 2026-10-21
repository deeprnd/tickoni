# Plan: Rename demo tests and commands to CLI tests — Step-by-Step

Derived from: `doc/execution/plans/rename-demo-tests-to-cli-tests.md`
Created: 2026-10-21

## Step-by-Step Implementation

### Phase 1: Remove demo CLI subcommand from production dispatch

1. **Edit `src/app/tickoni/main.zig`**
   - Locate the `demo` subcommand dispatch block
   - Remove the dispatch case (and its import if no longer needed)
   - Verify: `zig build` still compiles without the demo subcommand

### Phase 2: Absorb test utility modules

2. **Move `src/tickoni/demo/substitution.zig` → `src/tickoni/test/demo/investment/substitution.zig`**
   - Update its internal import paths to match new location

3. **Move `mod.zig` `runSystemSuite()` logic → `src/tickoni/test/integration/`**
   - Merge into existing integration test file (identify which one)
   - Update import paths in the integration test module

4. **Keep `preflight.zig`, `runner.zig`, `conformance.zig`, `comparator.zig` in `src/tickoni/demo/`**
   - Preserve their in-file unit tests
   - Remove only their import from `main.zig`

5. **Verify**: `zig build test` still passes for all in-file unit tests

### Phase 3: Rename Justfile test recipes

6. **Rename `just/test/demo.just` → `just/test/cli.just`**
   - Update file-level header comment
   - Rename all recipes:
     - `test-demo-tk` → `test-cli-tk`
     - `export-demo-conformance-*` → `export-cli-conformance-*`
     - `compare-demo-conformance` → `compare-cli-conformance`

7. **Edit `justfile` (line 26)**
   - Change: `import "just/test/demo.just"` → `import "just/test/cli.just"`

8. **Verify**: `just --list` shows `test-cli-tk` (not `test-demo-tk`)

### Phase 4: Rename CI workflow

9. **Rename `.github/workflows/_ci-demo.yml` → `.github/workflows/_ci-cli.yml`**
   - Update workflow `name:` field
   - Update job `name:` fields referencing demo
   - Update step `name:` fields referencing demo
   - Update all `just test-demo-tk` references → `just test-cli-tk`

10. **Verify**: workflow YAML syntax is valid (`yq` or manual review)

### Phase 5: Update dispatch map

11. **Edit `scripts/dispatch-map.json`**
    - Change key `"test-demo-tk"` → `"test-cli-tk"`
    - Update all value entries (recipe names, command paths) to reflect new naming
    - Verify: valid JSON (`python -m json.tool scripts/dispatch-map.json`)

### Phase 6: Batch-update documentation references

12. **Update `doc/execution/testing-tickoni.md`** — `test-demo-tk` → `test-cli-tk`

13. **Update `doc/execution/plans/tests-all-template.md`** — `test-demo-tk` → `test-cli-tk`, `demo-conformance` → `cli-conformance`

14. **Update `doc/execution/plans/hygiene-migrate-demo-tests-from-bash-to-pytest.md`** — `test-demo-tk` → `test-cli-tk`, `demo.just` → `cli.just`

15. **Update `doc/execution/quality.md`** — `test-demo-tk` → `test-cli-tk`

16. **Update `doc/strategy/templates/story-template.md`** — `test-demo-tk` → `test-cli-tk`

17. **Update `doc/strategy/roadmap/epics/v1.11.md`** — `test-demo-tk` → `test-cli-tk`

18. **Update `doc/strategy/roadmap/stories/v2.10-s8.md`** — `test-demo-tk` → `test-cli-tk`, `demo-conformance` → `cli-conformance`

19. **Update `doc/strategy/roadmap/stories/v2.10-s12.md`** — `test-demo-tk` → `test-cli-tk`

20. **Update `doc/strategy/roadmap/stories/v2.10-s14.md`** — `test-demo-tk` → `test-cli-tk`

21. **Update `doc/strategy/roadmap/stories/v3.19-s*.md`** (8 files) — `test-demo-tk` → `test-cli-tk`

22. **Update `doc/strategy/roadmap/stories/v3.23-s*.md`** (4 files) — `test-demo-tk` → `test-cli-tk`

### Phase 7: Verify no stale references remain

23. **Grep for `test-demo-tk` in all non-audit files**
    - Command: `grep -r "test-demo-tk" --include="*.md" --include="*.zig" --include="*.json" --include="*.just" --include="*.yml" .`
    - Expected result: zero matches outside `doc/execution/audits/`

24. **Grep for `demo.just` references** (non-audit files)

25. **Grep for `_ci-demo.yml` references** (non-audit files)

### Phase 8: Final build/test verification

26. **Run `just build-all && just test-unit-all && just test-integration-all && just test-system-all`** — confirm all non-cli tests pass

27. **Run `just --list`** — confirm `test-cli-tk` visible

29. **Run `just test-cli-tk`** (or equivalent) — confirm it executes successfully

## Files NOT to touch

All files under `doc/execution/audits/stories/` — these are historical records:
- `V2.10.S*-quality-gate.md`
- `V2.10.S*-security-audit.md`
- `V2.10.S*-maintainability-audit.md`
- `V2.22.S*-quality-gate.md`
- `V2.22.S*-telemetry-audit.md`
- `V2.22.S*-zig-audit.md`
- `V2.21.S*-quality-gate.md`
- `V2.10.S10-maintainability-audit.md`

## Risk notes

- Phase 2 (absorbing modules) requires identifying the correct destination files in `src/tickoni/test/integration/` before moving code
- Phase 6 (batch doc updates) should use `sed` or `rg` + `patch` for efficiency — batch all 26 doc files in a single operation
- Audit exclusion must be enforced: never touch files under `doc/execution/audits/`
