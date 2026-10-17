# Just Folder Refactoring — Folder Split and Aggregation Cleanup

**Date:** 2026-10-17
**Scope:** `just/quality.just`, `just/security.just`, root `justfile`
**Purpose:** Split monolithic quality.just and security.just into subdirectories; make root `tests-all` an aggregator-of-aggregations only.

---

## 1. Current State

```
just/
├── vars.just                              ← shared variables
├── quality.just                           ← format, lint, proto, yaml, spell, all ← MONOLITHIC
├── security.just                          ← codeql, gitleaks, seccomp, proof, sanitize, engine, all ← MONOLITHIC
├── build/                                 ← each category in its own file (good)
├── setup/                                 ← each install in its own file (good)
├── system/                                ← system utilities (good)
└── test/                                  ← each test domain in its own file (good)
```

**Problem:** `quality.just` and `security.just` are monolithic files at the root level. Every other domain (build, test, setup, system) follows the subdirectory pattern. Quality and security should too.

**Additional problem:** Root `tests-all` mixes categories — it calls `just build-all` (build), `just quality-*` (quality), `just security-*` (security), and `just test-all` (test). The root should only contain aggregator-of-aggregators, not individual domain calls.

---

## 2. Proposed Final Structure

```
just/
├── vars.just                              ← shared variables (root import, unchanged)
├── quality/
│   ├── all.just                           ← quality-check-all (aggregate of all categories)
│   ├── format.just                        ← quality-format-check/fix-fd/tk, *-all, *-linux-x86
│   ├── lint.just                          ← quality-lint-check-fd/tk, *-all, *-linux-x86
│   ├── proto.just                         ← quality-proto-check-fd/tk, *-all, *-linux-x86
│   ├── yaml.just                          ← quality-yaml-check-linux
│   └── spell.just                         ← quality-spell-check-linux
├── security/
│   ├── all.just                           ← security-check-all (aggregate of all categories)
│   ├── codeql.just                        ← security-codeql-check-fd/tk, *-all, *-linux-x86
│   ├── gitleaks.just                      ← security-gitleaks-check-fd/tk, *-all, *-linux-x86
│   ├── seccomp.just                       ← security-seccomp-check-fd/tk, *-all, *-linux-x86
│   ├── proof.just                         ← security-proof-check-fd/tk, *-all, *-linux-x86
│   ├── sanitize.just                      ← security-sanitize-check-fd/tk, *-all, *-linux-x86
│   └── engine.just                        ← security-engine-check-all, engine-check-changes, engine-check-orchestration
├── build/                                 ← unchanged
├── setup/                                 ← unchanged
├── system/                                ← unchanged
└── test/                                  ← unchanged
```

---

## 3. File-to-Recipe Mapping

### quality/ folder

| File | Recipes | Status |
|------|---------|--------|
| `format.just` | `quality-format-check-fd`, `quality-format-fix-fd`, `quality-format-check-tk`, `quality-format-fix-tk`, `*-linux-x86` aliases, `quality-format-check-all`, `quality-format-fix-all` | DONE |
| `lint.just` | `quality-lint-check-fd`, `quality-lint-check-tk`, `*-linux-x86` aliases, `quality-lint-check-all` | DONE |
| `proto.just` | `quality-proto-check-fd`, `quality-proto-check-tk`, `*-linux-x86` aliases, `quality-proto-check-all` | DONE |
| `yaml.just` | `quality-yaml-check-linux` | DONE |
| `spell.just` | `quality-spell-check-linux` | DONE |
| `all.just` | `quality-check-all` (calls all 5 category aggregates) | DONE |

### security/ folder

| File | Recipes | Status |
|------|---------|--------|
| `codeql.just` | `security-codeql-check-fd/tk`, `*-all`, `*-linux-x86` | DONE |
| `gitleaks.just` | `security-gitleaks-check-fd/tk`, `*-all`, `*-linux-x86` | DONE |
| `seccomp.just` | `security-seccomp-check-fd/tk`, `*-all`, `*-linux-x86` | DONE |
| `proof.just` | `security-proof-check-fd/tk`, `*-all`, `*-linux-x86` | DONE |
| `sanitize.just` | `security-sanitize-check-fd/tk`, `*-all`, `*-linux-x86` | DONE |
| `engine.just` | `security-engine-check-all`, `security-engine-check-changes`, `security-engine-check-orchestration`, `*-linux-x86` | DONE |
| `all.just` | `security-check-all` (calls all 6 category aggregates) | DONE |

---

## 4. Root `justfile` Changes

### Current (broken — too granular)

```justfile
tests-all:
    @just build-all
    @just quality-format-check-all
    @just quality-lint-check-tk
    @just quality-proto-check-all
    @just security-check-all
    @just security-engine-check-changes
    @just test-all
```

Problems:
- Mixes build, quality, security, and test in one recipe
- Calls individual category recipes (quality-format, quality-lint, etc.) instead of using aggregates
- Security calls both `security-check-all` and `security-engine-check-changes` separately (engine is already inside security-check-all)
- No aggregation-of-aggregations pattern

### Proposed (aggregator-of-aggregators only)

```justfile
# ── Imports ──────────────────────────────────────────────────────────────
import "just/vars.just"
import "just/setup/install-build.just"
import "just/setup/install-fd.just"
import "just/setup/install-coverage.just"
import "just/setup/install-zig.just"
import "just/setup/install-just.just"
import "just/setup/install-env.just"
import "just/setup/install-git.just"
import "just/setup/install-qt.just"
import "just/setup/install-quality.just"
import "just/setup/install-secrets.just"
import "just/setup/install-security.just"
import "just/setup/install-dev-env.just"

import "just/build/all.just"
import "just/test/all.just"

import "just/quality/all.just"
import "just/quality/format.just"
import "just/quality/lint.just"
import "just/quality/proto.just"
import "just/quality/yaml.just"
import "just/quality/spell.just"
import "just/security/all.just"
import "just/security/codeql.just"
import "just/security/gitleaks.just"
import "just/security/seccomp.just"
import "just/security/proof.just"
import "just/security/sanitize.just"
import "just/security/engine.just"
import "just/system/system.just"

# ── Aggregator-of-aggregators ───────────────────────────────────────────

tests-all:
    @just build-all
    @just test-all
    @just quality-check-all
    @just security-check-all
```

Key changes:
1. **Imports:** `just/quality.just` → `just/quality/all.just` + sub-files; `just/security.just` → `just/security/all.just` + sub-files. Other imports unchanged (build, test already use `all.just`).
2. **tests-all:** Now calls exactly 4 aggregators — `build-all`, `test-all`, `quality-check-all`, `security-check-all`. No individual category calls.
3. **Removed duplicate:** `security-engine-check-changes` was redundant since `security-check-all` already calls `security-engine-check-all` which calls `security-engine-check-changes`.
4. **Removed quality-lint-check-tk:** This was an inconsistent subset call. `quality-check-all` covers everything.
5. **Removed quality-proto-check-all:** Already covered by `quality-check-all`.
6. **Added sub-file imports:** Root justfile must import both `all.just` AND individual sub-files — justfile does NOT follow nested imports inside subfiles.

### Verified: DONE

All imports parse correctly, `just --dump` succeeds, `just --list` shows all recipes, and `just tests-all` resolves through the 4-aggregator chain.

---

## 5. Implementation Steps

### Phase 1: Create quality/ subdirectory

1. Create `just/quality/format.just` — extract format recipes from quality.just ✅ DONE
2. Create `just/quality/lint.just` — extract lint recipes from quality.just ✅ DONE
3. Create `just/quality/proto.just` — extract proto recipes from quality.just ✅ DONE
4. Create `just/quality/yaml.just` — extract yaml recipe ✅ DONE
5. Create `just/quality/spell.just` — extract spell recipe ✅ DONE
6. Create `just/quality/all.just` — `quality-check-all` calls all 5 categories ✅ DONE
7. Delete `just/quality.just` ✅ DONE

### Phase 2: Create security/ subdirectory

1. Create `just/security/codeql.just` — extract codeql recipes ✅ DONE
2. Create `just/security/gitleaks.just` — extract gitleaks recipes ✅ DONE
3. Create `just/security/seccomp.just` — extract seccomp recipes ✅ DONE
4. Create `just/security/proof.just` — extract proof recipes ✅ DONE
5. Create `just/security/sanitize.just` — extract sanitize recipes ✅ DONE
6. Create `just/security/engine.just` — extract engine recipes ✅ DONE
7. Create `just/security/all.just` — `security-check-all` calls all 6 categories ✅ DONE
8. Delete `just/security.just` ✅ DONE

### Phase 3: Update root justfile

1. Replace `import "just/quality.just"` with `import "just/quality/all.just"` + sub-files ✅ DONE
2. Replace `import "just/security.just"` with `import "just/security/all.just"` + sub-files ✅ DONE
3. Rewrite `tests-all` to use 4 aggregation-only calls ✅ DONE
4. Add sub-file imports to root justfile (justfile does NOT follow nested imports) ✅ DONE
5. Remove duplicate `security-engine-check-changes` and `quality-lint-check-tk` from `tests-all` ✅ DONE

### Phase 4: Verify

1. `just --dump` parses without errors
2. `just --list` shows all recipes unchanged
3. `just tests-all --dry-run` resolves the full chain through aggregators
4. Verify no orphaned imports or references
5. Run `just quality-check-all --dry-run` and `just security-check-all --dry-run` to confirm sub-aggregators work

---

## 6. Naming Convention Standard (for reference)

| Level | Pattern | Example |
|-------|---------|---------|
| Directory | Domain name (lowercase, no prefix) | `quality/`, `security/`, `build/`, `test/`, `setup/`, `system/` |
| Sub-file | Category name (lowercase, no prefix) | `format.just`, `lint.just`, `codeql.just`, `unit.just` |
| Aggregate file | `all.just` | Always named `all.just` for the top-level aggregator |
| Recipe — domain | `{domain}-{category}-{scope}` | `quality-format-check-fd`, `security-gitleaks-check-tk` |
| Recipe — platform alias | `{recipe}-{os}-{arch}` | `quality-format-check-fd-linux-x86` |
| Recipe — aggregate | `{domain}-{category}-all` | `quality-format-check-all`, `security-gitleaks-check-all` |
| Recipe — super-aggregate | `{domain}-check-all` or `{domain} all` | `quality-check-all`, `security-check-all`, `test-all`, `build-all` |

**Principle:** File names describe content; recipe names describe action+scope. The `all.just` file always sits at the top of each folder and serves as the aggregation entry point for its domain.
