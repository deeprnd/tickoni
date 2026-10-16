# Justfile Architecture Reorganization

**Date:** 2026-10-17
**Status:** planned
**Scope:** justfile, just/ directory, CI workflows

## Problem Statement

The justfile system has accumulated structural debt:

1. **Root justfile bloat — 161 recipes** mixing variables, setup, build, test, quality, security, memory management, and dispatchers
2. **Dead `just/` directory — 257 recipe names** across 14 files, but **never included** by justfile. All 145 duplicates have the same name as justfile recipes but may differ in body. The just/ files are unreachable dead code.
3. **145 duplicate recipes** between justfile and just/ — same names, sometimes different bodies, creating confusion about which is the source of truth
4. **`--platform` inconsistency** — some orchestrator.py calls pass `--platform`, others don't (Qt passes it everywhere; Windows passes it for toolchains; Linux/macOS rely on auto-detection)
5. **Tool-specific setup in CI** — workflows call `setup-zig`, `setup-gitleaks-linux-x86`, etc. instead of usage-based `test-setup-unit`, `security-setup-secrets`
6. **Alias proliferation** — quality and security have ~180 platform forwarding aliases across both files
7. **Cross-category calls** — test recipes call `just build-fd-*`, build recipes reference `just setup-qt-*` in error messages, `tests-all` calls `build-all`. This violates the strict category boundary rule: only `*-all` aggregate recipes in root justfile are allowed to call other categories, and only same-kind aggregates. No test→build, build→setup, test→setup, etc.

## Assessment Summary

### Recipe Distribution (current state)

| Location | Recipes | Notes |
|----------|---------|-------|
| justfile | 161 | Variables + setup + build + test + quality + security + mem + aliases |
| just/ (all files) | 257 unique names | 145 overlap with justfile (dead), 112 only in just/ (dead) |
| **Total dead duplicates** | **145** | Same name in both files, just/ unreachable |

### What's unique to each

| Only in justfile | Only in just/ |
|---|---|
| `build-qt-linux-*` (6) | `build-qt` (bare dispatcher) |
| `test-unit-fd-*` (6) | `test-unit-tk-linux-*`, `test-unit-tk-macos-*`, `test-unit-tk-windows-*` |
| `test-unit-tk` (1) | `test-setup-install`, `test-setup-run` |
| `default`, `help`, `dynamic-test-opts` | `setup-quality`, `setup-zig`, `setup-sanitizer-*` |
| ~22 quality recipes | `test-perf-*` (10) |
| ~29 security recipes | `test-demo-fd`, `test-demo-all`, `test-integration-tk-domain-*`, `test-integration-tk-infra-*` |
| ~45 setup recipes | `quality-format-check-qt`, `quality-lint-check-qt`, `quality-lint-check-actions` |
| mem-* (4), kill-test | `security-*-qt` variants (20+) |

### Cross-Category Call Violations

Rule: Only `*-all` aggregate recipes in root justfile may call other categories. No test→build, build→setup, test→setup, etc. Each category is self-contained — its recipes must not depend on other categories.

| Violating Recipe | Category | Calls | Target Category | Lines |
|---|---|---|---|---|
| `test-integration-tk-windows-x86` | test | `just build-fd-windows-x86` | build | 615 |
| `test-integration-tk-windows-arm` | test | `just build-fd-windows-arm` | build | 621 |
| `test-system-tk-windows-x86` | test | `just build-fd-windows-x86` | build | 687 |
| `test-system-tk-windows-arm` | test | `just build-fd-windows-arm` | build | 694 |
| `build-qt-linux-*` (×6) | build | `'just setup-qt-*' first` | setup | 340,350,360,370,380,390 |

After removing `just build-fd-*` from the Windows test recipes, they should be identical to the non-Windows platform variants (same `zig build` invocation), since the FD libraries are already present via CI artifact reuse. The only difference is that CI must ensure `build-fd` runs first (which it does via the workflow step ordering).

Notes:
- `tests-all` calling `build-all` is the top-level aggregator — its entire purpose is to aggregate all categories. This is allowed and should stay.
- `build-qt-*` referencing `just setup-qt-*` is only in error messages (`"run 'just setup-qt-*' first"`), not actual invocation. These should use an inline CMake check or remove the reference entirely.
- The Windows test→build calls are the worst offenders — they bake build dependencies into test recipes, making CI harder to reason about and preventing artifact reuse.

### Platform Parameter Inconsistency

Auto-detection (`detect_platform(None)`) works for most cases but fails for:
- Windows toolchains (msvc doesn't exist on other platforms)
- Qt dependency resolution
- Cases where `install_method` is an OS map

Current state: Qt passes `--platform` everywhere, Windows passes it for toolchains, Linux/macOS rely on auto-detection. This is asymmetric.

### CI Usage vs Tool Names

| CI Workflow | Currently Calls | Problem |
|-------------|----------------|---------|
| _ci-unit.yml | setup-zig, test-setup-install, test-setup-run | Knows about zig and pytest |
| _ci-integration.yml | setup-zig | Knows about zig |
| _ci-demo.yml | setup-zig | Knows about zig |
| _ci-system.yml | setup-zig | Knows about zig |
| _ci-quality.yml | setup-quality-linux-x86 | Ok (usage-based) |
| _ci-security-secrets.yml | setup-gitleaks-linux-x86 | Knows about gitleaks |
| _ci-security-deep.yml | setup-fd-linux-x86-gcc, setup-build-linux-x86-gcc, setup-sanitizer-..., setup-security-linux-x86, setup-qt-linux-x86 | Knows about fd, build, sanitizer, security, qt |
| _ci-coverage.yml | setup-coverage-linux-x86-clang | Knows about coverage |

## Reorganization Plan

### Phase 0: Audit and classify every recipe

Before moving anything, catalog every recipe from both sources and classify:

**Canonical (keep)** — actual implementation bodies used by CI or local dev:
- **Variables:** `make`, `python`, `justfile_dir`, `ZIG_CACHE`, `ZIG_GLOBAL_CACHE`, `ZIG_PREFIX`, `ZIG_PREFIX_REL`, `zig_linux_x86_cpu`, `os`, `arch`, `tk_os`, `tk_arch`, `tk_platform`, `cpu_count`, `fd_*` lib paths
- **Build:** `build-tk-*` (platform variants), `build-fd-*` (platform variants), `build-fd-tk-libs`, `build-fd-gcc`, `build-fd-clang`, `build-fd-arm`, `build-fd-macos-x86_64`, `build-fd-dev`, `build-all`, `build-qt-*`, `clean-all`, `build-tk`, `build-fd` dispatchers
- **Test:** `test-unit-fd-*`, `test-unit-tk-*`, `test-integration-tk-*`, `test-demo-tk`, `test-system-tk`, `test-e2e-*`, `export-demo-conformance-*`, `compare-demo-conformance`, `test-cov-*`, `gen-audit-fixtures`, `infra-ensure-*`, `dynamic-test-opts`, `test-all`, `tests-all` dispatchers
- **Quality:** `quality-format-check-*`, `quality-lint-check-*`, `quality-proto-check-*`, `quality-yaml-check-linux`, `quality-spell-check-linux`, `quality-check-all`
- **Security:** `security-codeql-check-*`, `security-gitleaks-check-*`, `security-seccomp-check-*`, `security-proof-check-*`, `security-sanitize-check-*`, `security-engine-check-*`, `security-check-all`
- **Setup:** `setup-build-*`, `setup-fd-*`, `setup-quality-*`, `setup-gitleaks-*`, `setup-linux-*`, `setup-macos-*`, `setup-windows-*`, `setup-fd-deps-*`, `setup-coverage-*`, `setup-security-*`, `setup-qt-*`, `setup-env`, `setup-git`, `test-prep-linux-x86`
- **Mem:** `mem-init`, `mem-query`, `mem-reset`, `mem-fini`, `mem-alloc`, `mem-alloc-auto`, `mem-free`, `mem-drop-caches`, `kill-test`

**Dead/removed** — recipes only in just/ that have no callers:
- `setup-quality` (bare dispatcher — replaced by per-platform variants in justfile)
- `setup-zig` (replaced by `setup-fd-*` which embeds zig,ssl)
- `setup-sanitizer-linux-x86-clang` (referenced nowhere)
- `test-demo-fd`, `test-demo-all` (CI only calls `test-demo-tk`)
- `test-integration-tk-domain-*`, `test-integration-tk-infra-*` (not referenced by CI)
- `test-perf-*` (not referenced by CI)
- `test-setup-install`, `test-setup-run` (referenced by test-unit-all in just/ but not by CI)
- `test-unit-tk-linux-*`, `test-unit-tk-macos-*`, `test-unit-tk-windows-*` (CI uses justfile versions)
- `build-qt` (just/ has this as CMake; justfile has `build-qt-*` platform variants)
- `quality-format-check-qt`, `quality-lint-check-qt`, `quality-lint-check-actions` (not referenced by CI)
- `security-*-qt` variants (20+ — not referenced by CI)

**New/missing** — recipes only in just/ that should exist in the reorganized tree:
- `build-tk-linux-arm`, `build-tk-macos-*`, `build-tk-windows-*` — platform variants that justfile delegates to via `build-tk` dispatcher. Currently justfile has them as aliases.
- `test-integration-tk-linux-arm`, `test-integration-tk-macos-*`, `test-integration-tk-windows-*` — platform variants referenced by test dispatcher
- `test-unit-tk-linux-arm`, `test-unit-tk-macos-*`, `test-unit-tk-windows-*` — referenced by unit test dispatcher

### Phase 1: Move canonical recipes to `just/` by category

**Destination structure:**

```
justfile                          # variables + includes + aggregate-all + dispatchers
├── just/vars.just                # All variable definitions (from common.just)
├── just/setup/install.just       # setup-build-*, setup-fd-*, setup-fd-deps-*, setup-coverage-*, setup-zig
├── just/setup/quality.just       # setup-quality-*
├── just/setup/secrets.just       # setup-gitleaks-*
├── just/setup/security.just      # setup-security-*
├── just/setup/qt.just            # setup-qt-*
├── just/setup/developer.just     # setup-env, setup-git, setup-linux-*, setup-macos-*, setup-windows-*, test-prep-linux-x86
├── just/build/dispatch.just      # build-tk, build-fd (bare dispatchers)
├── just/build/linux.just         # build-tk-linux-x86, build-tk-linux-arm, build-fd-linux-x86-gcc, build-fd-linux-x86-clang, build-fd-linux-arm-gcc
├── just/build/macos.just         # build-tk-macos-x86, build-tk-macos-arm, build-fd-macos-x86, build-fd-macos-arm
├── just/build/windows.just       # build-tk-windows-x86, build-tk-windows-arm, build-fd-windows-x86, build-fd-windows-arm
├── just/build/compat.just        # build-fd-gcc, build-fd-clang, build-fd-arm, build-fd-macos-x86_64, build-fd-tk-libs, build-fd-dev
├── just/build/qt.just            # build-qt-linux-x86, build-qt-linux-arm, build-qt-macos-x86, build-qt-macos-arm, build-qt-windows-x86, build-qt-windows-arm
├── just/test/dispatch.just       # test-all, test-unit-tk, test-unit-fd, test-integration-tk (bare dispatchers)
├── just/test/unit.just           # test-unit-tk-linux-x86, test-unit-fd-linux-x86-gcc, gen-audit-fixtures, test-unit-all, test-unit-tk-linux-arm, etc.
├── just/test/integration.just    # test-integration-tk-linux-x86, test-integration-tk-windows-x86, test-integration-tk-linux-arm, etc.
├── just/test/demo.just           # test-demo-tk, export-demo-conformance-*, compare-demo-conformance
├── just/test/system.just         # test-system-tk, infra-ensure-*, test-system-all
├── just/test/coverage.just       # test-cov-*
├── just/test/e2e.just            # test-e2e-*
├── just/quality.just             # quality-format-check-*, quality-lint-check-*, quality-proto-check-*, quality-yaml-check-linux, quality-spell-check-linux, quality-check-all
├── just/security.just            # security-*, security-check-all
├── just/system.mem.just          # mem-*, kill-test
```

Each file starts with a comment header identifying its category.

**Platform alias convention (enforced during Phase 1):**

When a test/quality/security recipe is identical across platforms, bundle all non-canonical platforms as aliases to the canonical implementation:

```
test-integration-tk-linux-x86:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test

test-integration-tk-linux-arm: test-integration-tk-linux-x86
test-integration-tk-macos-x86: test-integration-tk-linux-x86
test-integration-tk-macos-arm: test-integration-tk-linux-x86
test-integration-tk-windows-x86: test-integration-tk-linux-x86
test-integration-tk-windows-arm: test-integration-tk-linux-x86
```

Only deviate from the canonical implementation when there is a clear platform-specific reason (e.g., different lib path, different test binary, different environment). All other platform variants are zero-body aliases. This eliminates duplicate recipe bodies entirely.

- No recipe in `just/test/` may call `just build-*` or `just setup-*`
- No recipe in `just/build/` may call `just setup-*`
- No recipe in `just/quality/` or `just/security/` may call `just build-*`, `just setup-*`, or `just test-*`
- No recipe in `just/setup/` may call `just build-*`, `just test-*`, `just quality-*`, or `just security-*`
- The only allowed cross-category call is `tests-all` → `build-all` (root-level aggregator aggregating all categories). This stays in root justfile.
- No recipe in `just/test/` may call `just build-*` or `just setup-*` — test recipes must assume their build prerequisites are satisfied by CI, not invoke them
- Error messages in build recipes should not reference `just setup-*`; use inline checks or static analysis instead

### Phase 2: Fix cross-category violations before adding includes

justfile becomes thin (~40 lines):

```
# Variables
include just/vars.just

# Includes by category
include just/setup/install.just
include just/setup/quality.just
include just/setup/secrets.just
include just/setup/security.just
include just/setup/qt.just
include just/setup/developer.just
include just/build/dispatch.just
include just/build/linux.just
include just/build/macos.just
include just/build/windows.just
include just/build/compat.just
include just/build/qt.just
include just/test/dispatch.just
include just/test/unit.just
include just/test/integration.just
include just/test/demo.just
include just/test/system.just
include just/test/coverage.just
include just/test/e2e.just
include just/quality.just
include just/security.just
include just/system.mem.just

# Aggregate dispatchers (kept in root for cross-category calls)
tests-all:
    @just build-all
    @just quality-check-all
    @just test-all
    @just security-check-all

test-all:
    @just test-unit-all
    @just test-integration-all
    @just test-cov-all
    @just test-system-all
    @just test-e2e-all
    @just test-demo-all

# Bare dispatchers (kept in root for case routing)
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

default:
    @just --list

help:
    @just --list
```

### Phase 3: Delete `just/common.just`

After moving its contents to `just/vars.just` (variables) and `just/setup/*.just` (setup recipes), `just/common.just` is deleted.

### Phase 4: Fix platform parameter consistency

Standardize `--platform` usage. Choose one approach:

**Option A (explicit):** Always pass `--platform` explicitly. Eliminates all asymmetry.

**Option B (minimal):** Keep auto-detection but document edge cases. Only pass `--platform` where known to fail (Windows toolchains, Qt), then fix any remaining inconsistencies.

### Phase 5: Reduce alias proliferation

Quality and security have ~180 platform forwarding aliases across both files.

Options:
- **Generator script:** `scripts/gen-aliases.py` generates platform aliases from canonical recipes
- **Just alias syntax:** Use `alias foo-bar = recipe-name` instead of `foo-bar: recipe-name`
- **Dispatcher pattern:** Replace individual aliases with single dispatcher + case routing

### Phase 6: Update CI workflows

Replace tool-specific setup calls with usage-based dispatchers:
- `setup-zig` → `test-setup-unit` or `build-setup-fd`
- `setup-gitleaks-linux-x86` → `security-setup-secrets`
- `setup-fd-linux-x86-gcc` → `build-setup-fd`

## Execution Order

1. Phase 0 — Audit and classify every recipe (create the catalog)
2. Phase 1 — Move canonical recipes to `just/` by category
3. Phase 2 — Add `include` directives to justfile
4. Phase 3 — Delete `just/common.just`
5. Phase 4 — Fix platform parameter consistency
6. Phase 5 — Reduce alias proliferation
7. Phase 6 — Update CI workflows

## Verification

- `just --list` shows all recipes organized by category
- `just build-tk`, `just build-fd`, `just test-all`, `just tests-all` all work end-to-end
- CI workflows pass (after Phase 6)
- No broken recipe references
- All platform aliases still resolve correctly
- 161 → ~20 recipes in justfile (down from 161)
- 0 duplicate recipe names between justfile and just/
- `just file:vars` shows all variables still accessible
