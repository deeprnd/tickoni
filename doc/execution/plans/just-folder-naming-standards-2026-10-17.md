# Just Folder Naming Standards

**Date:** 2026-10-17
**Scope:** All files under `just/` and root `justfile`
**Purpose:** Define and enforce naming conventions for files, recipes, subdirectories, and the root justfile imports/aggregators

---

## 1. Current State (Verified on Disk)

```
just/
├── vars.just                              ← shared variables (root import, correct)
├── quality/
│   ├── all.just                           ← quality-check-all ✅
│   ├── format.just                        ← quality-format-* ✅
│   ├── lint.just                          ← quality-lint-* ✅
│   ├── proto.just                         ← quality-proto-* ✅
│   ├── yaml.just                          ← quality-yaml-* ✅
│   └── spell.just                         ← quality-spell-* ✅
├── security/
│   ├── all.just                           ← security-check-all ✅
│   ├── codeql.just                        ← security-codeql-* ✅
│   ├── engine.just                        ← security-engine-* ✅
│   ├── gitleaks.just                      ← security-gitleaks-* ✅
│   ├── proof.just                         ← security-proof-* ✅
│   ├── sanitize.just                      ← security-sanitize-* ✅
│   └── seccomp.just                       ← security-seccomp-* ✅
├── build/
│   ├── all.just                           ← build-all, clean-all ✅
│   ├── fd.just                            ← build-fd-* ✅
│   ├── qt.just                            ← build-qt-* ✅
│   └── tk.just                            ← build-tk-* ✅
├── setup/
│   ├── build.just                         ← setup-build-* ✅ bare name
│   ├── coverage.just                      ← setup-coverage-* ✅ bare name
│   ├── dev-env.just                       ← setup-linux-x86-gcc, setup-dev-env-* ⚠️ redundant, remove
│   ├── env.just                           ← setup-all ⚠️ should be all.just
│   ├── fd.just                            ← setup-fd-* ✅ bare name
│   ├── git.just                           ← setup-git ✅ bare name
│   ├── just.just                          ← setup-just ✅ bare name
│   ├── qt.just                            ← setup-qt-* ✅ bare name
│   ├── quality.just                       ← setup-quality-* ✅ bare name
│   ├── secrets.just                       ← setup-gitleaks-* ⚠️ wrong concept
│   ├── security.just                      ← setup-security-* ✅ bare name
│   └── zig.just                           ← setup-zig ✅ bare name
├── system/
│   └── system.just                        ← mem-*, kill-test ⚠️ naming mismatch
└── test/
    ├── all.just                           ← test-all ✅
    ├── coverage.just                      ← test-cov-* ✅
    ├── demo.just                          ← test-demo-* ✅
    ├── dynamic.just                       ← dynamic-test-opts ✅
    ├── e2e.just                           ← test-e2e-* ✅
    ├── integration.just                   ← test-integration-* ✅
    ├── perf.just                          ← test-perf-* ✅
    ├── system.just                        ← test-system-* ✅
    ├── test-include.just                  ← test-include ✅
    └── unit.just                          ← test-unit-* ✅
```

## 2. Problems

### 2.1 Uniform Pattern: No Exceptions

**Every domain directory has exactly one `all.just` as the aggregator, followed by bare `{identifier}.just` files for each sub-domain.**

| Domain | all.just Content |
|--------|-----------------|
| `build/` | `build-all` (calls build-fd, build-tk, build-qt) |
| `test/` | `test-all` (calls test-unit-all, test-integration-all, etc.) |
| `quality/` | `quality-check-all` (calls quality-format-check-all, etc.) |
| `security/` | `security-check-all` (calls security-engine-check-all, etc.) |
| `setup/` | `setup-all` (calls setup-fd, setup-zig, setup-qt, etc.) |

### 2.2 Setup/ `env.just` — Should Be `all.just`

`env.just` contains `setup-all`. It should be named `all.just` to match every other domain's aggregator pattern.

### 2.3 Setup/ `dev-env.just` — Redundant, Remove Entirely

`dev-env.just` contains platform-specific convenience aliases (`setup-linux-x86-gcc` etc.) that chain to existing setup commands, plus `setup-dev-env-linux-x86` dev stacks and `test-prep-linux-x86`. All redundant — `setup-all` in `all.just` installs everything. `setup-fd`, `setup-zig`, `setup-qt` etc. are available individually.

**Action: Delete `dev-env.just` entirely.**

### 2.4 Setup/ `secrets.just` — Wrong Concept

`secrets.just` contains `setup-gitleaks-*` recipes. Rename to `gitleaks.just` to match the recipe prefix.

### 2.5 system/system.just: File Name vs Recipe Name Mismatch

The file is named `system.just` but contains recipes with `mem-*` and `kill-test` prefixes (no `system-` prefix).

**Action:** Rename all recipes to use the `system-` prefix.

### 2.6 Root justfile: Import Pattern

The root justfile must import each sub-file individually (justfile doesn't follow nested imports). This should be consistent across all domains.

### 2.7 Root justfile: Aggregator Consistency

Root dispatchers (`tests-all`) should call only each domain's `*-all` aggregator: `build-all`, `test-all`, `quality-check-all`, `security-check-all`.

## 3. Proposed Standards

### Standard 1: Uniform Bare Names — No Prefixes

**Rule:** All files across all domains use bare `{identifier}.just` names. The directory provides the namespace.

| Domain | Pattern | Examples |
|--------|---------|----------|
| `setup/` | `{tool}.just` | `fd.just`, `zig.just`, `qt.just`, `git.just`, `build.just`, `coverage.just`, `gitleaks.just`, `just.just`, `quality.just`, `security.just`, `all.just` |
| `build/` | `{product}.just` | `fd.just`, `tk.just`, `qt.just` |
| `quality/` | `{check}.just` | `format.just`, `lint.just`, `proto.just`, `yaml.just`, `spell.just` |
| `security/` | `{check}.just` | `codeql.just`, `gitleaks.just`, `seccomp.just`, `proof.just`, `sanitize.just`, `engine.just` |
| `test/` | `{domain}.just` | `unit.just`, `integration.just`, `e2e.just`, `perf.just`, `demo.just`, `coverage.just`, `system.just`, `utils.just` |
| `system/` | `{utility}.just` | `system.just` (contains all system utilities) |

### Standard 2: Recipe Naming

**Rule:** Recipe names follow `{domain}-{category}-{scope}` where:
- `{domain}` = setup, build, test, quality, security, system
- `{category}` = specific sub-area (fd, tk, qt, format, lint, etc.)
- `{scope}` = check, fix, all, linux-x86, macos-arm, etc.

| Domain | Examples |
|--------|----------|
| setup | `setup-fd-linux-x86-gcc`, `setup-zig`, `setup-git`, `setup-coverage-macos-arm`, `setup-all` |
| build | `build-fd-linux-x86-gcc`, `build-tk-macos-arm`, `build-qt-windows-x86` |
| test | `test-unit-tk-linux-x86`, `test-integration-fd`, `test-e2e-all` |
| quality | `quality-format-check-fd`, `quality-lint-check-linux-x86` |
| security | `security-gitleaks-check-tk`, `security-seccomp-check-all` |
| system | `system-mem-alloc-auto`, `system-kill-test` |

### Standard 3: system/ Recipes — Add `system-` Prefix

**Rule:** All recipes in `just/system/system.just` use the `system-` prefix for consistency.

| Current | Proposed |
|---------|----------|
| `mem-init` | `system-mem-init` |
| `mem-query` | `system-mem-query` |
| `mem-reset` | `system-mem-reset` |
| `mem-fini` | `system-mem-fini` |
| `mem-alloc` | `system-mem-alloc` |
| `mem-alloc-auto` | `system-mem-alloc-auto` |
| `mem-free` | `system-mem-free` |
| `mem-drop-caches` | `system-mem-drop-caches` |
| `kill-test` | `system-kill-test` |

### Standard 4: Platform Identifiers

**Rule:** Use the 2-part `os-arch` format from `contrib/platform.sh`:

| Identifier | Platform |
|------------|----------|
| `linux-x86` | Linux x86_64 |
| `linux-arm` | Linux ARM64 |
| `macos-x86` | macOS x86_64 |
| `macos-arm` | macOS ARM64 |
| `windows-x86` | Windows x86_64 |
| `windows-arm` | Windows ARM64 |

No version numbers, no `_64` suffixes, no `aarch64`. Always `os-arch`.

### Standard 5: all.just as Domain Aggregator

**Rule:** Every domain directory has exactly one `all.just` that aggregates all sub-files. The root justfile imports both the `all.just` AND individual sub-files (justfile doesn't follow nested imports).

| Domain | all.just Content |
|--------|-----------------|
| `build/` | `build-all` (calls build-fd, build-tk, build-qt) |
| `test/` | `test-all` (calls test-unit-all, test-integration-all, etc.) |
| `quality/` | `quality-check-all` (calls quality-format-check-all, etc.) |
| `security/` | `security-check-all` (calls security-engine-check-all, etc.) |
| `setup/` | `setup-all` (calls setup-fd, setup-zig, setup-qt, etc.) |

### Standard 6: Root justfile Imports

**Rule:** Root justfile imports:
1. `vars.just` first (variables)
2. Each domain's `all.just` (aggregators)
3. Each domain's sub-files individually (justfile doesn't follow nested imports)
4. No other files

```justfile
# Variables
import "just/vars.just"

# Setup (all bare names, no prefixes, all.just is aggregator)
import "just/setup/all.just"
import "just/setup/build.just"
import "just/setup/coverage.just"
import "just/setup/fd.just"
import "just/setup/git.just"
import "just/setup/just.just"
import "just/setup/gitleaks.just"
import "just/setup/qt.just"
import "just/setup/quality.just"
import "just/setup/security.just"
import "just/setup/zig.just"

# Build
import "just/build/all.just"
import "just/build/fd.just"
import "just/build/qt.just"
import "just/build/tk.just"

# Test
import "just/test/all.just"
import "just/test/coverage.just"
import "just/test/demo.just"
import "just/test/e2e.just"
import "just/test/integration.just"
import "just/test/perf.just"
import "just/test/system.just"
import "just/test/unit.just"
import "just/test/utils.just"

# Quality
import "just/quality/all.just"
import "just/quality/format.just"
import "just/quality/lint.just"
import "just/quality/proto.just"
import "just/quality/yaml.just"
import "just/quality/spell.just"

# Security
import "just/security/all.just"
import "just/security/codeql.just"
import "just/security/engine.just"
import "just/security/gitleaks.just"
import "just/security/proof.just"
import "just/security/sanitize.just"
import "just/security/seccomp.just"

# System
import "just/system/system.just"

# Root-level aggregators
tests-all:
    @just build-all
    @just test-all
    @just quality-check-all
    @just security-check-all
```

## 4. Proposed Final Directory Structure

```
just/
├── vars.just                              ← shared variables
├── build/
│   ├── all.just                           ← build-all, clean-all
│   ├── fd.just                            ← build-fd-*
│   ├── qt.just                            ← build-qt-*
│   └── tk.just                            ← build-tk-*
├── quality/
│   ├── all.just                           ← quality-check-all
│   ├── format.just                        ← quality-format-*
│   ├── lint.just                          ← quality-lint-*
│   ├── proto.just                         ← quality-proto-*
│   ├── yaml.just                          ← quality-yaml-*
│   └── spell.just                         ← quality-spell-*
├── security/
│   ├── all.just                           ← security-check-all
│   ├── codeql.just                        ← security-codeql-*
│   ├── engine.just                        ← security-engine-*
│   ├── gitleaks.just                      ← security-gitleaks-*
│   ├── proof.just                         ← security-proof-*
│   ├── sanitize.just                      ← security-sanitize-*
│   └── seccomp.just                       ← security-seccomp-*
├── setup/
│   ├── all.just                           ← setup-all (was env.just)
│   ├── build.just                         ← setup-build-*
│   ├── coverage.just                      ← setup-coverage-*
│   ├── fd.just                            ← setup-fd-*
│   ├── git.just                           ← setup-git
│   ├── gitleaks.just                      ← setup-gitleaks-* (was secrets.just)
│   ├── just.just                          ← setup-just
│   ├── qt.just                            ← setup-qt-*
│   ├── quality.just                       ← setup-quality-*
│   ├── security.just                      ← setup-security-*
│   └── zig.just                           ← setup-zig
├── system/
│   └── system.just                        ← system-mem-*, system-kill-test
└── test/
    ├── all.just                           ← test-all
    ├── coverage.just                      ← test-cov-*
    ├── demo.just                          ← test-demo-*
    ├── e2e.just                           ← test-e2e-*
    ├── integration.just                   ← test-integration-*
    ├── perf.just                          ← test-perf-*
    ├── system.just                        ← test-system-*
    ├── unit.just                          ← test-unit-*
    └── utils.just                         ← dynamic-test-opts, test-include (merged from dynamic.just + test-include.just)
```

## 5. Implementation Plan

### Phase 1: Rename setup/env.just → setup/all.just

Move `env.just` to `all.just`. Recipe stays `setup-all`.

| Rename From | Rename To |
|-------------|-----------|
| `setup/env.just` | `setup/all.just` |

**Impact:** Update root justfile import from `env.just` to `all.just`.

**Status:** ✅ Done

### Phase 2: Delete setup/dev-env.just

Remove the file entirely. Content is redundant — `all.just` provides `setup-all` which installs everything. CI workflows calling `setup-linux-x86-gcc` or `setup-dev-env-linux-x86` should use `setup-all` or chain individual setup commands.

**Status:** ✅ Done

### Phase 3: Rename setup/secrets.just → setup/gitleaks.just

| Rename From | Rename To |
|-------------|-----------|
| `setup/secrets.just` | `setup/gitleaks.just` |

**Impact:** Update root justfile import. No recipe changes.

**Status:** ✅ Done

### Phase 4: Rename system/ Recipes (9 recipes)

| From | To |
|------|----|
| `mem-init` | `system-mem-init` |
| `mem-query` | `system-mem-query` |
| `mem-reset` | `system-mem-reset` |
| `mem-fini` | `system-mem-fini` |
| `mem-alloc` | `system-mem-alloc` |
| `mem-alloc-auto` | `system-mem-alloc-auto` |
| `mem-free` | `system-mem-free` |
| `mem-drop-caches` | `system-mem-drop-caches` |
| `kill-test` | `system-kill-test` |

**Impact:** Any external caller of `just mem-*` or `just kill-test` needs updating. Check CI workflows and documentation.

**Status:** ✅ Done

### Phase 5: Update Root justfile Imports

Update all imports to match the final directory structure. No `install-` prefixes. No `dev-env.just` or `env.just` imports.

**Status:** ✅ Done

### Phase 6: Verify

1. `just --dump` parses without errors
2. `just --list` shows all recipes with new names
3. `just tests-all --dry-run` resolves correctly
4. Check CI workflows for `just mem-*`, `just kill-test`, `just setup-linux-x86-gcc`, `just setup-dev-env-*` references
5. No orphaned imports or references

**Status:** ✅ Done

### Phase 7: Update CI Workflows

- `_ci-integration.yml`: `just mem-alloc-auto` → `just system-mem-alloc-auto`
- `_ci-system.yml`: `just mem-alloc-auto` → `just system-mem-alloc-auto`
- `_ci-unit.yml`: `just mem-alloc-auto` → `just system-mem-alloc-auto`
- `tests-dev-setup.yml`: `just setup-linux-x86-gcc` → `just setup-all`

**Status:** ✅ Done

### Phase 8: Merge test/dynamic.just + test/test-include.just → test/utils.just

Merged two small files into `test/utils.just` following the plan's proposed structure. Deleted originals.

**Status:** ✅ Done

## 6. Naming Decision Rationale

### Why uniform `all.just` aggregator in every domain?

Every domain directory follows the same pattern: `all.just` is the aggregator, all other files are bare `{identifier}.just`. This is consistent, predictable, and requires no special cases. `setup/all.just` → `setup-all`, `build/all.just` → `build-all`, etc.

### Why uniform bare names (no prefixes) across all domains?

- **Directory provides namespace:** `setup/fd.just` is unambiguous. Adding `install-` prefix is redundant noise.
- **Consistent across domains:** `build/fd.just`, `quality/format.just`, `test/unit.just`, `setup/fd.just` — all follow the same pattern. No special case for any domain.
- **Cleaner:** Fewer characters, no arbitrary prefix conventions.
- **Scalable:** When adding new files, the convention is established — just use `{identifier}.just`.

### Why remove dev-env.just?

`all.just` provides `setup-all` which installs everything. Platform-specific convenience aliases (`setup-linux-x86-gcc`) and dev stacks (`setup-dev-env-linux-x86`) are unnecessary complexity. Developers can run `just setup-all` or chain individual commands (`setup-fd`, `setup-zig`, `setup-qt`) as needed.

### Why `secrets.just` → `gitleaks.just`?

The file installs gitleaks specifically. "secrets" is a concept, not a tool. The recipe prefix is `setup-gitleaks-*`, so the file name should match.

### Why `system-` prefix for mem/kill recipes?

The recipes live in `just/system/system.just`. `system-mem-*` and `system-kill-*` make it clear these are system-level utilities and won't collide with any future domain-level `mem-*` or `kill-*` recipes.

### Why keep quality/security at root?

These are domain-specific check recipes, not installers. They belong at the top level for frequent reference. The subdirectory structure (`quality/format.just`, `security/engine.just`) provides good granularity without adding nesting.
