# Doc Alignment Plan — Execution Docs vs Current Codebase

**Branch:** `story/tile-consolidation` (ahead 12, behind 0)
**Scope:** 6 execution docs vs current `justfile`, CI workflows, and `contrib/` directory structure
**Status:** Assessment complete, pending approval to execute

---

## Critical Mismatches (docs describe things that no longer exist)

| Doc | Claim | Reality |
|-----|-------|---------|
| **ci.md** | "Each workflow begins with a `detect-changes` job" | Zero occurrences of `detect-changes` in any YAML. `ci.yml` uses direct `needs:` DAG — no path detection. |
| **ci.md** | Dispatch tree includes `build-artifacts-compare` as intermediate aggregation | `ci.yml` has `build-artifacts-compare` as a job but the tree description is misleading about its role |
| **testing-tickoni.md** | `just test-cli-tk` — "Deterministic demo conformance suite" | `just/test/demo.just` was deleted; no `test-cli-tk` recipe exists anywhere |
| **testing-tickoni.md** | `just test-system-tk` runs `python contrib/test/orchestrator.py system-test` | `contrib/test/` still has `orchestrator.py` but the old demo scripts (`run_live_investment_demo.sh`, etc.) were deleted — the orchestrator's system-test functionality may be broken |
| **testing-tickoni.md** | `just test-e2e-fd` runs `make integration-test && make run-integration-test` | `just/test/e2e.just`: `test-e2e-fd: @true` — it's a no-op placeholder, not the firedancer integration-test |
| **quality.md** | `just test-cli-tk` for demo commands | Recipe doesn't exist |
| **build.md** | Demo conformance badge refresh via `contrib/tool/readme/refresh-badges.py` with examples | Still exists but the demo context it references (`test-cli-tk`) is gone |
| **build.md** | Build graph references `src/tickoni/runtime/` | `src/tickoni/demo/` was deleted; `src/app/tickoni_cli/` now exists as separate CLI |

---

## Structural Mismatches (paths and organization changed)

| Doc | Old path | New path |
|-----|----------|----------|
| **ci.md, testing-tickoni.md** | `contrib/test/orchestrator.py` (system test orchestration) | `contrib/test/orchestrator.py` (still exists but only has `system-test`; old demo scripts deleted) |
| **ci.md** | `contrib/test/run_live_investment_demo.sh` | Deleted |
| **ci.md** | `contrib/test/run_system_test.sh` | Deleted |
| **ci.md** | `contrib/test/infra/` | Deleted |
| **ci.md** | `contrib/test/dispatch` / `dispatch-map.json` | Deleted |
| **testing-tickoni.md** | `src/tickoni/test/demo/` | Deleted; moved to `src/tickoni/test/fixtures/` and `src/app/tickoni_cli/` |
| **ci.md** | `contrib/test/test_*.py` files | Moved to `contrib/build/tests/`, `contrib/setup/tests/`, `contrib/tool/tests/` |
| **ci.md** | `contrib/infra/` | Deleted |

---

## Minor/Accuracy Issues

### ci.md
- "All fourteen Tickoni CI workflows" — actual count: `ci.yml` + 12 `_ci-*.yml` + `tests-coverage.yml` + `tests-dev-setup.yml` + `badge-update.yml` = 15 files, but `badge-update.yml` is not a Tickoni CI workflow per se
- Table says `_ci-cli.yml` covers "Deterministic CLI Conformance" — this is now `fixture-cli` in the DAG, but the doc doesn't reflect the new naming or the fact that `test-cli-tk` recipe is gone
- Qt security references `qtbase5-dev` packages but Qt Quality section says Qt6
- `FD_TK_LIB_SRCS` lists `src/third_party/cjson src/third_party/s2n-bignum` inline rather than as separate array entries

### testing-tickoni.md
- Qt test section describes `cmake -S src/tickoni/terminal -B build/qt --fresh` but Qt6 vs Qt5 version is unclear
- Duplicate `<!-- badge:cov-tk:end -->` on line 46
- `test-unit-all` does NOT use `run-badged-command.py` (unlike integration and system)

### build.md
- Build graph ASCII art references `src/tickoni/runtime/runtime.zig`, `src/tickoni/tiles/payment_pipeline.zig`, and `src/app/tickoni/supervisor.zig` — paths need verification
- Demo conformance badge section examples reference `test-cli-tk` which doesn't exist

### quality.md
- References `just test-cli-tk` in the Demoable section — recipe doesn't exist

### development.md
- References `zig build run -- start/status` as active — need to verify `src/app/tickoni/main.zig` still has these commands
- CLI tooling section doesn't reflect `src/app/tickoni_cli/` as a separate CLI module
- `test-unit-tk` description says `run-badged-command.py` badge-wrapping — actually that's `test-unit-all`

### security.md
- Sanitizer commands reference `security-sanitize-check-fd` and `security-sanitize-check-tk` — need to verify these still exist in `just/security/*.just`

---

## Plan

### Phase 1: Fix ci.md (highest impact — CI architecture changed fundamentally)

1. Remove the `detect-changes` section — it doesn't exist. Replace with accurate description of the `plan` job and the `needs:` DAG.
2. Rewrite the dispatch tree to match actual `ci.yml` jobs: `plan` → `quality`, `security-secrets`, `build` → `build-artifacts-compare`, `project-build` → `unit` → `integration`, `system`, `fixture-cli`, `coverage` (parallel) → `project-tests` → `security-deep-*` → `project-security`, `ci-required`.
3. Fix workflow summary table — recount workflows, verify runner names and job names match reality.
4. Fix `_ci-cli.yml` description — it runs `fixture-cli` which exercises CLI tests, but `test-cli-tk` recipe doesn't exist. Clarify what it actually does.
5. Update system test section — remove references to deleted `run_live_investment_demo.sh`; document that it now uses `contrib/test/orchestrator.py system-test` via `infra-ensure-llamacpp`.
6. Fix Qt security section — align Qt5 vs Qt6 package references.
7. Update deleted upstream workflows table — verify accuracy of removal reasons.
8. Fix `FD_TK_LIB_SRCS` table formatting in Centralized Firedancer Lib Machinery.

### Phase 2: Fix testing-tickoni.md

1. Remove all references to `just test-cli-tk` — replace with accurate description of the current demo/fixture test situation. Either document the `fixture-cli` CI job or note that demo tests were reorganized into CLI build/tests.
2. Fix `test-e2e-fd` description — it's `@true` (no-op), not the firedancer integration-test command. Document the current state.
3. Update system test section — document that `contrib/test/orchestrator.py` now handles the full system test lifecycle (llama.cpp start → zig test → stop), and the old bash scripts are gone.
4. Fix path references — update test directory boundaries to reflect that `src/tickoni/demo/` is deleted and `src/app/tickoni_cli/` is the new CLI location.
5. Fix badge reference — remove duplicate `<!-- badge:cov-tk:end -->` on line 46.
6. Update test-unit-all — note that it does NOT use `run-badged-command.py` (unlike integration and system).
7. Update pytest test paths — tests moved from `contrib/test/` to `contrib/build/tests/`, `contrib/setup/tests/`, `contrib/tool/tests/`.

### Phase 3: Fix build.md

1. Verify build graph ASCII art — check if `src/tickoni/runtime/runtime.zig`, `src/tickoni/tiles/payment_pipeline.zig`, and `src/app/tickoni/supervisor.zig` still exist at those paths. Update if paths shifted.
2. Remove or update demo conformance badge section — `refresh-badges.py` examples reference `test-cli-tk` which doesn't exist. Either remove the demo conformance references or update them to the new CLI test structure.
3. Add `build-cli` recipe — new recipe exists in `just/build/cli.just` for building the CLI tool separately.

### Phase 4: Fix quality.md

1. Replace `just test-cli-tk` references in the Demoable section with the current demo test mechanism (or mark as needing reorganization).
2. Verify all `just` command references match what's actually in `just/quality/*.just` and `just/security/*.just`.

### Phase 5: Fix security.md

1. Verify all `just security-*` command references still exist in `just/security/*.just` — especially `security-seccomp-check-fd`, `security-proof-check-fd`, `security-sanitize-check-fd`.
2. Check if `security-sanitize-check-fd` still runs Clang ASan+UBSan as described.

### Phase 6: Fix development.md

1. Verify `zig build run -- start/status` still works (check `src/app/tickoni/main.zig`).
2. Update CLI tooling section — `src/app/tickoni_cli/` now exists as a separate CLI module; this should be reflected.
3. Verify `test-unit-tk` description — the `run-badged-command.py` badge-wrapping is in `test-unit-all`, not `test-unit-tk`.

### Phase 7: Cross-cutting consistency

1. Update all inter-doc references — ensure cross-links between the 6 docs point to correct sections.
2. Remove stale badge references — any badge that references a dead recipe needs updating or removal.
3. Add "Current Test Command Matrix" section to testing-tickoni.md that reflects the actual justfile dispatch structure.

---

## Priority Order

1. **ci.md** first — it has the most severe inaccuracies (describing non-existent mechanisms like `detect-changes`)
2. **testing-tickoni.md** second — most references to deleted recipes (`test-cli-tk`, incorrect `test-e2e-fd` behavior)
3. **build.md** third — needs path verification and demo section cleanup
4. **quality.md, security.md, development.md** fourth — mostly recipe reference corrections

## Files Affected

- `doc/execution/ci.md`
- `doc/execution/testing-tickoni.md`
- `doc/execution/build.md`
- `doc/execution/quality.md`
- `doc/execution/security.md`
- `doc/execution/development.md`

## Verification Strategy

After each doc is updated, verify against the source of truth:
1. `just --list` for recipe existence
2. `cat .github/workflows/*.yml` for CI workflow structure
3. `ls contrib/*/` for directory structure
4. `ls src/tickoni/` and `ls src/app/tickoni/` for path accuracy
5. Cross-reference all `just` command mentions across all 6 docs
