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
│   ├── build.just                         ← setup-build-* ⚠️ should be install-build.just
│   ├── coverage.just                      ← setup-coverage-* ⚠️ should be install-coverage.just
│   ├── dev-env.just                       ← setup-dev-env-* ⚠️ should be install-dev-env.just
│   ├── env.just                           ← setup-all ⚠️ ambiguous name
│   ├── fd.just                            ← setup-fd-* ⚠️ should be install-fd.just
│   ├── git.just                           ← setup-git ⚠️ should be install-git.just
│   ├── just.just                          ← setup-just ⚠️ should be install-just.just
│   ├── qt.just                            ← setup-qt-* ⚠️ should be install-qt.just
│   ├── quality.just                       ← setup-quality-* ⚠️ should be install-quality.just
│   ├── secrets.just                       ← setup-gitleaks-* ⚠️ should be install-secrets.just
│   ├── security.just                      ← setup-security-* ⚠️ should be install-security.just
│   └── zig.just                           ← setup-zig ⚠️ should be install-zig.just
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

### 2.1 Setup/ Directory: Bare Names vs install-* Prefix

| File | Recipe Prefix | Issue |
|------|--------------|-------|
| `build.just` | `setup-build-*` | bare name, should be `install-build.just` |
| `coverage.just` | `setup-coverage-*` | bare name, should be `install-coverage.just` |
| `dev-env.just` | `setup-dev-env-*` | bare name, should be `install-dev-env.just` |
| `env.just` | `setup-all` | ambiguous, should describe what it sets up |
| `fd.just` | `setup-fd-*` | bare name, should be `install-fd.just` |
| `git.just` | `setup-git` | bare name, should be `install-git.just` |
| `just.just` | `setup-just` | bare name, should be `install-just.just` |
| `qt.just` | `setup-qt-*` | bare name, should be `install-qt.just` |
| `quality.just` | `setup-quality-*` | bare name, should be `install-quality.just` |
| `secrets.just` | `setup-gitleaks-*` | bare name + wrong concept (secrets != gitleaks), should be `install-secrets.just` |
| `security.just` | `setup-security-*` | bare name, should be `install-security.just` |
| `zig.just` | `setup-zig` | bare name, should be `install-zig.just` |

### 2.2 system/system.just: File Name vs Recipe Name Mismatch

The file is named `system.just` but contains recipes with `mem-*` and `kill-test` prefixes. It should either:
- Be renamed to match content: `system.just` → recipes should be `system-mem-*` and `system-kill-*`
- OR keep `mem-*` recipes and rename file to `mem.just` (less ideal, since it also has kill-test)

### 2.3 Root justfile: Import Pattern Inconsistency

The root justfile imports `all.just` (aggregators) AND individual sub-files in some domains but not others. This creates:
- Redundant imports (sub-files are already importable via their `all.just`'s directory, but justfile doesn't follow nested imports)
- Inconsistent patterns across domains

### 2.4 Root justfile: Aggregator Consistency

The root `justfile` has dispatcher recipes (`tests-all`, `build-all`, `test-all`) that mix aggregation levels. Need to verify they all follow the same pattern: each domain calls only its own `*-all` aggregator.

## 3. Proposed Standards

### Standard 1: setup/ Files — install-* Prefix

**Rule:** Every file in `just/setup/` must use the `install-*` prefix to describe what tool/component it installs.

| Current | Proposed | Rationale |
|---------|----------|-----------|
| `build.just` | `install-build.just` | Installs build toolchain |
| `coverage.just` | `install-coverage.just` | Installs coverage toolchain |
| `dev-env.just` | `install-dev-env.just` | Installs dev environment |
| `env.just` | `install-env.just` | Installs full dev environment |
| `fd.just` | `install-fd.just` | Installs Firedancer toolchain |
| `git.just` | `install-git.just` | Installs git hooks |
| `just.just` | `install-just.just` | Installs just binary |
| `qt.just` | `install-qt.just` | Installs Qt 6 |
| `quality.just` | `install-quality.just` | Installs quality tools |
| `secrets.just` | `install-secrets.just` | Installs secrets tooling |
| `security.just` | `install-security.just` | Installs security tooling |
| `zig.just` | `install-zig.just` | Installs Zig |

### Standard 2: Recipe Naming — setup-* Prefix

**Rule:** All setup/ recipes use the `setup-*` prefix regardless of file name. File names describe WHAT is installed; recipe names describe the ACTION.

| File | Recipe Prefix | Alignment |
|------|--------------|-----------|
| `install-build.just` | `setup-build-*` | File=install-build, recipe=setup-build — consistent |
| `install-qt.just` | `setup-qt-*` | File=install-qt, recipe=setup-qt — consistent |
| `install-secrets.just` | `setup-gitleaks-*` | File=install-secrets, recipe=setup-gitleaks — acceptable (tool name) |
| `install-dev-env.just` | `setup-dev-env-*` | File=install-dev-env, recipe=setup-dev-env — consistent |

### Standard 3: system/ File — Match Content

**Rule:** File names in `just/system/` should reflect the recipe prefixes they contain.

| Current | Proposed | Rationale |
|---------|----------|-----------|
| `system/system.just` with `mem-*` + `kill-test` recipes | Keep `system/system.just` but rename recipes to `system-mem-*` and `system-kill-*` OR rename file to `mem.just` and keep `mem-*` + add `system-kill-*` | Option A is cleaner: one file per concern, consistent `system-*` prefix |

**Recommendation:** Keep `system/system.just` as the file but standardize recipes:
- `mem-init` → `system-mem-init`
- `mem-query` → `system-mem-query`
- `mem-reset` → `system-mem-reset`
- `mem-fini` → `system-mem-fini`
- `mem-alloc` → `system-mem-alloc`
- `mem-alloc-auto` → `system-mem-alloc-auto`
- `mem-free` → `system-mem-free`
- `mem-drop-caches` → `system-mem-drop-caches`
- `kill-test` → `system-kill-test`

### Standard 4: Recipe → Domain Prefix

**Rule:** Recipe names follow `{domain}-{category}-{scope}` where:
- `{domain}` = build, test, quality, security, setup, system
- `{category}` = specific sub-area (fd, tk, qt, format, lint, etc.)
- `{scope}` = check, fix, all, linux-x86, macos-arm, etc.

| Domain | Examples |
|--------|----------|
| build | `build-fd-linux-x86-gcc`, `build-tk-macos-arm`, `build-qt-windows-x86` |
| test | `test-unit-tk-linux-x86`, `test-integration-fd`, `test-e2e-all` |
| quality | `quality-format-check-fd`, `quality-lint-check-linux-x86` |
| security | `security-gitleaks-check-tk`, `security-seccomp-check-all` |
| setup | `setup-fd-linux-x86-gcc`, `setup-coverage-macos-arm`, `setup-git` |
| system | `system-mem-alloc-auto`, `system-kill-test` |

### Standard 5: Platform Identifiers

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

### Standard 6: all.just as Domain Aggregator

**Rule:** Each domain directory has exactly one `all.just` that aggregates all sub-files. The root justfile imports both the `all.just` AND individual sub-files (justfile does not follow nested imports).

| Domain | all.just Content |
|--------|-----------------|
| `build/` | `build-all` (calls build-fd, build-tk, build-qt) |
| `test/` | `test-all` (calls test-unit-all, test-integration-all, etc.) |
| `quality/` | `quality-check-all` (calls quality-format-check-all, etc.) |
| `security/` | `security-check-all` (calls security-engine-check-all, etc.) |

### Standard 7: Root justfile Imports

**Rule:** Root justfile imports:
1. `vars.just` first (variables)
2. Each domain's `all.just` (aggregators)
3. Each domain's sub-files individually (justfile doesn't follow nested imports)
4. No other files

```justfile
# Variables
import "just/vars.just"

# Setup
import "just/setup/install-build.just"
import "just/setup/install-coverage.just"
import "just/setup/install-dev-env.just"
import "just/setup/install-env.just"
import "just/setup/install-fd.just"
import "just/setup/install-git.just"
import "just/setup/install-just.just"
import "just/setup/install-qt.just"
import "just/setup/install-quality.just"
import "just/setup/install-secrets.just"
import "just/setup/install-security.just"
import "just/setup/install-zig.just"

# Build
import "just/build/all.just"
import "just/build/fd.just"
import "just/build/qt.just"
import "just/build/tk.just"

# Test
import "just/test/all.just"
import "just/test/coverage.just"
import "just/test/demo.just"
import "just/test/dynamic.just"
import "just/test/e2e.just"
import "just/test/integration.just"
import "just/test/perf.just"
import "just/test/system.just"
import "just/test/test-include.just"
import "just/test/unit.just"

# Quality
import "just/quality/all.just"
import "just/quality/format.just"
import "just/quality/lint.just"
import "just/quality/proto.just"
import "just/quality/spell.just"
import "just/quality/yaml.just"

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
│   ├── install-build.just                 ← setup-build-*
│   ├── install-coverage.just              ← setup-coverage-*
│   ├── install-dev-env.just               ← setup-dev-env-*
│   ├── install-env.just                   ← setup-all
│   ├── install-fd.just                    ← setup-fd-*
│   ├── install-git.just                   ← setup-git
│   ├── install-just.just                  ← setup-just
│   ├── install-qt.just                    ← setup-qt-*
│   ├── install-quality.just               ← setup-quality-*
│   ├── install-secrets.just               ← setup-gitleaks-*
│   ├── install-security.just              ← setup-security-*
│   └── install-zig.just                   ← setup-zig
├── system/
│   └── system.just                        ← system-mem-*, system-kill-test
└── test/
    ├── all.just                           ← test-all
    ├── coverage.just                      ← test-cov-*
    ├── demo.just                          ← test-demo-*
    ├── dynamic.just                       ← dynamic-test-opts
    ├── e2e.just                           ← test-e2e-*
    ├── integration.just                   ← test-integration-*
    ├── perf.just                          ← test-perf-*
    ├── system.just                        ← test-system-*
    ├── test-include.just                  ← test-include
    └── unit.just                          ← test-unit-*
```

## 5. Implementation Plan

### Phase 1: Rename setup/ Files (12 files)

All recipes keep their `setup-*` prefix. Only filenames change.

| Rename From | Rename To |
|-------------|-----------|
| `setup/build.just` | `setup/install-build.just` |
| `setup/coverage.just` | `setup/install-coverage.just` |
| `setup/dev-env.just` | `setup/install-dev-env.just` |
| `setup/env.just` | `setup/install-env.just` |
| `setup/fd.just` | `setup/install-fd.just` |
| `setup/git.just` | `setup/install-git.just` |
| `setup/just.just` | `setup/install-just.just` |
| `setup/qt.just` | `setup/install-qt.just` |
| `setup/quality.just` | `setup/install-quality.just` |
| `setup/secrets.just` | `setup/install-secrets.just` |
| `setup/security.just` | `setup/install-security.just` |
| `setup/zig.just` | `setup/install-zig.just` |

**Impact:** Git rename only. No recipe changes. No CI changes (CI calls `just setup-*`, not filenames).

### Phase 2: Rename system/ Recipes (9 recipes)

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

**Impact:** Any external caller of `just mem-*` or `just kill-test` needs updating. Check CI workflows and any documentation.

### Phase 3: Update Root justfile Imports

Update the root `justfile` to use all new `install-*` paths and ensure every sub-file is imported (not just `all.just`).

### Phase 4: Verify

1. `just --dump` parses without errors
2. `just --list` shows all recipes with new names
3. `just tests-all --dry-run` resolves correctly
4. Check CI workflows for any `just mem-*` or `just kill-test` references
5. No orphaned imports or references

## 6. Naming Decision Rationale

### Why `install-*` for setup/ files?

- **Describes content:** Each file installs a specific tool. `install-zig` clearly means "this file contains Zig installation recipes."
- **Consistent:** 7 of 13 setup files already used `install-*`. The rest should follow.
- **Distinguishes from recipe prefix:** File names describe what IS (`install-*`), recipe names describe the action (`setup-*`).
- **Scalable:** When adding new installers, the convention is established.

### Why keep quality/security at root?

These are domain-specific check recipes, not installers. They belong at the top level for frequent reference. The subdirectory structure (`quality/format.just`, `security/engine.just`) provides good granularity without adding nesting for the root import.

### Why system-* prefix for mem/kill recipes?

The recipes live in `just/system/system.just`. Having `mem-*` and `kill-test` without the `system-` prefix breaks the domain prefix convention. Using `system-mem-*` and `system-kill-*` makes it clear these are system-level utilities, and they won't collide with any future domain-level `mem-*` or `kill-*` recipes.
