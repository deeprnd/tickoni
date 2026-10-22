# Platform Variable Unification Plan

## Problem

Three parallel conventions for platform detection across the project:

| Convention | Set by | Consumed by |
|---|---|---|
| `TK_PLATFORM` | Install strategies | None (redundant) |
| `TK_OS` + `TK_ARCH` | `contrib/platform.sh` | orchestrator.py (build), justfile |
| `os` / `arch` | justfile backticks | justfile recipes |

This means:
- `contrib/platform.sh` exports all three (`TK_OS`, `TK_ARCH`, `TK_PLATFORM`)
- `just/vars.just` has `os`/`arch` (used by recipes) plus redundant `tk_os`/`tk_arch`/`tk_platform` aliases
- Setup orchestrator calls `platform.sh platform` via `detect_platform()` when no `--platform` arg is given
- Build orchestrator has `TK_OS`/`TK_ARCH` env fallback (lines 73-76), then calls `platform.sh platform` as last resort
- Install strategies (`build.py`, `openssl_build.py`) set `TK_PLATFORM` from the `platform_str` parameter

Inconsistency: `TK_PLATFORM` exists as a pre-joined convenience variable alongside decomposed `TK_OS`/`TK_ARCH`, but consumers either need OS, arch, or both — and each case is clearer with the component available.

## Standard

**Single source of truth: `contrib/platform.sh`**

**Standard convention: `TK_OS` + `TK_ARCH` (two separate env vars)**

**Delete: `TK_PLATFORM` entirely, `tk_platform()` function, `tk_platform` from justfile, `tk_os`/`tk_arch` justfile aliases.**

Rationale:
- `TK_OS` + `TK_ARCH` are already the canonical output from `platform.sh`
- Two vars are more flexible than a joined string (easier to compare OS-only, arch-only)
- Joined string can be derived on-demand: `"${TK_OS}-${TK_ARCH}"`
- `tk_platform` is a redundant alias; `os`/`arch` in justfile are sufficient
- No consumer needs a pre-joined `TK_PLATFORM` that can't be trivially constructed
- Removing `TK_PLATFORM` eliminates the anti-pattern of a "joined convenience variable" that sits alongside the decomposed vars

## Data Flow (Before)

```
justfile recipes (many pass --platform, some don't)
    → setup orchestrator: detect_platform(args.platform)
        → calls platform.sh platform if no --platform
        → returns "linux-x86"
        → Orchestrator.setup(platform_str)
            → strategy.execute(tool, config, platform_str, ...)
                → build.py: env['TK_PLATFORM'] = platform_str
                → openssl_build.py: env['TK_PLATFORM'] = platform_str
    → build orchestrator: platform_from_args(args)
        → --platform override OR TK_OS/TK_ARCH env OR platform.sh platform fallback
```

## Data Flow (After)

```
justfile: export TK_OS and TK_ARCH via vars.just
    → setup orchestrator: detect_platform(args.platform)
        → --platform override OR TK_OS/TK_ARCH env (no platform.sh call needed)
        → Orchestrator sets os.environ['TK_OS'] and os.environ['TK_ARCH'] from resolved platform
            → strategy.execute(tool, config, platform_str, ...)
                → build.py: env['TK_OS'] + env['TK_ARCH'] from os.environ
                → openssl_build.py: env['TK_OS'] + env['TK_ARCH'] from os.environ
    → build orchestrator: platform_from_args(args)
        → --platform override OR TK_OS/TK_ARCH env (remove platform.sh platform fallback)
```

Key improvement: no subprocess call to `platform.sh platform` anywhere in the runtime path. The values come from the justfile where they were already computed.

## Actual callers (search verified)

**`platform.sh platform` calls:**
- `contrib/setup/platform.py` — `detect_platform()` calls `bash contrib/platform.sh platform`
- `contrib/build/orchestrator.py` lines 79-82 — `platform_from_args()` calls `platform.sh platform`

**`platform.sh os` calls:**
- `just/vars.just` lines 22, 29 — `os` and `tk_os`

**`platform.sh arch` calls:**
- `just/vars.just` lines 25, 30 — `arch` and `tk_arch`

**CI workflows:** zero dependency — all use `${{ matrix.platform }}` and `--platform` args. No workflow calls `platform.sh`.

**Install strategies:**
- `contrib/setup/install/strategies/build.py` line 87 — sets `env['TK_PLATFORM'] = platform_str`
- `contrib/setup/install/strategies/openssl_build.py` line 131 — sets `env['TK_PLATFORM'] = platform_str`

## Changes

### 0. No justfile aliases needed
Justfile doesn't support variable interpolation in assignments (`{{ var }}` only works in recipe bodies). The `TK_OS` and `TK_ARCH` env vars are set entirely by the orchestrator's `resolve_platform()` function, which splits the resolved platform string and writes to `os.environ` before calling strategies. The justfile only exports `os` and `arch` (which subprocess calls already inherit via `export`).

### 1. `contrib/platform.sh`
- Keep exporting `TK_OS`, `TK_ARCH` (already done)
- Remove `TK_PLATFORM` assignment and echo (line 158, 161)
- Remove `tk_platform()` function (lines 115-117)
- Remove `tk_platform` from the standalone `case` dispatch (line 167)
- Update header doc comment to remove `TK_PLATFORM` reference (line 13)

### 2. `just/vars.just`
- Add `export` to `os` and `arch` (lines 22, 25)
- Add `export TK_OS := `os`` and `export TK_ARCH := `arch`` aliases
- Remove `tk_os`, `tk_arch`, `tk_platform` lines (lines 29-31) — redundant aliases
- Remove or update the comment on lines 27-28 about "backward compatibility"

### 3. `contrib/setup/platform.py` — remove subprocess dependency
`platform.py` has 3 functions, but `detect_platform()` is the only one that calls `platform.sh`. Remove it entirely — its logic is trivial enough to live inline in the orchestrator.

Remove `detect_platform()` from `platform.py`. Replace its caller in `contrib/setup/orchestrator.py` with an inline function:
```python
def resolve_platform(args_platform):
    if args_platform:
        return args_platform
    tk_os = os.environ.get("TK_OS", "")
    tk_arch = os.environ.get("TK_ARCH", "")
    if tk_os and tk_arch:
        return f"{tk_os}-{tk_arch}"
    return "linux-x86"  # safe default
```

`platform.py` then becomes a pure Python utility module:
- `matches_platform(tool, platform_key)` — unchanged, pure Python
- `get_platform_from_string(platform_str)` — unchanged, pure Python
- `detect_platform()` — removed (moved inline into orchestrator)

### 4. `contrib/build/orchestrator.py`
- Remove `platform.sh platform` subprocess fallback in `platform_from_args()` (lines 78-84)
- Keep the `--platform` override (lines 70-71) and `TK_OS`/`TK_ARCH` env fallback (lines 73-76)
- Fallback defaults to `"linux-x86"` if neither env vars nor `--platform` are set

### 5. `contrib/setup/install/strategies/build.py`
- Change `env['TK_PLATFORM'] = platform_str` to:
  ```python
  env['TK_OS'] = os.environ.get("TK_OS", "")
  env['TK_ARCH'] = os.environ.get("TK_ARCH", "")
  ```
- These are set by the setup orchestrator before calling `strategy.execute()`

### 6. `contrib/setup/install/strategies/openssl_build.py`
- Change `env['TK_PLATFORM'] = platform_str` to:
  ```python
  env['TK_OS'] = os.environ.get("TK_OS", "")
  env['TK_ARCH'] = os.environ.get("TK_ARCH", "")
  ```
- Keep the `platform_str` check for `windows-arm`/`windows-x86` (line 132-135) — used for `FD_WINDOWS_ARCH`

### 7. `contrib/setup/orchestrator.py`
- In `Orchestrator._install_tool()` or `Orchestrator.setup()`: after resolving `platform_str` from `detect_platform()`, set `os.environ['TK_OS']` and `os.environ['TK_ARCH']` before calling `strategy.execute()`:
  ```python
  tk_os, tk_arch = get_platform_from_string(platform_str)
  os.environ['TK_OS'] = tk_os
  os.environ['TK_ARCH'] = tk_arch
  ```
- The `get_platform_from_string()` function already exists and splits "linux-x86" into ("linux", "x86")

## Files touched: 7

| File | Changes |
|---|---|
| `just/vars.just` | Add `export`, add `TK_OS`/`TK_ARCH` aliases, remove `tk_os`/`tk_arch`/`tk_platform` |
| `platform.sh` | Remove `tk_platform()`, `TK_PLATFORM`, `platform` case arg |
| `platform.py` | `detect_platform()` reads from env instead of `platform.sh platform` |
| `orchestrator.py (build)` | Remove `platform.sh platform` fallback |
| `orchestrator.py (setup)` | Set `os.environ['TK_OS']` and `TK_ARCH` before calling strategies |
| `build.py` | Read `TK_OS`/`TK_ARCH` from env |
| `openssl_build.py` | Read `TK_OS`/`TK_ARCH` from env |

## Verification

1. `bash contrib/platform.sh os` → linux, `bash contrib/platform.sh arch` → x86, `bash contrib/platform.sh platform` → fails
2. `just build-fd-linux-x86-libs` — builds without platform.sh calls
3. `just setup-fd-linux-x86` — setup orchestrator reads from env
4. `just test-unit-all` — no justfile breakage
5. Verify `TK_OS` and `TK_ARCH` are in env during any just recipe execution

## Risk

- Doc references (V2.10.S1 audit, v2.10-s1 story, proposals) document `platform.sh platform` as part of the feature surface — informational only
- The `export TK_OS := os` syntax in justfile passes the just variable as a shell string; verify it resolves to the computed value not the backtick expression
- Minimal change surface: 7 files, no new dependencies
