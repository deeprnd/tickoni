# Just Directory Naming Standards

**Date:** 2026-10-17
**Scope:** All files under `just/` and root `justfile`
**Purpose:** Define naming conventions for files, recipes, and subdirectories

---

## Current State

### Directory Structure (28 files, ~241 recipes)

```
just/
├── vars.just                              ← shared variables
├── quality.just                           ← quality check recipes
├── security.just                          ← security check recipes
├── system.mem.just                        ← system utilities (hugepages, kill-test)
├── test-import.just                       ← test helper (1 recipe: test-include)
├── build/
│   ├── all.just                           ← aggregate dispatcher (build-all, clean-all)
│   ├── build-fd.just                      ← Firedancer build
│   ├── build-qt.just                      ← Qt terminal build
│   └── build-tk.just                      ← Tickoni/Zig build
├── setup/
│   ├── developer.just                     ← platform dev stacks + test-prep
│   ├── install-build.just                 ← build toolchain
│   ├── install-coverage.just              ← coverage toolchain
│   ├── install-env.just                   ← full dev environment setup
│   ├── install-fd.just                    ← Firedancer toolchain
│   ├── install-git.just                   ← git hooks
│   ├── install-just.just                  ← just installer
│   ├── install-zig.just                   ← zig installer
│   ├── qt.just                            ← Qt setup
│   ├── quality.just                       ← quality tool installation
│   ├── secrets.just                       ← gitleaks installation
│   └── security.just                      ← security/formal-verification installation
└── test/
    ├── all.just                           ← aggregate dispatcher (test-all)
    ├── coverage.just                      ← coverage tests
    ├── demo.just                          ← demo conformance
    ├── dynamic.just                       ← dynamic test options
    ├── e2e.just                           ← E2E tests
    ├── integration.just                   ← integration tests
    ├── perf.just                          ← performance tests
    ├── system.just                        ← system tests
    └── unit.just                          ← unit tests
```

### Problems Identified

1. **Inconsistent setup/ file naming** — mix of `install-*` prefix (7 files) and bare names (4 files)
2. **Top-level misc files** — `vars.just`, `system.mem.just`, `test-import.just` sit at root alongside quality/security, obscuring structure
3. **File name → recipe prefix mismatch** in setup/ — `install-zig.just` has recipe `setup-zig:`, `qt.just` has `setup-qt-linux-arm:`, `developer.just` has `setup-linux-x86:` — recipe names use `setup-` prefix but file names use either `install-` or bare names
4. **`test-import.just`** has a single recipe called `test-include` (not `test-import`)
5. **`system.mem.just`** has recipes called `mem-*` (not `system.*`)
6. **`vars.just`** contains 22 recipe-like lines but is purely a variable definitions file — it should be clearly distinguished from recipe files

### Analysis of Setup/ Inconsistency

| File | Recipe Prefix | Purpose | Issue |
|------|--------------|---------|-------|
| install-build.just | `setup-build-*` | Build toolchain | File=install, recipe=setup |
| install-fd.just | `setup-fd-*` | Firedancer toolchain | File=install, recipe=setup |
| install-zig.just | `setup-zig` | Zig installer | File=install, recipe=setup |
| install-git.just | `setup-git` | Git hooks | File=install, recipe=setup |
| install-just.just | `setup-just` | Just installer | File=install, recipe=setup |
| install-env.just | `setup-env` | Full dev environment | File=install, recipe=setup |
| install-coverage.just | `setup-coverage-*` | Coverage toolchain | File=install, recipe=setup |
| install-build.just | `setup-build-*` | Build toolchain | File=install, recipe=setup |
| qt.just | `setup-qt-*` | Qt setup | File=qt, recipe=setup |
| quality.just | `setup-quality-*` | Quality tools | File=quality, recipe=setup |
| secrets.just | `setup-gitleaks-*` | Gitleaks | File=secrets, recipe=setup |
| security.just | `setup-security-*` | Security/FV tools | File=security, recipe=setup |
| setup/install-dev-env.just | `setup-dev-env-*` | Platform dev stacks | DONE — renamed ✓ |

**Pattern:** All recipe names use `setup-` prefix, and all file names use `install-*` prefix. DONE.

### Recipe Naming Consistency (Within Domains)

| Domain | Pattern | Status |
|--------|---------|--------|
| build/ | `build-{product}` (fd, tk, qt) + `build-{product}-{platform}` | ✓ Consistent |
| test/ | `test-{domain}-{product}` (unit, integration, e2e, etc.) + platform variants | ✓ Consistent |
| quality/ | `quality-{category}-{scope}` (format, lint, proto) | ✓ Consistent |
| security/ | `security-{category}-{scope}` (codeql, gitleaks, seccomp) | ✓ Consistent |
| setup/ | `setup-{tool}-{platform}` (install-*) or `setup-{tool}-{platform}` (bare names) | ✗ Inconsistent |

---

## Proposed Standards

### Standard 1: File Naming

**Rule:** File names should describe **what the file contains**, not the action it performs.

| Domain | Current | Proposed | Rationale |
|--------|---------|----------|-----------|
| setup/ | `install-zig.just` | `install-zig.just` | ✓ Keep `install-*` prefix — describes the tool being installed |
| setup/ | `install-git.just` | `install-git.just` | ✓ Keep |
| setup/ | `install-just.just` | `install-just.just` | ✓ Keep |
| setup/ | `install-env.just` | `install-env.just` | ✓ Keep |
| setup/ | `install-fd.just` | `install-fd.just` | ✓ Keep |
| setup/ | `install-coverage.just` | `install-coverage.just` | ✓ Keep |
| setup/ | `install-build.just` | `install-build.just` | ✓ Keep |
| setup/ | `qt.just` | `install-qt.just` | DONE — renamed ✓ |
| setup/ | `quality.just` | `install-quality.just` | DONE — renamed ✓ |
| setup/ | `secrets.just` | `install-secrets.just` | DONE — renamed ✓ |
| setup/ | `security.just` | `install-security.just` | DONE — renamed ✓ |
| setup/ | `developer.just` | `install-dev-env.just` | DONE — renamed ✓ |

**After:** All setup/ files use `install-*` prefix. DONE.

### Standard 2: Recipe Naming

**Rule:** Recipe names should use the `setup-` prefix for all setup recipes, matching the file's purpose.

| File | Current | Proposed |
|------|---------|----------|
| install-qt.just | `setup-qt-linux-x86:` | ✓ Keep (already uses `setup-`) |
| install-quality.just | `setup-quality-*` | ✓ Keep |
| install-secrets.just | `setup-gitleaks-*` | ✓ Keep (tool name, not setup) |
| install-security.just | `setup-security-*` | ✓ Keep |
| install-dev-env.just | `setup-dev-env-linux-x86:` | DONE — renamed ✓ |

**Rationale:** The `setup-` prefix is the action verb. The `install-*` file prefix describes the tool being set up. Together: `install-qt.just` contains `setup-qt-*` recipes. DONE.

### Standard 3: Top-Level Files

**Rule:** Top-level `just/` files should only contain domain-specific content (quality, security). Shared variables and system utilities belong in their own subdirectories.

| Current | Proposed | Rationale |
|---------|----------|-----------|
| `just/vars.just` | `just/vars.just` | ✓ Keep at root — shared variables are used by ALL recipes, including the root justfile imports them first |
| `just/quality.just` | `just/quality.just` | ✓ Keep at root — domain-specific, used in root justfile |
| `just/security.just` | `just/security.just` | ✓ Keep at root — domain-specific, used in root justfile |
| `just/system.mem.just` | `just/system/system.just` | DONE — moved ✓ |
| `just/test-import.just` | `just/test/test-include.just` | DONE — moved ✓ |

DONE. All top-level misc files resolved.

### Standard 4: Recipe → File Prefix Alignment

**Rule:** When a file contains a single domain, recipe names should share the file's prefix for clarity.

| File | Recipe Prefix | Alignment |
|------|--------------|-----------|
| build/build-fd.just | `build-fd-*` | ✓ File prefix matches recipe prefix |
| test/unit.just | `test-unit-*` | ✓ File prefix matches recipe prefix |
| setup/install-qt.just | `setup-qt-*` | Partial — file=`install-qt`, recipe=`setup-qt`. Both describe the same tool, different granularity. Acceptable. |
| setup/install-dev-env.just | `setup-dev-env-linux-x86:` | DONE — renamed ✓ |

### Standard 5: Platform Naming

**Rule:** Use the standardized platform identifiers defined in `contrib/platform.sh`.

| Identifier | Platform |
|------------|----------|
| `linux-x86` | Linux x86_64 |
| `linux-arm` | Linux ARM64 |
| `macos-x86` | macOS x86_64 |
| `macos-arm` | macOS ARM64 |
| `windows-x86` | Windows x86_64 |
| `windows-arm` | Windows ARM64 |

No version numbers (e.g., `macos-15-x86_64`), no `x86_64` suffix, no `aarch64`. Use the 2-part `os-arch` format everywhere.

---

## Proposed Final Directory Structure

```
just/
├── vars.just                              ← shared variables (root import, stays at top)
├── quality.just                           ← quality check recipes (root import, stays at top)
├── security.just                          ← security check recipes (root import, stays at top)
├── build/
│   ├── all.just                           ← build-all, clean-all
│   ├── build-fd.just                      ← Firedancer build
│   ├── build-qt.just                      ← Qt terminal build
│   └── build-tk.just                      ← Tickoni/Zig build
├── setup/
│   ├── install-build.just                 ← build toolchain
│   ├── install-coverage.just              ← coverage toolchain
│   ├── install-dev-env.just               ← platform dev stacks (renamed from developer.just)
│   ├── install-env.just                   ← full dev environment
│   ├── install-fd.just                    ← Firedancer toolchain
│   ├── install-git.just                   ← git hooks
│   ├── install-just.just                  ← just installer
│   ├── install-qt.just                    ← Qt setup (renamed from qt.just)
│   ├── install-quality.just               ← quality tools (renamed from quality.just)
│   ├── install-secrets.just               ← gitleaks (renamed from secrets.just)
│   ├── install-security.just              ← security/FV tools (renamed from security.just)
│   └── install-zig.just                   ← zig installer
├── system/
│   ├── system.just                        ← hugepages, kill-test (moved from system.mem.just)
│   └── test/                              ← test files moved here? OR keep in test/
│       └── test-include.just              ← test helper (moved from test-import.just)
└── test/
    ├── all.just                           ← test-all
    ├── coverage.just                      ← coverage tests
    ├── demo.just                          ← demo conformance
    ├── dynamic.just                       ← dynamic test options
    ├── e2e.just                           ← E2E tests
    ├── integration.just                   ← integration tests
    ├── perf.just                          ← performance tests
    ├── system.just                        ← system tests (renamed from system.just)
    └── unit.just                          ← unit tests
```

Wait — `test/` already has `system.just` (system tests) and `just/system.mem.just` has system utilities. These are different things:
- `test/system.just` → system tests (real LLM demo)
- `system.mem.just` → hugepages + kill-test (system utilities)

Let me reconsider the structure:

```
just/
├── vars.just                              ← shared variables
├── quality.just                           ← quality checks
├── security.just                          ← security checks
├── build/
│   ├── all.just
│   ├── build-fd.just
│   ├── build-qt.just
│   └── build-tk.just
├── setup/
│   ├── install-build.just
│   ├── install-coverage.just
│   ├── install-dev-env.just
│   ├── install-env.just
│   ├── install-fd.just
│   ├── install-git.just
│   ├── install-just.just
│   ├── install-qt.just
│   ├── install-quality.just
│   ├── install-secrets.just
│   ├── install-security.just
│   └── install-zig.just
├── system/
│   └── system.just                        ← hugepages, kill-test
└── test/
    ├── all.just
    ├── coverage.just
    ├── demo.just
    ├── dynamic.just
    ├── e2e.just
    ├── integration.just
    ├── perf.just
    ├── system.just                        ← system tests (real LLM)
    └── unit.just
    └── test-include.just                  ← test helper (renamed from test-import.just)
```

Actually, let me keep it simpler. The root files (quality.just, security.just) are fine. The question is really about setup/ and the misc top-level files. Here's the cleaner version:

```
just/
├── vars.just                              ← shared variables (unchanged, root import)
├── quality.just                           ← quality checks (unchanged, root import)
├── security.just                          ← security checks (unchanged, root import)
├── build/
│   ├── all.just
│   ├── build-fd.just
│   ├── build-qt.just
│   └── build-tk.just
├── setup/
│   ├── install-build.just
│   ├── install-coverage.just
│   ├── install-dev-env.just           ← renamed from developer.just
│   ├── install-env.just
│   ├── install-fd.just
│   ├── install-git.just
│   ├── install-just.just
│   ├── install-qt.just                ← renamed from qt.just
│   ├── install-quality.just           ← renamed from quality.just
│   ├── install-secrets.just           ← renamed from secrets.just
│   ├── install-security.just          ← renamed from security.just
│   └── install-zig.just
├── system/
│   └── system.just                    ← moved from system.mem.just
└── test/
    ├── all.just
    ├── coverage.just
    ├── demo.just
    ├── dynamic.just
    ├── e2e.just
    ├── integration.just
    ├── perf.just
    ├── system.just                    ← system tests (real LLM)
    └── unit.just
    └── test-include.just              ← renamed from test-import.just
```

---

## Implementation Plan

### Phase 1: Setup/ File Renaming (12 → 12)

Rename all bare-named setup files to use `install-*` prefix:

| From | To | Changes Required |
|------|----|------------------|
| `setup/qt.just` | `setup/install-qt.just` | DONE ✓ — no recipe changes |
| `setup/quality.just` | `setup/install-quality.just` | DONE ✓ — no recipe changes |
| `setup/secrets.just` | `setup/install-secrets.just` | DONE ✓ — no recipe changes |
| `setup/security.just` | `setup/install-security.just` | DONE ✓ — no recipe changes |
| `setup/developer.just` | `setup/install-dev-env.just` | DONE ✓ — recipes renamed `setup-linux-x86:` → `setup-dev-env-linux-x86:`, etc. |

### Phase 2: Top-Level File Moves/Renames

| From | To | Changes |
|------|----|---------|
| `just/test-import.just` | `just/test/test-include.just` | DONE ✓ — import updated, recipe path fixed (`../vars.just`) |
| `just/system.mem.just` | `just/system/system.just` | DONE ✓ — import updated |

### Phase 3: Update Root `justfile` Imports — DONE ✓

```justfile
# Setup — all use install-* prefix
import "just/setup/install-build.just"
import "just/setup/install-coverage.just"
import "just/setup/install-dev-env.just"        # was developer.just
import "just/setup/install-env.just"
import "just/setup/install-fd.just"
import "just/setup/install-git.just"
import "just/setup/install-just.just"
import "just/setup/install-qt.just"              # was qt.just
import "just/setup/install-quality.just"          # was quality.just
import "just/setup/install-secrets.just"          # was secrets.just
import "just/setup/install-security.just"         # was security.just
import "just/setup/install-zig.just"

# System (moved from root)
import "just/system/system.just"                  # was system.mem.just

# Test (updated path)
import "just/test/test-include.just"              # was test-import.just
```

### Phase 4: Update CI Workflow References

Search and update any CI workflow files that reference:
- `just setup-qt-*` → `just setup-qt-*` (no change, recipe name stays same)
- `just setup-quality-*` → `just setup-quality-*` (no change)
- `just setup-linux-x86` → `just setup-dev-env-linux-x86` (recipe renamed)
- `just test-import` → `just test-include` (recipe name unchanged, but file moved)
- `just mem-*` → `just mem-*` (no change)

### Phase 5: Verify

- `just --dump` parses without errors
- `just --list` shows all recipes
- `just tests-all --dry-run` resolves the full chain
- CI workflows pass
- No orphaned imports or references

---

## Naming Decision Rationale

### Why `install-*` for setup/ files?

- **Describes the content:** Each file installs a specific tool or set of tools. "install-zig" clearly means "this file contains recipes to install Zig".
- **Consistent with existing convention:** 7 of 13 setup files already use `install-*`. The other 6 should follow the same pattern.
- **Distinguishes from `setup-*` recipe prefix:** File names describe what the tool IS (`install-*`), recipe names describe the action (`setup-*`). This two-level naming is clear and unambiguous.
- **Scalable:** When adding a new installer (e.g., for CBMC, or any future tool), the convention is established.

### Why keep quality/security at root?

- They are domain-specific check recipes, not installers. They belong at the top level alongside vars.
- They are imported directly in the root justfile for the `quality-check-all` and `security-check-all` aggregation recipes.
- Moving them to subdirectories would add an unnecessary nesting level for files that are frequently referenced.

### Why move system.mem.just to just/system/system.just?

- "system.mem.just" conflates two concerns: "system" (kill-test) and "mem" (hugepages). The file actually contains both.
- `just/system/system.just` is a clean namespace: all system-level utilities live under `system/`.
- It removes the confusing `.mem.` infix from the filename.

### Why rename test-import.just to test/test-include.just?

- The recipe inside is called `test-include`, not `test-import`. The file name should match the recipe name.
- Moving it to `test/` makes sense — it's a test helper, not a top-level concern.

### Why rename developer.just to install-dev-env.just?

- "developer" is a role, not a tool or component. It doesn't describe what's in the file.
- The file contains dev environment setup recipes (platform dev stacks, test-prep).
- "dev-env" is descriptive and fits the `install-*` pattern.
