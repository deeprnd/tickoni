# Platform Variable Unification Plan

## Problem

Three parallel conventions for platform detection across the project:

| Convention | Set by | Consumed by |
|---|---|---|
| `TK_PLATFORM` | `just/test/unit.just`, install strategies | test runner, OpenSSL helper |
| `TK_OS` + `TK_ARCH` | `contrib/platform.sh` | orchestrator.py |
| `os` / `arch` / `tk_platform` | justfile backticks | justfile recipes |

This means:
- `contrib/platform.sh` exports all three (`TK_OS`, `TK_ARCH`, `TK_PLATFORM`)
- `just/common.just` reads all three via backticks (redundant: `os`/`arch` already sufficient)
- `orchestrator.py` reads `TK_OS` + `TK_ARCH` from env, joins them
- `test_run_test_series.py` reads `TK_PLATFORM` from env (one variable only)
- `run_test_series.sh` calls `contrib/platform.sh os` directly (avoids env entirely)
- Install strategies (`build.py`, `openssl_build.py`) set `TK_PLATFORM` as env var
- `kcov.sh` reads `TK_ARCH` from env

Inconsistency: some consumers expect a joined string (`TK_PLATFORM`), some expect two parts (`TK_OS`/`TK_ARCH`), some bypass env entirely and call `platform.sh`.

## Standard

**Single source of truth: `contrib/platform.sh`**

**Standard convention: `TK_OS` + `TK_ARCH` (two separate env vars)**

**Delete: `TK_PLATFORM` entirely, `tk_platform()` function, `{{ tk_platform }}` in justfile, `tk_os`/`tk_arch` justfile aliases.**

Rationale:
- `TK_OS` + `TK_ARCH` are already the canonical output from `platform.sh`
- Orchestrator already uses this pattern (lines 73-76)
- Two vars are more flexible than a joined string (easier to compare OS-only, arch-only)
- Joined string can be derived on-demand: `"${TK_OS}-${TK_ARCH}"`
- `tk_platform` is a redundant alias; `os`/`arch` in justfile are sufficient
- No consumer needs a pre-joined `TK_PLATFORM` that can't be trivially constructed
- Removing `TK_PLATFORM` eliminates the anti-pattern of a "joined convenience variable" that sits alongside the decomposed vars — consumers either need OS, arch, or both, and each case is clearer with the component available

## Actual callers (search verified)

**`platform.sh platform`:**
- `contrib/setup/platform.py` line 30 — `detect_platform()`
- `contrib/build/orchestrator.py` lines 79-82 — `platform_from_args()`

**`platform.sh os`:**
- `contrib/test/run_test_series.sh` line 13 — my fix
- `just/common.just` lines 99, 106 — `os` and `tk_os`

**`platform.sh arch`:**
- `just/common.just` lines 102, 107 — `arch` and `tk_arch`

**CI workflows:** zero dependency — all use `${{ matrix.platform }}` and `--platform` args. No workflow calls `platform.sh`.

## Changes

### 0. Migrate callers of `platform.sh platform` before deleting `tk_platform()`
Two Python files call `platform.sh platform` directly — must be migrated first:

- `contrib/setup/platform.py` line 30: `detect_platform()` calls `bash contrib/platform.sh platform`
  → Migrate to read `TK_OS` + `TK_ARCH` from env, join as `"${TK_OS}-${TK_ARCH}"`
- `contrib/build/orchestrator.py` lines 79-82: `platform_from_args()` calls `platform.sh platform`
  → Already has `TK_OS`/`TK_ARCH` fallback (lines 73-76); just remove the `platform.sh platform` fallback

### 1. `contrib/platform.sh`
- Keep exporting `TK_OS`, `TK_ARCH` (already done)
- Remove `TK_PLATFORM` assignment and echo (line 158, 161)
- Remove `tk_platform()` function (lines 115-117)
- Remove `tk_platform` from the standalone `case` dispatch (line 167)
- Update header doc comment to remove `TK_PLATFORM` reference (line 13)

### 2. `just/common.just`
- Keep `os` and `arch` (already used by many recipes)
- Remove `tk_os`, `tk_arch`, `tk_platform` lines (lines 106-108) — redundant aliases

### 3. `contrib/test/test_run_test_series.py`
- Change `os.environ["TK_PLATFORM"]` to join from `TK_OS` + `TK_ARCH`
- Or change `_bash_command` to accept `TK_OS` and check `platform_str.startswith("windows-")`

### 4. `just/test/unit.just`
- Change `TK_PLATFORM={{ tk_platform }}` to `TK_OS={{ os }} TK_ARCH={{ arch }}`

### 5. `contrib/setup/install/strategies/build.py`
- Change `env['TK_PLATFORM'] = platform_str` to:
  ```python
  env['TK_OS'] = platform_str.split('-')[0]
  env['TK_ARCH'] = platform_str.split('-')[1]
  ```

### 6. `contrib/setup/install/strategies/openssl_build.py`
- Same change as #5

### 7. `contrib/test/run_test_series.sh`
- Already calls `platform.sh` directly — no change needed

### 8. `contrib/setup/helpers/kcov.sh`
- Uses `TK_ARCH` from env — already follows the standard, no change

### 9. `contrib/build/orchestrator.py`
- Already uses `TK_OS` + `TK_ARCH` — no change needed (only change is removing `platform.sh platform` fallback in step 0)

## Verification

1. Run `just test-setup-run` on linux-x86 (current machine) — all 120 tests pass
2. Run `just test-unit-all` to ensure no justfile breakage
3. Run `just build-fd-linux-x86-libs` to ensure orchestrator still works
4. Verify `platform.sh` standalone invocation still works: `bash contrib/platform.sh os`, `bash contrib/platform.sh arch`
5. Verify `bash contrib/platform.sh platform` no longer works (removed)

## Risk

- Doc references (V2.10.S1 audit, v2.10-s1 story, README) document `platform.sh platform` as part of the feature surface — these are informational, not actionable. Consider updating if desired.
- Minimal change surface: 8 files touched (platform.py, orchestrator.py, platform.sh, common.just, test_run_test_series.py, unit.just, build.py, openssl_build.py)
