# Justfile Architecture Reorganization

**Date:** 2026-10-17
**Status:** planned
**Scope:** justfile, just/ directory, CI workflows

## Current State

| Location | Recipes | Notes |
|----------|---------|-------|
| justfile | 215 | Variables + setup + build + test + quality + security + mem + dispatchers |
| just/ (all files) | 358 unique names | 194 overlap with justfile (dead), 164 only in just/ (dead) |
| **Total dead duplicates** | **358** | All just/ recipes are unreachable — just/ is never included |

### Key Problems

1. Root justfile bloat — 215 recipes mixing variables, setup, build, test, quality, security, memory management, and dispatchers
2. Dead `just/` directory — 358 recipe names across 14 files, never included by justfile
3. 194 duplicate recipes between justfile and just/ — same names, sometimes different bodies
4. `--platform` inconsistency — some orchestrator.py calls pass `--platform`, others rely on auto-detection
5. Tool-specific setup in CI — workflows call `setup-zig`, `setup-gitleaks-linux-x86` instead of usage-based names
6. Alias proliferation — quality and security have ~180 platform forwarding aliases
7. Cross-category call violations — test recipes call `just build-fd-*`, build recipes reference `just setup-qt-*`

### Cross-Category Violations

| Violating Recipe | Category | Calls | Target |
|---|---|---|---|
| `test-integration-tk-windows-x86/arm` | test | `just build-fd-*` | build |
| `test-system-tk-windows-x86/arm` | test | `just build-fd-*` | build |
| `build-qt-linux-*` (x6) | build | `just setup-qt-*` | setup |

### Target Structure

```
justfile                          # variables + includes + aggregate-all + dispatchers
├── just/vars.just                # All variable definitions
├── just/setup/install.just       # setup-build-*, setup-fd-*, setup-fd-deps-*, setup-coverage-*, setup-zig
├── just/setup/quality.just       # setup-quality-*
├── just/setup/secrets.just       # setup-gitleaks-*
├── just/setup/security.just      # setup-security-*
├── just/setup/qt.just            # setup-qt-*
├── just/setup/developer.just     # setup-env, setup-git, setup-linux-*, setup-macos-*, setup-windows-*, test-prep-linux-x86
├── just/build/dispatch.just      # build-tk, build-fd (bare dispatchers)
├── just/build/linux.just         # build-tk-linux-x86, build-tk-linux-arm, build-fd-linux-x86-gcc/clang, build-fd-linux-arm-gcc
├── just/build/macos.just         # build-tk-macos-x86/arm, build-fd-macos-x86/arm
├── just/build/windows.just       # build-tk-windows-x86/arm, build-fd-windows-x86/arm
├── just/build/compat.just        # build-fd-gcc, build-fd-clang, build-fd-arm, build-fd-macos-x86_64, build-fd-tk-libs, build-fd-dev
├── just/build/qt.just            # build-qt-linux-x86/arm, build-qt-macos-x86/arm, build-qt-windows-x86/arm
├── just/test/dispatch.just       # test-all, test-unit-tk, test-unit-fd, test-integration-tk (bare dispatchers)
├── just/test/unit.just           # test-unit-tk-linux-x86, test-unit-fd-linux-x86-gcc, gen-audit-fixtures, test-unit-all, platform variants
├── just/test/integration.just    # test-integration-tk-linux-x86, test-integration-tk-windows-x86, platform variants
├── just/test/demo.just           # test-demo-tk, export-demo-conformance-*, compare-demo-conformance
├── just/test/system.just         # test-system-tk, infra-ensure-*, test-system-all
├── just/test/coverage.just       # test-cov-*
├── just/test/e2e.just            # test-e2e-*
├── just/quality.just             # quality-format-check-*, quality-lint-check-*, quality-proto-check-*, quality-yaml-check-linux, quality-spell-check-linux, quality-check-all
├── just/security.just            # security-*, security-check-all
├── just/system.mem.just          # mem-*, kill-test
```

### Platform Alias Convention

When a test/quality/security recipe is identical across platforms, bundle all non-canonical platforms as zero-body aliases to the canonical implementation:

```
test-integration-tk-linux-x86:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test

test-integration-tk-linux-arm: test-integration-tk-linux-x86
test-integration-tk-macos-x86: test-integration-tk-linux-x86
test-integration-tk-macos-arm: test-integration-tk-linux-x86
test-integration-tk-windows-x86: test-integration-tk-linux-x86
test-integration-tk-windows-arm: test-integration-tk-linux-x86
```

### Rules After Reorganization

- No recipe in `just/test/` may call `just build-*` or `just setup-*`
- No recipe in `just/build/` may call `just setup-*`
- No recipe in `just/quality/` or `just/security/` may call `just build-*`, `just setup-*`, or `just test-*`
- No recipe in `just/setup/` may call `just build-*`, `just test-*`, `just quality-*`, or `just security-*`
- Only allowed cross-category call: `tests-all` → `build-all` (root-level aggregator)
- Build recipe error messages must not reference `just setup-*`; use inline checks instead

## Execution Steps

### Step 1: Audit and classify every recipe

Before moving anything, catalog every recipe from both sources.

1. Run `just --list` to list all current recipes
2. Scan all 14 files under `just/` for recipe names
3. Build a classification table:
   - **Canonical (keep):** actual implementation bodies used by CI or local dev — variables (`make`, `python`, `justfile_dir`, `ZIG_*`, `tk_platform`, `fd_*`), build (`build-tk-*`, `build-fd-*`, `build-qt-*`), test (`test-unit-*`, `test-integration-*`, `test-demo-*`, `test-system-*`, `test-cov-*`, `test-e2e-*`), quality (`quality-format-check-*`, `quality-lint-check-*`), security (`security-codeql-*`, `security-gitleaks-*`, `security-seccomp-*`, etc.), setup (`setup-build-*`, `setup-fd-*`, `setup-quality-*`, `setup-gitleaks-*`, `setup-linux-*`, `setup-macos-*`, `setup-windows-*`, `setup-coverage-*`, `setup-security-*`, `setup-qt-*`, `setup-env`, `setup-git`), mem (`mem-init`, `mem-query`, `mem-reset`, `mem-fini`, `mem-alloc`, `mem-free`, `mem-drop-caches`, `kill-test`)
   - **Dead (remove):** only in `just/`, no callers — `setup-quality` (bare), `setup-zig`, `setup-sanitizer-linux-x86-clang`, `test-demo-fd`, `test-demo-all`, `test-integration-tk-domain-*`, `test-integration-tk-infra-*`, `test-perf-*`, `test-setup-install`, `test-setup-run`, `test-unit-tk-linux-*`, `test-unit-tk-macos-*`, `test-unit-tk-windows-*`, `build-qt` (bare), `quality-format-check-qt`, `quality-lint-check-qt`, `quality-lint-check-actions`, `security-*-qt` (20+)
   - **New/missing:** recipes only in `just/` that should exist — `build-tk-linux-arm`, `build-tk-macos-*`, `build-tk-windows-*`, `test-integration-tk-linux-arm`, `test-integration-tk-macos-*`, `test-integration-tk-windows-*`, `test-unit-tk-linux-arm`, `test-unit-tk-macos-*`, `test-unit-tk-windows-*`
4. Write the catalog to `doc/execution/plans/hygiene-2026-10-01-justfile-reorganization.md` as an appendix

### Step 2: Fix cross-category violations

Before reorganizing, remove the violations so the new structure stays clean.

1. Remove `just build-fd-windows-x86` and `just build-fd-windows-arm` from:
   - `test-integration-tk-windows-x86` (line ~615)
   - `test-integration-tk-windows-arm` (line ~621)
   - `test-system-tk-windows-x86` (line ~687)
   - `test-system-tk-windows-arm` (line ~694)
2. Replace with the same `zig build` invocation used by non-Windows variants (FD libraries are already present via CI artifact reuse)
3. Replace `'just setup-qt-*' first` error messages in `build-qt-linux-*` (6 recipes, lines 340-390) with an inline CMake check or remove the reference entirely
4. Verify: no recipe in `just/` files calls `just build-*` or `just setup-*`

### Step 3: Create `just/` directory structure

Create the target file layout from the structure above.

1. Create each `.just` file under `just/` with a category comment header
2. Move **variable definitions** from `just/common.just` → `just/vars.just`
3. Move **setup recipes** from `just/common.just` into their respective `just/setup/*.just` files:
   - `setup-build-*`, `setup-fd-*`, `setup-fd-deps-*`, `setup-coverage-*`, `setup-zig` → `just/setup/install.just`
   - `setup-quality-*` → `just/setup/quality.just`
   - `setup-gitleaks-*` → `just/setup/secrets.just`
   - `setup-security-*` → `just/setup/security.just`
   - `setup-qt-*` → `just/setup/qt.just`
   - `setup-env`, `setup-git`, `setup-linux-*`, `setup-macos-*`, `setup-windows-*`, `test-prep-linux-x86` → `just/setup/developer.just`
4. Move **build recipes** into `just/build/*.just` files (linux, macos, windows, compat, qt)
5. Move **test recipes** into `just/test/*.just` files (dispatch, unit, integration, demo, system, coverage, e2e)
6. Move **quality and security recipes** into `just/quality.just` and `just/security.just`
7. Move **memory recipes** into `just/system.mem.just`
8. Use the platform alias convention (zero-body aliases) for identical cross-platform recipes

### Step 4: Rewrite `justfile` with includes

Replace the current monolithic justfile (~161 recipes) with a thin file (~40 lines):

1. Add `include just/vars.just` at the top
2. Add `include` directives for each category file in logical order (setup → build → test → quality → security → mem)
3. Move aggregate dispatchers (`tests-all`, `test-all`, `build-all`, `quality-check-all`, `security-check-all`) to root
4. Move bare dispatchers (`build-tk`, `build-fd`, `test-unit-tk`, `test-unit-fd`, `test-integration-tk`, `test-all`) to root as case-routing scripts
5. Keep `default` and `help` in root
6. Verify: `just --list` shows all recipes organized by category
7. Verify: `just build-tk`, `just build-fd`, `just test-all`, `just tests-all` all work end-to-end

### Step 5: Delete `just/common.just` and dead `just/` files

1. Confirm all canonical recipes have been moved to the new structure
2. Delete `just/common.just` (its contents are now in `just/vars.just` and `just/setup/*.just`)
3. Delete dead recipe files in `just/` that are not referenced by anything:
   - `just/setup/zig.just` (setup-zig is replaced by setup-fd-*)
   - `just/test/demo-fd.just` (test-demo-fd not referenced)
   - `just/test/demo-all.just` (test-demo-all not referenced)
   - `just/test/integration-domain.just` (test-integration-tk-domain-* not referenced)
   - `just/test/integration-infra.just` (test-integration-tk-infra-* not referenced)
   - `just/test/perf.just` (test-perf-* not referenced)
   - `just/test/setup.just` (test-setup-install, test-setup-run not referenced)
   - `just/test/unit-tk.just` (test-unit-tk-linux-* etc. not referenced)
   - `just/build/qt.just` (build-qt bare dispatcher, replaced by build-qt-* variants)
   - `just/quality/qt.just` (quality-format-check-qt, quality-lint-check-qt not referenced)
   - `just/quality/actions.just` (quality-lint-check-actions not referenced)
   - `just/security/qt.just` (security-*-qt variants not referenced)
4. Delete any other `just/` files that no longer have recipes

### Step 6: Fix platform parameter consistency

Standardize `--platform` usage across all orchestrator.py calls.

1. Choose approach: **Option A** (always pass `--platform` explicitly) or **Option B** (keep auto-detection, document edge cases)
2. If Option A: add `--platform {{ tk_platform }}` to every orchestrator.py call
3. If Option B: identify remaining edge cases (Windows toolchains, Qt) and ensure `--platform` is passed only there
4. Update all affected recipes in `just/setup/` and `just/build/` files

### Step 7: Reduce alias proliferation

Quality and security have ~180 platform forwarding aliases across both files.

1. Evaluate options:
   - **Generator script:** `scripts/gen-aliases.py` generates platform aliases from canonical recipes
   - **Just alias syntax:** Use `alias foo-bar = recipe-name` instead of `foo-bar: recipe-name`
   - **Dispatcher pattern:** Replace individual aliases with single dispatcher + case routing
2. Pick the best option for the existing codebase
3. Implement the chosen approach
4. Verify: recipe count is reduced without losing any platform variants

### Step 8: Update CI workflows

Replace tool-specific setup calls with usage-based dispatchers.

| CI Workflow | Currently Calls | Replace With |
|---|---|---|
| `_ci-unit.yml` | `setup-zig`, `test-setup-install`, `test-setup-run` | `test-setup-unit` |
| `_ci-integration.yml` | `setup-zig` | `test-setup-unit` or `build-setup-fd` |
| `_ci-demo.yml` | `setup-zig` | `test-setup-unit` or `build-setup-fd` |
| `_ci-system.yml` | `setup-zig` | `test-setup-unit` or `build-setup-fd` |
| `_ci-quality.yml` | `setup-quality-linux-x86` | Keep (already usage-based) |
| `_ci-security-secrets.yml` | `setup-gitleaks-linux-x86` | `security-setup-secrets` |
| `_ci-security-deep.yml` | `setup-fd-linux-x86-gcc`, `setup-build-linux-x86-gcc`, etc. | `build-setup-fd`, `test-setup-unit`, etc. |
| `_ci-coverage.yml` | `setup-coverage-linux-x86-clang` | `test-setup-unit` or coverage-specific dispatcher |

1. Update each workflow YAML file
2. Run CI to verify all lanes pass
3. Remove any workflow steps that are no longer needed after dispatcher consolidation

## Verification Checklist

- [ ] `just --list` shows all recipes organized by category
- [ ] `just build-tk` works end-to-end
- [ ] `just build-fd` works end-to-end
- [ ] `just test-all` works end-to-end
- [ ] `just tests-all` works end-to-end
- [ ] CI workflows pass after Phase 6 updates
- [ ] No broken recipe references remain
- [ ] All platform aliases resolve correctly
- [ ] Recipe count in justfile: 161 → ~20
- [ ] 0 duplicate recipe names between justfile and just/
- [ ] `just file:vars` shows all variables still accessible

---

## Appendix A: Full Recipe Audit (Step 1 Output)

### Totals

| Source | Count |
|--------|-------|
| Justfile recipes | 215 |
| Just/ recipes (all 14 files) | 358 |
| Overlap (canonical — in both) | 194 |
| Only justfile | 21 |
| Only just/ (dead) | 164 |

### Variables (not recipes — kept from both sources)

**justfile only (19):** `make`, `python`, `fd_tickoni_build`, `fd_tickoni_dir`, `fd_tickoni_lib`, `fd_gcc_build`, `fd_gcc_dir`, `fd_gcc_lib`, `fd_clang_build`, `fd_clang_dir`, `fd_clang_lib`, `fd_cov_build`, `fd_cov_dir`, `fd_cov_lib`, `os`, `arch`, `tk_os`, `tk_arch`, `tk_platform`, `cpu_count`

**just/common.just (28):** `make`, `python`, `justfile_dir`, `fd_tickoni_build`, `fd_tickoni_dir`, `fd_tickoni_lib`, `fd_gcc_build`, `fd_gcc_dir`, `fd_gcc_lib`, `fd_clang_build`, `fd_clang_dir`, `fd_clang_lib`, `fd_arm_build`, `fd_arm_dir`, `fd_arm_lib`, `fd_cov_build`, `fd_cov_dir`, `fd_cov_lib`, `ZIG_CACHE`, `ZIG_GLOBAL_CACHE`, `ZIG_PREFIX`, `ZIG_PREFIX_REL`, `zig_linux_x86_cpu`, `os`, `arch`, `tk_os`, `tk_arch`, `tk_platform`, `cpu_count`

### Canonical Recipes (194 — in both justfile and just/)

**Build (23):** `build-all`, `build-fd`, `build-fd-arm`, `build-fd-clang`, `build-fd-dev`, `build-fd-gcc`, `build-fd-linux-arm-gcc`, `build-fd-linux-x86-clang`, `build-fd-linux-x86-gcc`, `build-fd-macos-arm`, `build-fd-macos-x86`, `build-fd-macos-x86_64`, `build-fd-tk-libs`, `build-fd-windows-arm`, `build-fd-windows-x86`, `build-tk`, `build-tk-linux-arm`, `build-tk-linux-x86`, `build-tk-macos-arm`, `build-tk-macos-x86`, `build-tk-windows-arm`, `build-tk-windows-x86`, `clean-all`

**Test (71):** `test-all`, `test-cov-all`, `test-cov-fd`, `test-cov-fd-linux-x86-clang`, `test-cov-tk`, `test-cov-tk-linux-x86`, `test-demo-tk`, `test-demo-tk-linux-x86`, `test-demo-tk-macos-arm`, `test-demo-tk-macos-x86`, `test-demo-tk-windows-arm`, `test-demo-tk-windows-x86`, `test-e2e-all`, `test-e2e-fd`, `test-e2e-tk`, `test-integration-all`, `test-integration-fd`, `test-integration-tk`, `test-integration-tk-linux-arm`, `test-integration-tk-linux-x86`, `test-integration-tk-macos-arm`, `test-integration-tk-macos-x86`, `test-integration-tk-windows-arm`, `test-integration-tk-windows-x86`, `test-prep-linux-x86`, `test-system-all`, `test-system-fd`, `test-system-tk`, `test-system-tk-linux-x86`, `test-system-tk-macos-arm`, `test-system-tk-macos-x86`, `test-system-tk-windows-arm`, `test-system-tk-windows-x86`, `test-unit-all`, `test-unit-tk-linux-arm`, `test-unit-tk-linux-x86`, `test-unit-tk-macos-arm`, `test-unit-tk-macos-x86`, `test-unit-tk-windows-arm`, `test-unit-tk-windows-x86`, `tests-all`, `compare-demo-conformance`, `export-demo-conformance-linux`, `export-demo-conformance-macos-15-arm`, `export-demo-conformance-macos-15-x86_64`, `export-demo-conformance-macos-26-arm`, `export-demo-conformance-macos-26-x86_64`, `export-demo-conformance-windows-arm`, `export-demo-conformance-windows-x86`, `gen-audit-fixtures`, `infra-ensure-llamacpp`, `infra-ensure-llamacpp-win`, `infra-ensure-model`

**Quality (34):** `quality-check-all`, `quality-format-check-all`, `quality-format-check-fd`, `quality-format-check-fd-linux-x86`, `quality-format-check-linux-x86`, `quality-format-check-tk`, `quality-format-check-tk-linux-x86`, `quality-format-fix-all`, `quality-format-fix-fd`, `quality-format-fix-fd-linux-x86`, `quality-format-fix-tk`, `quality-format-fix-tk-linux-x86`, `quality-lint-check-all`, `quality-lint-check-fd`, `quality-lint-check-fd-linux-x86`, `quality-lint-check-linux-x86`, `quality-lint-check-tk`, `quality-lint-check-tk-linux-x86`, `quality-proto-check-all`, `quality-proto-check-fd`, `quality-proto-check-fd-linux-x86`, `quality-proto-check-linux-x86`, `quality-proto-check-tk`, `quality-proto-check-tk-linux-x86`, `quality-spell-check-linux`, `quality-yaml-check-linux`

**Security (44):** `security-check-all`, `security-codeql-check-all`, `security-codeql-check-fd`, `security-codeql-check-fd-linux-x86`, `security-codeql-check-tk`, `security-codeql-check-tk-linux-x86`, `security-engine-check-all`, `security-engine-check-changes`, `security-engine-check-changes-linux-x86`, `security-engine-check-orchestration`, `security-engine-check-orchestration-linux-x86`, `security-gitleaks-check-all`, `security-gitleaks-check-fd`, `security-gitleaks-check-fd-linux-x86`, `security-gitleaks-check-linux-x86`, `security-gitleaks-check-tk`, `security-gitleaks-check-tk-linux-x86`, `security-proof-check-all`, `security-proof-check-fd`, `security-proof-check-fd-linux-x86`, `security-proof-check-linux-x86`, `security-proof-check-tk`, `security-proof-check-tk-linux-x86`, `security-sanitize-check-all`, `security-sanitize-check-fd`, `security-sanitize-check-fd-linux-x86`, `security-sanitize-check-linux-x86`, `security-sanitize-check-tk`, `security-sanitize-check-tk-linux-x86`, `security-seccomp-check-all`, `security-seccomp-check-fd`, `security-seccomp-check-fd-linux-x86`, `security-seccomp-check-linux-x86`, `security-seccomp-check-tk`, `security-seccomp-check-tk-linux-x86`

**Setup (57):** `setup-build-linux-arm-gcc`, `setup-build-linux-x86-clang`, `setup-build-linux-x86-gcc`, `setup-build-macos-arm`, `setup-build-macos-x86`, `setup-build-windows-arm`, `setup-build-windows-x86`, `setup-coverage-linux-x86-clang`, `setup-coverage-macos-arm`, `setup-coverage-macos-x86`, `setup-fd-deps-linux-arm-gcc`, `setup-fd-deps-linux-x86-clang`, `setup-fd-deps-linux-x86-gcc`, `setup-fd-deps-macos-arm`, `setup-fd-deps-macos-x86`, `setup-fd-deps-windows-arm`, `setup-fd-deps-windows-x86`, `setup-fd-linux-arm-gcc`, `setup-fd-linux-x86-clang`, `setup-fd-linux-x86-gcc`, `setup-fd-macos-arm`, `setup-fd-macos-x86`, `setup-fd-windows-arm`, `setup-fd-windows-x86`, `setup-git`, `setup-gitleaks-linux-x86`, `setup-gitleaks-macos-arm`, `setup-gitleaks-macos-x86`, `setup-gitleaks-windows-arm`, `setup-gitleaks-windows-x86`, `setup-linux-arm-clang`, `setup-linux-arm-gcc`, `setup-linux-x86-clang`, `setup-linux-x86-gcc`, `setup-macos-arm`, `setup-macos-x86`, `setup-qt-linux-arm`, `setup-qt-linux-x86`, `setup-qt-macos-arm`, `setup-qt-macos-x86`, `setup-qt-windows-arm`, `setup-qt-windows-x86`, `setup-quality-linux-x86`, `setup-quality-macos-arm`, `setup-quality-macos-x86`, `setup-quality-windows-arm`, `setup-quality-windows-x86`, `setup-security-linux-x86`, `setup-security-macos-x86`, `setup-security-windows-x86`, `setup-windows-arm`, `setup-windows-x86`

**Memory (4):** `mem-query`, `mem-reset`, `mem-fini`, `mem-drop-caches`, `kill-test`

### Dead Recipes (164 — only in just/, never invoked by justfile)

**Build (1):** `build-qt` (bare dispatcher — replaced by platform variants `build-qt-linux-x86` etc. in justfile)

**System test (1):** `test-system-tk-linux-arm`

**Demo (3):** `test-demo-all`, `test-demo-fd`, `test-demo-tk-linux-arm`

**Integration (14):** `test-integration-tk-domain`, `test-integration-tk-domain-linux-arm`, `test-integration-tk-domain-linux-x86`, `test-integration-tk-domain-macos-arm`, `test-integration-tk-domain-macos-x86`, `test-integration-tk-domain-windows-arm`, `test-integration-tk-domain-windows-x86`, `test-integration-tk-infra`, `test-integration-tk-infra-linux-arm`, `test-integration-tk-infra-linux-x86`, `test-integration-tk-infra-macos-arm`, `test-integration-tk-infra-macos-x86`, `test-integration-tk-infra-windows-arm`, `test-integration-tk-infra-windows-x86`

**Perf (10):** `test-perf-all`, `test-perf-fd`, `test-perf-qt`, `test-perf-tk`, `test-perf-tk-linux-arm`, `test-perf-tk-linux-x86`, `test-perf-tk-macos-arm`, `test-perf-tk-macos-x86`, `test-perf-tk-windows-arm`, `test-perf-tk-windows-x86`

**Unit (2):** `test-setup-install`, `test-setup-run`

**Setup (3):** `setup-quality` (bare), `setup-quality-linux-arm`, `setup-sanitizer-linux-x86-clang`, `setup-zig`

**Quality format (30):** `quality-format-check-fd-macos-arm`, `quality-format-check-fd-macos-x86`, `quality-format-check-fd-windows-arm`, `quality-format-check-fd-windows-x86`, `quality-format-check-qt`, `quality-format-check-qt-linux-x86`, `quality-format-check-qt-macos-arm`, `quality-format-check-qt-macos-x86`, `quality-format-check-qt-windows-arm`, `quality-format-check-qt-windows-x86`, `quality-format-check-tk-macos-arm`, `quality-format-check-tk-macos-x86`, `quality-format-check-tk-windows-arm`, `quality-format-check-tk-windows-x86`, `quality-format-fix-fd-macos-arm`, `quality-format-fix-fd-macos-x86`, `quality-format-fix-fd-windows-arm`, `quality-format-fix-fd-windows-x86`, `quality-format-fix-qt`, `quality-format-fix-qt-linux-x86`, `quality-format-fix-qt-macos-arm`, `quality-format-fix-qt-macos-x86`, `quality-format-fix-qt-windows-arm`, `quality-format-fix-qt-windows-x86`, `quality-format-fix-tk-macos-arm`, `quality-format-fix-tk-macos-x86`, `quality-format-fix-tk-windows-arm`, `quality-format-fix-tk-windows-x86`

**Quality lint (15):** `quality-lint-check-actions`, `quality-lint-check-fd-macos-arm`, `quality-lint-check-fd-macos-x86`, `quality-lint-check-fd-windows-arm`, `quality-lint-check-fd-windows-x86`, `quality-lint-check-qt`, `quality-lint-check-qt-linux-x86`, `quality-lint-check-qt-macos-arm`, `quality-lint-check-qt-macos-x86`, `quality-lint-check-qt-windows-arm`, `quality-lint-check-qt-windows-x86`, `quality-lint-check-tk-macos-arm`, `quality-lint-check-tk-macos-x86`, `quality-lint-check-tk-windows-arm`, `quality-lint-check-tk-windows-x86`

**Quality proto (8):** `quality-proto-check-fd-macos-arm`, `quality-proto-check-fd-macos-x86`, `quality-proto-check-fd-windows-arm`, `quality-proto-check-fd-windows-x86`, `quality-proto-check-tk-macos-arm`, `quality-proto-check-tk-macos-x86`, `quality-proto-check-tk-windows-arm`, `quality-proto-check-tk-windows-x86`

**Security codeql (18):** `security-codeql-check-fd-macos-arm`, `security-codeql-check-fd-macos-x86`, `security-codeql-check-fd-windows-arm`, `security-codeql-check-fd-windows-x86`, `security-codeql-check-qt`, `security-codeql-check-qt-macos-arm`, `security-codeql-check-qt-macos-x86`, `security-codeql-check-qt-windows-arm`, `security-codeql-check-qt-windows-x86`, `security-codeql-check-tk-macos-arm`, `security-codeql-check-tk-macos-x86`, `security-codeql-check-tk-windows-arm`, `security-codeql-check-tk-windows-x86`

**Security engine (8):** `security-engine-check-changes-macos-arm`, `security-engine-check-changes-macos-x86`, `security-engine-check-changes-windows-arm`, `security-engine-check-changes-windows-x86`, `security-engine-check-orchestration-macos-arm`, `security-engine-check-orchestration-macos-x86`, `security-engine-check-orchestration-windows-arm`, `security-engine-check-orchestration-windows-x86`

**Security gitleaks (14):** `security-gitleaks-check-fd-macos-arm`, `security-gitleaks-check-fd-macos-x86`, `security-gitleaks-check-fd-windows-arm`, `security-gitleaks-check-fd-windows-x86`, `security-gitleaks-check-qt`, `security-gitleaks-check-qt-linux-x86`, `security-gitleaks-check-qt-macos-arm`, `security-gitleaks-check-qt-macos-x86`, `security-gitleaks-check-qt-windows-arm`, `security-gitleaks-check-qt-windows-x86`, `security-gitleaks-check-tk-macos-arm`, `security-gitleaks-check-tk-macos-x86`, `security-gitleaks-check-tk-windows-arm`, `security-gitleaks-check-tk-windows-x86`

**Security proof (14):** `security-proof-check-fd-macos-arm`, `security-proof-check-fd-macos-x86`, `security-proof-check-fd-windows-arm`, `security-proof-check-fd-windows-x86`, `security-proof-check-qt`, `security-proof-check-qt-linux-x86`, `security-proof-check-qt-macos-arm`, `security-proof-check-qt-macos-x86`, `security-proof-check-qt-windows-arm`, `security-proof-check-qt-windows-x86`, `security-proof-check-tk-macos-arm`, `security-proof-check-tk-macos-x86`, `security-proof-check-tk-windows-arm`, `security-proof-check-tk-windows-x86`

**Security sanitize (14):** `security-sanitize-check-fd-macos-arm`, `security-sanitize-check-fd-macos-x86`, `security-sanitize-check-fd-windows-arm`, `security-sanitize-check-fd-windows-x86`, `security-sanitize-check-qt`, `security-sanitize-check-qt-linux-x86`, `security-sanitize-check-qt-macos-arm`, `security-sanitize-check-qt-macos-x86`, `security-sanitize-check-qt-windows-arm`, `security-sanitize-check-qt-windows-x86`, `security-sanitize-check-tk-macos-arm`, `security-sanitize-check-tk-macos-x86`, `security-sanitize-check-tk-windows-arm`, `security-sanitize-check-tk-windows-x86`

**Security seccomp (14):** `security-seccomp-check-fd-macos-arm`, `security-seccomp-check-fd-macos-x86`, `security-seccomp-check-fd-windows-arm`, `security-seccomp-check-fd-windows-x86`, `security-seccomp-check-qt`, `security-seccomp-check-qt-linux-x86`, `security-seccomp-check-qt-macos-arm`, `security-seccomp-check-qt-macos-x86`, `security-seccomp-check-qt-windows-arm`, `security-seccomp-check-qt-windows-x86`, `security-seccomp-check-tk-macos-arm`, `security-seccomp-check-tk-macos-x86`, `security-seccomp-check-tk-windows-arm`, `security-seccomp-check-tk-windows-x86`

**Infra (1):** `infra-ensure-llamacpp-win-arm`

### Recipes Only in Justfile (21 — no just/ equivalent)

**Build (6):** `build-qt-linux-arm`, `build-qt-linux-x86`, `build-qt-macos-arm`, `build-qt-macos-x86`, `build-qt-windows-arm`, `build-qt-windows-x86`

**Test unit (7):** `test-unit-fd`, `test-unit-fd-linux-x86-gcc`, `test-unit-fd-macos-arm`, `test-unit-fd-macos-x86`, `test-unit-fd-windows-arm`, `test-unit-fd-windows-x86`, `test-unit-tk`

**Memory (4):** `mem-alloc`, `mem-alloc-auto`, `mem-free`, `mem-init`

**Setup (1):** `setup-env`

**Other (3):** `default`, `dynamic-test-opts`, `help`
