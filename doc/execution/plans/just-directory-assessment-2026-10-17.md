# Just Directory Assessment

**Date:** 2026-10-17
**Scope:** All files under `just/` and root `justfile`
**Purpose:** Evaluate naming consistency, aggregation correctness, reference integrity, and anti-patterns

---

## 1. File Inventory

### Root `justfile` (60 lines)
- 12 includes for setup files
- 4 includes for build files
- 8 includes for test files
- 1 each for quality, security, system.mem
- 4 root recipes: `default`, `help`, `tests-all`, `dynamic-test-opts`

### `just/` Directory Structure
```
just/
├── vars.just                              # Variables (python, os, arch, platform, fd dirs, zig cache, cpu)
├── common.just                            # ⚠️ ORPHAN — not included, but contains 64 duplicate recipes
├── quality.just                           # Format, lint, proto, yaml, spell, all
├── security.just                          # CodeQL, gitleaks, seccomp, proof, sanitize, engine, all
├── system.mem.just                        # Hugepages (mem-*, mem-query, kill-test)
├── build/
│   ├── all.just                           # build-all, clean-all
│   ├── build-fd.just                      # Firedancer build (dispatcher + platforms)
│   ├── build-qt.just                      # Qt terminal build (dispatcher + platforms)
│   └── build-tk.just                      # Tickoni/Zig build (dispatcher + platforms)
├── setup/
│   ├── install-build.just                 # Build toolchain (gcc/clang/macos/windows)
│   ├── install-fd.just                    # Firedancer toolchain + deps (gcc/clang/macos/windows)
│   ├── install-coverage.just              # Coverage toolchain (clang/macos)
│   ├── install-zig.just                   # Zig installer
│   ├── install-env.just                   # Full dev environment (setup-env + setup-git)
│   ├── install-git.just                   # Git hooks setup
│   ├── dev-setup.just                     # Platform dev stacks (linux/macos/windows)
│   ├── developer.just                     # ⚠️ DUPLICATE — duplicates dev-setup.just + setup-env
│   ├── qt.just                            # Qt setup
│   ├── quality.just                       # Quality setup
│   ├── secrets.just                       # Gitleaks setup
│   └── security.just                      # Security setup
└── test/
    ├── all.just                           # test-all (aggregate)
    ├── unit.just                          # Unit tests (tk/fd dispatchers, gen-audit-fixtures)
    ├── integration.just                   # Integration tests (tk/fd dispatchers)
    ├── demo.just                          # Demo conformance (test/export/compare)
    ├── coverage.just                      # Coverage tests (cov-fd, cov-tk)
    ├── e2e.just                           # E2E tests (no-op placeholders)
    ├── system.just                        # System tests (real LLM demo, infra helpers)
    └── perf.just                          # Performance tests (Linux-only CPU placement)
```

**Total files:** 28 (29 including common.just)
**Total recipe definitions:** 236 across all just files (including common.just)

---

## 2. CRITICAL BUG: Missing `justfile_dir` Definition

### Severity: HIGH

`justfile_dir` is referenced in 4 places but **never defined** in the included files:

| File | Line | Reference |
|------|------|-----------|
| `just/test/perf.just` | 7, 12, 28, 37 | `{{ justfile_dir }}/contrib/...` |
| `just/security.just` | 100 | `justfile_directory()` (built-in just function) |

The definition exists only in `just/common.just`:
```just
justfile_dir := `git rev-parse --show-toplevel`
```

But `common.just` is **not included** in the root justfile.

**Impact:** Any recipe in `perf.just` that uses `{{ justfile_dir }}` will fail with "undefined variable" error at runtime.

**Fix:** Add `justfile_dir := \`git rev-parse --show-toplevel\`` to `vars.just`.

---

## 3. ORPHANED FILE: `common.just`

### Severity: MEDIUM

`just/common.just` contains **64 recipe definitions** that are **never included** in the root justfile:
- All platform setup recipes (`setup-build-*`, `setup-fd-*`, `setup-qt-*`, `setup-coverage-*`, `setup-gitleaks-*`, `setup-security-*`, `setup-quality-*`, `setup-zig`)
- Platform dev stacks (`setup-linux-*`, `setup-macos-*`, `setup-windows-*`)
- System test helpers (`test-prep-linux-x86`, `mem-*`, `kill-test`)
- Legacy `tests-all`, `test-all` (now superseded by the ones in included files)

**All 64 recipes are duplicated** in the split files under `just/setup/` and `just/system.mem.just`.

**Recommendation:** Delete `common.just`. It serves no purpose and its recipes are redundant.

---

## 4. DUPLICATE SETUP FILES: `dev-setup.just` vs `developer.just`

### Severity: HIGH

Both files are included in the root justfile and define overlapping recipes:

| Recipe | `dev-setup.just` | `developer.just` | Notes |
|--------|------------------|-------------------|-------|
| `setup-linux-x86` | ✓ | ✓ | Identical body |
| `setup-linux-arm` | ✓ | ✓ | Identical alias |
| `setup-macos-x86` | ✓ | ✓ | Identical body |
| `setup-macos-arm` | ✓ | ✓ | Identical alias |
| `setup-windows-x86` | ✓ | ✓ | Identical body |
| `setup-windows-arm` | ✓ | ✓ | Identical body |
| `setup-env` | | ✓ | Only in `developer.just` |
| `setup-git` | | ✓ | Only in `developer.just` |
| `test-prep-linux-x86` | | ✓ | Only in `developer.just` |

**Impact:** `just` will error with "recipe already defined" when both files are included.

**Fix:** Delete `dev-setup.just` (or `developer.just`) and consolidate into one. The `setup-env` and `setup-git` recipes should stay in `install-env.just` where they belong.

---

## 5. DUPLICATE `setup-env` ACROSS THREE FILES

### Severity: HIGH

`setup-env` is defined in:
1. `common.just` (not included, so no runtime impact)
2. `developer.just` (included)
3. `install-env.just` (included)

This means `setup-env` will error on include because it's defined twice.

**Fix:** Keep `setup-env` only in `install-env.just`. Delete from `developer.just` (which should also be deleted per finding #4).

---

## 6. NAMING INCONSISTENCIES

### 6.1 Platform Naming

Inconsistent use of platform identifiers:

| Pattern | Used in | Recommendation |
|---------|---------|----------------|
| `linux-x86` | Most files | ✓ Preferred |
| `linux-x86_64` | `demo.just` (export-*) | Inconsistent — use `linux-x86` |
| `macos-15-x86_64` | `demo.just` | Version-prefixed — fine for CI but inconsistent |
| `macos-26-x86_64` | `demo.just` | Same concern |
| `macos-arm` | Most files | ✓ Preferred |
| `windows-arm` | Most files | ✓ Preferred (internally maps to arm64) |

**Recommendation:** Standardize on `linux-x86`, `linux-arm`, `macos-x86`, `macos-arm`, `windows-x86`, `windows-arm`. Update `demo.just` export targets.

### 6.2 Recipe Naming Patterns

Three naming conventions coexist:

| Pattern | Example | Files |
|---------|---------|-------|
| `test-{domain}-{product}` | `test-unit-tk`, `test-unit-fd` | `test/*.just` |
| `test-{product}-{domain}` | `test-demo-tk` | `test/demo.just` |
| `test-{domain}-{product}-{platform}` | `test-unit-tk-linux-x86` | `test/*.just` |

**Recommendation:** Standardize on `test-{domain}-{product}` (e.g., `test-unit-tk`), then `test-{domain}-{product}-{platform}` for platform-specific variants. `test-demo-tk` should become `test-demo-tk` (already correct, but `export-demo-conformance-*` should follow the same pattern).

### 6.3 Quality/Security Naming

Quality and security files use consistent patterns:
- `quality-{category}-{scope}` → `quality-format-check-fd`, `quality-lint-check-tk`
- `security-{category}-{scope}` → `security-gitleaks-check-fd`, `security-seccomp-check-tk`
- `*-linux-x86` aliases for backward compatibility
- `*-all` aggregate dispatchers

**Assessment:** ✓ Consistent and follows industry standard patterns.

---

## 7. AGGREGATION CORRECTNESS

### 7.1 Build Aggregation

| Recipe | Correct | Notes |
|--------|---------|-------|
| `build-all` | ✓ | Delegates to `build-fd`, `build-tk`, `build-qt` |
| `clean-all` | ✓ | Removes build directories |

### 7.2 Test Aggregation

| Recipe | Correct | Notes |
|--------|---------|-------|
| `test-all` | ✓ | Calls `test-unit-all`, `test-integration-all`, `test-cov-all`, `test-system-all`, `test-e2e-all` |
| `test-unit-all` | ✓ | Calls `test-unit-tk`, `test-unit-fd` |
| `test-integration-all` | ✓ | Calls `test-integration-fd`, `test-integration-tk` |
| `test-cov-all` | ✓ | Calls `test-cov-fd`, `test-cov-tk` |
| `test-system-all` | ✓ | Calls `test-system-tk`, `test-system-fd` |
| `test-e2e-all` | ✓ | Calls `test-e2e-fd`, `test-e2e-tk` |

### 7.3 Quality/Security Aggregation

| Recipe | Correct | Notes |
|--------|---------|-------|
| `quality-check-all` | ✓ | Calls format, lint, proto, yaml, spell |
| `security-check-all` | ✓ | Calls engine, codeql, gitleaks, seccomp, proof, sanitize |

### 7.4 `tests-all` (Root)

| Recipe | Correct | Notes |
|--------|---------|-------|
| `tests-all` | ✓ | Calls build-all, quality-format-check-all, quality-lint-check-tk, quality-proto-check-all, security-check-all, security-engine-check-changes, test-all |

**Assessment:** ✓ All aggregation chains are logically correct and complete.

---

## 8. REFERENCE INTEGRITY

### 8.1 Variable Usage

| Variable | Defined in | Used by | Correct |
|----------|-----------|---------|---------|
| `python` | `vars.just` | All setup/build/test files | ✓ |
| `make` | `vars.just` | `unit.just` | ✓ |
| `os` / `arch` | `vars.just` | Dispatchers in `build-fd.just`, `build-tk.just`, `unit.just`, `system.just`, `system.mem.just` | ✓ |
| `cpu_count` | `vars.just` | `build-fd.just`, `unit.just`, `demo.just` | ✓ |
| `ZIG_CACHE` / `ZIG_GLOBAL_CACHE` | `vars.just` | `unit.just`, `integration.just`, `demo.just`, `perf.just` | ✓ |
| `ZIG_PREFIX` | `vars.just` | `perf.just` | ✓ |
| `fd_tickoni_lib` | `vars.just` | `unit.just`, `integration.just`, `build-tk.just`, `perf.just` | ✓ |
| `justfile_dir` | **MISSING** | `perf.just`, `security.just` | ✗ CRITICAL |

### 8.2 Script References

All scripts referenced exist and are correctly pathed:
- `contrib/setup/orchestrator.py` — ✓ (setup files)
- `contrib/build/orchestrator.py` — ✓ (build files)
- `contrib/test/run_live_investment_demo.sh` — ✓
- `contrib/test/run_live_investment_demo_win.sh` — ✓
- `contrib/test/infra/dynamic_test_opts.py` — ✓ (root justfile)
- `contrib/tool/readme/run-badged-command.py` — ✓ (test files)
- `contrib/quality/quality.sh` — ✓ (quality.just)
- `contrib/security/security.sh` — ✓ (security.just)
- `contrib/quality/engine/engine_check_changes.py` — ✓
- `contrib/quality/engine/linter.py` — ✓

### 8.3 `just` Subcommand References

All `just {recipe}` calls within recipes resolve to valid targets:
- `build-all` → `build-fd`, `build-tk`, `build-qt` ✓
- `test-unit-all` → `test-unit-tk`, `test-unit-fd` ✓
- `test-integration-all` → `test-integration-fd`, `test-integration-tk` ✓
- `test-cov-all` → `test-cov-fd`, `test-cov-tk` ✓
- `test-system-all` → `test-system-tk`, `test-system-fd` ✓
- `test-e2e-all` → `test-e2e-fd`, `test-e2e-tk` ✓
- `quality-format-check-all` → `quality-format-check-fd`, `quality-format-check-tk` ✓
- `security-check-all` → engine, codeql, gitleaks, seccomp, proof, sanitize ✓

**Assessment:** ✓ All recipe references are valid and resolvable.

---

## 9. ANTI-PATTERNS

### 9.1 Bash Shebangs in Just Recipes (LOW)

Several recipes include `#!/usr/bin/env bash` as a comment:
```just
build-fd:
    #!/usr/bin/env bash
    set -euo pipefail
```

This is not a bash script — it's a just recipe. The shebang line is harmless (just ignores comments) but misleading. It suggests the recipe is a standalone shell script when it's actually a just recipe body.

**Recommendation:** Remove shebang comments. Keep `set -euo pipefail` as a comment or as a recipe line without the shebang prefix.

### 9.2 Mixed `@` Prefix Usage (LOW)

Some recipes use `@` (silent execution), others don't:
- `test-cov-fd`: `@true`
- `test-e2e-fd`: `@true`
- `test-unit-fd-linux-x86-gcc`: no `@` (verbose)

**Recommendation:** Standardize on `@` for all recipes that invoke sub-recipes (`just {recipe}`) to avoid noisy output. Keep verbose for recipes that run the actual work.

### 9.3 Windows Platform Alias Naming (LOW)

`build-qt-windows-x86: build-qt-linux-x86` — Windows builds delegate to Linux recipes. This works because the Qt build recipe itself uses `git rev-parse --show-toplevel` and cross-platform cmake, but the naming is confusing.

**Recommendation:** Add a comment explaining the cross-platform delegation, or rename to `build-qt-windows-x86: # cross-platform via cmake`.

### 9.4 Duplicate `test-perf-fd` and `test-perf-qt` No-ops (INFO)

Both are `@true` with no implementation. If they're intentional placeholders, add a comment explaining why they exist.

### 9.5 Inconsistent Dispatcher Patterns (MEDIUM)

Some dispatchers use `exec just {recipe}` (bash exec, replaces shell):
- `build-fd` dispatcher: `exec just build-fd-linux-x86-gcc`
- `build-tk` dispatcher: `exec just build-tk-linux-x86`
- `test-unit-fd` dispatcher: `exec just test-unit-fd-linux-x86-gcc`

Others use `@just {recipe}` (just native):
- `test-all`: `@just test-unit-all`
- `tests-all`: `@just build-all`

**Recommendation:** Use `@just {recipe}` (native) for all dispatchers. The `exec` pattern is only needed when the dispatcher needs bash-specific logic (e.g., `set -euo pipefail` before the exec). For simple routing, `@just {recipe}` is cleaner.

---

## 10. RECOMMENDATIONS SUMMARY

| Priority | Issue | Action |
|----------|-------|--------|
| **CRITICAL** | Missing `justfile_dir` definition | Add to `vars.just` |
| **HIGH** | `dev-setup.just` duplicates `developer.just` | Delete one (prefer `dev-setup.just`) |
| **HIGH** | `setup-env` defined 3x (2x included) | Keep only in `install-env.just` |
| **MEDIUM** | `common.just` is orphaned | Delete |
| **MEDIUM** | Inconsistent dispatcher patterns | Standardize on `@just {recipe}` |
| **LOW** | Bash shebang comments in recipes | Remove shebang lines |
| **LOW** | Platform naming in `demo.just` export targets | Use `linux-x86` instead of `linux-x86_64` |
| **INFO** | No-op `test-perf-fd`/`test-perf-qt` | Add explanatory comments |

---

## 11. COHERENCE ASSESSMENT

### What's Good
- Clear separation of concerns: setup, build, test, quality, security, system
- Consistent naming in quality/security files
- Proper aggregation chain from `tests-all` → `test-all` → lane-specific dispatchers
- Platform alias pattern (`recipe-arm: recipe-x86`) is used consistently
- Python variable abstraction (`{{ python }}`) is consistently applied
- Zig cache variables are standardized
- `justfile_directory()` (built-in just function) usage in security.just is correct

### What's Broken
- `justfile_dir` is missing → perf.just will fail at runtime
- Duplicate recipe definitions will cause just parse errors
- `common.just` is a dead file with 64 duplicate recipes
- Three-way naming inconsistency between setup files

### Verdict
**The directory structure is logically sound but has implementation bugs.** The categorization (setup/build/test/quality/security/system) follows industry standards. The aggregation chains are correct. The naming conventions are mostly consistent within domains. However, the missing `justfile_dir` definition and duplicate recipe definitions are blocking issues that must be fixed before the justfile will parse correctly.

### Industry Standard Compliance

| Criteria | Status | Notes |
|----------|--------|-------|
| Single responsibility per file | ⚠️ | `dev-setup.just` vs `developer.just` overlap |
| Clear aggregation hierarchy | ✓ | `tests-all` → `test-all` → lane dispatchers |
| Consistent naming | ⚠️ | Mixed patterns in test files |
| No dead code | ✗ | `common.just` is dead |
| Variable abstraction | ✓ | `{{ python }}`, `{{ os }}`, `{{ arch }}` |
| Platform abstraction | ✓ | Dispatcher pattern with `case` statement |
| Error handling | ✓ | `set -euo pipefail` in bash recipes |
| Idempotent setup | ✓ | Orchestrator.py handles idempotency |
