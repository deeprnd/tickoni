# Build/Test/Quality/Security Tooling Consolidation Plan

## Goal

Today, `just build-fd`, `just test-unit-fd`, `just test-unit-tk`, and `just test-integration-tk`
each independently re-implement "what OS/arch am I on", and CI wires around 11 `contrib/*`
scripts of uneven purpose. The macOS/Windows `test-unit-fd` gap fixed (adding a `Darwin` branch by hand) is exactly the failure mode this plan exists to stop: every new
platform lane requires a human to remember to update N separate `case "$(uname -s)"` blocks
scattered across `justfile` and `contrib/`, and it's easy to miss one.

This proposal turns six requirements into a concrete target design:

1. **One way in.** Every build/test/quality/security action is a `just` recipe. Nobody — human
   or CI — invokes `gcc`, `zig`, `gmake`, or a `contrib/*.sh` script directly.
2. **One naming grid.** `{command}[-{subcommand}]-{os}-{arch}[-{compiler}]`, e.g.
   `build-fd-linux-arm-gcc`, `test-unit-tk-macos-arm`. A bare `{command}` (no suffix) stays as
   the auto-detecting convenience form for local dev, exactly like `build-fd` already does.
3. **One place detects the platform.** A single script, reused by every `just` recipe and every
   `contrib/*.sh` script that currently reimplements `uname -s`/`uname -m` parsing.
4. **CI always calls the fully-qualified recipe.** No auto-detection inside CI — reproducibility
   over cleverness, which is already the stated intent of the existing `build-fd-*` recipes.
5. **Fewer scripts.** Merge or delete scripts that duplicate each other or nothing calls.
6. **One setup script per lane.** `just setup-{os}-{arch}[-{compiler}]` installs everything that
   lane's `build`/`test`/`quality`/`security` recipes need — zig, compiler, make, shellcheck,
   gitleaks, buf, llvm-cov, kcov, CBMC, pre-commit — so a new contributor or a new CI runner
   needs exactly one command before any other `just` recipe works.

---

## 1. Current-State Inventory

### 1.1 OS/arch detection is duplicated in (at least) 6 places

| Location | What it detects | How |
|---|---|---|
| `justfile:107-135` (`build-fd`) | OS (Linux/Darwin/MINGW\|MSYS\|CYGWIN), then arch on Darwin | `uname -s` / `uname -m`, inline `case` |
| `justfile:244-273` (`test-unit-fd`, patched this session) | Same, plus Darwin arch | inline `case`, duplicated from `build-fd` |
| `justfile:274-286` (`test-unit-tk`) | Windows-only branch | inline `case` |
| `justfile:311-323` (`test-integration-tk`) | Windows-only branch | inline `case` |
| `contrib/detect-windows-arch.sh` (32 lines) | Windows arch only, via `MSYSTEM_CARCH`/`PROCESSOR_ARCHITEW6432`/`PROCESSOR_ARCHITECTURE`/`uname -m` | standalone script, called 4x from `justfile` + once from `fd-build-windows.sh` |
| `contrib/zigw.sh:7-21` | Windows + Windows-ARM detection (different env vars than `detect-windows-arch.sh`) | reimplemented independently, does **not** call `detect-windows-arch.sh` |

Each of these encodes the OS/arch taxonomy slightly differently (`Darwin` vs `macOS` vs
`aarch64|arm64` vs `ARM64|arm64|AARCH64|aarch64`), and `zigw.sh` and `detect-windows-arch.sh`
independently detect "is this Windows ARM" using different environment variables. This is the
mechanism by which the macOS gap in `test-unit-fd` happened, and it will happen again the next
time a recipe needs OS-awareness and someone copies whichever `case` block is closest at hand.

### 1.2 `contrib/*.sh` and `contrib/*.py` script inventory

| Script | Lines | Purpose | Called by | Verdict |
|---|---|---|---|---|
| `install-zig.py` | 270 | Downloads official prebuilt Zig | `setup-public-gh-runner/action.yml` today; becomes the sole Zig installer called by every `setup-*` recipe (dev and CI alike) | **Keep** — this is now the *only* path, per D1 |
| `install-zig-bootstrap.py` | 314 | Source-builds Zig via `zig-bootstrap` | Documented in `ci.md` as a local-only path; no script or workflow calls it | **Delete** (D1) — a second, dev-only install path is exactly the divergence this plan removes. If the prebuilt-binary path (`install-zig.py`) ever breaks for a platform, the fix lands in that one script for everyone, not a parallel bootstrap-from-source escape hatch that only some contributors know about. `ci.md`'s "local developer machines may still use..." language is retired along with the script. |
| `fd-write-zig-link-manifests.sh` | 59 | Writes link manifests consumed by `build.zig` | `fd-build-lib.sh:111` | **Keep**, fold into `fd-tk-libs.sh` (see 3.3) |
| `fd-tk-libs.sh` | 191 | Single source of truth for FD lib source dirs (`FD_TK_LIB_SRCS` etc.) + `fd_build_fd()` | `fd-build-lib.sh`, `security.sh`, documented in `ci.md` | **Keep** — this is the good example of "one source of truth" already in the repo |
| `fd-build-windows.sh` | 73 | Windows FD lib build + `libuuid.a` stub | `justfile` (`build-fd-windows-x86/arm`), `fd-build-windows.ps1` | **Keep**, but stop calling `detect-windows-arch.sh` separately (see 3.1) |
| `fd-build-windows.ps1` | 12 | PowerShell shim that shells out to `fd-build-windows.sh` | nothing in-repo calls it (no workflow references `.ps1`) | **Delete** (D2) — confirmed orphaned, no external trigger; the project is self-contained |
| `fd-build-linux.sh` | 9 | Thin wrapper: `fd-build-lib.sh fd-tickoni-fd "$CC"` | `justfile:114` (`build-fd` Linux branch) | **Delete, inline into justfile** — 9 lines wrapping one call is exactly the kind of indirection this plan should remove |
| `fd-build-lib.sh` | 111 | Real workhorse: builds FD libs for a given `BUILDDIR`/`CC`/`MODE` | `justfile` (6 call sites), `fd-build-linux.sh`, `fd-build-windows.sh` | **Keep** — this is the right level of shared logic |
| `detect-windows-arch.sh` | 32 | Windows arch normalization | `justfile` (4x), `fd-build-windows.sh` | **Replace** with the new cross-platform `platform.sh` (below) |
| `ci-run-build-tk.sh` | 18 | Wraps `zigw.sh build`, adds a retry-with-diagnostics fallback | `.github/workflows/build-tk.yml` (7x) | **Keep** — genuine CI-only diagnostic behavior, correctly kept out of the local `build-tk` recipe |
| `zigw.sh` | 61 | Zig binary resolution (Windows-ARM x64-Zig workaround) + target-override injection | `justfile` (11x), `ci-run-build-tk.sh`, `contrib/test/run_cli_demo_tests.sh` | **Keep**, but delegate its OS/arch classification to `platform.sh` instead of reimplementing it |
| `quality.sh` | 154 | Format/lint dispatch | `justfile` (7x) | **Keep as-is** — no OS-detection duplication here, already well-scoped |
| `security.sh` | 120 | Security check dispatch | `justfile` (5x) | **Keep as-is** — same |

**Net effect of the script changes above:** 11 scripts → 8. Delete `fd-build-linux.sh` (inlined),
`detect-windows-arch.sh` (absorbed into `platform.sh`), `fd-build-windows.ps1` (orphaned, D2), and
`install-zig-bootstrap.py` (single Zig install path, D1); add one new script (`platform.sh`). The
bigger win is not script *count* but removing the 4 duplicated detection blocks from `justfile`
and the 2 independent reimplementations in `zigw.sh`/`detect-windows-arch.sh`, collapsing to 1,
and removing the dev-vs-CI install divergence entirely.

### 1.3 CI-side platform installs are also inline, not scripted

`.github/actions/setup-public-gh-runner/action.yml` (160 lines) already centralizes *most*
per-platform installs (Zig, gmake, gitleaks, kcov, Windows bootstrap) behind `if: runner.os ==
...` composite-action steps — this is the right idea, but it's YAML-only, so a developer cannot
run the same install locally. `.github/actions/deps/action.yml` separately handles Firedancer
system deps (`contrib/setup/helpers/deps.sh`) and duplicates its own `runner.os`/`runner.arch` branching for zstd
installation. There is no single command a new contributor or a fresh CI runner can invoke to
"install everything this platform needs."

---

## 2. Target Design

### 2.1 Principle 1 — one way in

No doc, script comment, or workflow step should tell a developer or CI to run `zig build ...`,
`gcc ...`, or `bash contrib/foo.sh` directly. `development.md` already states this ("Use
`justfile` recipes as the repo-facing command surface") — this plan makes it mechanically true
by removing the scripts that currently *require* direct invocation knowledge (e.g.
`fd-build-windows.sh`'s arch/compiler args are only documented in its own header comment, not in
`justfile`).

### 2.2 Principle 2 — the naming grid

```
{command}[-{subcommand}]-{os}-{arch}[-{compiler}]
```

- `os` ∈ `linux`, `macos`, `windows`
- `arch` ∈ `x86`, `arm`
- `compiler` — **only present where the repo actually validates more than one compiler on that
  platform.** Today that's Linux only (`gcc`, `clang`, and ARM's `gcc-14`). macOS and Windows
  build with `clang` exclusively, so `build-fd-macos-arm` does not need a `-clang` suffix any
  more than `build-fd-linux-x86-gcc`'s sibling needs a redundant `-gcc12` version suffix. This
  mirrors the existing `build-fd-gcc` / `build-fd-clang` / `build-fd-arm` (implicitly gcc-14)
  naming, just made positionally consistent.
- The **bare `{command}`** (`build-fd`, `test-unit-fd`, `test-unit-tk`, `test-integration-tk`,
  `build-tk`) stays as the auto-detecting dispatcher for local development — this is Principle 1
  in action (a developer should never need to know their own OS/arch/compiler triple to run
  `just build-fd`). It is a **pure router**: it computes `{os}-{arch}[-{compiler}]` once (via
  2.3) and execs the fully-qualified recipe. It contains no build logic of its own.

**Important scoping exception, not silently resolved:** `quality-*` and `security-*` recipes
(`quality-lint-check-fd`, `security-seccomp-check-fd`, `security-proof-check-fd`/CBMC,
`security-sanitize-check-fd`) are Linux/x86-only **by design**, not by omission —
`development.md` states "Firedancer only supports x86-64 Linux... other targets are not valid
for the Firedancer runtime because the code relies on x86-64 memory-ordering assumptions." These
recipes should **not** be forced into the `{os}-{arch}` grid; doing so would either (a) produce
meaningless recipes like `security-seccomp-check-fd-macos-arm`, or (b) require silently deciding
that seccomp/CBMC/sanitizers now run cross-platform, which is an architecture decision this plan
does not make. See Open Decision D3.

### 2.3 Principle 3 — one platform-detection script

New file: `contrib/platform.sh`. A sourceable bash library (not a script with subcommands spread
across callers) exposing:

```bash
tk_os()          # linux | macos | windows
tk_arch()        # x86 | arm
tk_platform()    # "$(tk_os)-$(tk_arch)", e.g. "macos-arm"
```

Detection logic consolidates, in one place, the union of what today's 3 independent
implementations (`build-fd`'s inline case, `detect-windows-arch.sh`, `zigw.sh`'s inline case)
each know:

- `uname -s` → `Linux` / `Darwin` / `MINGW*|MSYS*|CYGWIN*` → `linux`/`macos`/`windows`
- arch: `uname -m` (`arm64|aarch64` → `arm`, else `x86`), falling back on Windows to
  `MSYSTEM_CARCH` / `PROCESSOR_ARCHITEW6432` / `PROCESSOR_ARCHITECTURE` when `uname -m` is
  unreliable under MSYS (this is exactly what `detect-windows-arch.sh` does today — that logic
  moves here verbatim, not reinvented)

Every consumer switches to this one script:

- `justfile`: computed once as top-level `just` variables (backtick assignments run once per
  invocation, exactly like the existing `make := ...` line), then every dispatcher recipe becomes
  a one-liner instead of a repeated `case` block:
  ```just
  os   := `bash contrib/platform.sh os`
  arch := `bash contrib/platform.sh arch`

  build-fd:
      @just build-fd-{{os}}-{{arch}}
  ```
  This is the direct fix for "os detection should be in one place and reused across different
  just commands" — four separate `case "$(uname -s)"` blocks collapse to two `just` variables
  reused by every dispatcher recipe.
- `zigw.sh` calls `tk_os`/`tk_arch` instead of reimplementing Windows/ARM detection; keeps its
  own Zig-binary-path-discovery logic (that part isn't OS detection, it's Zig install-layout
  knowledge and stays local to `zigw.sh`).
- `fd-build-windows.sh` calls `platform.sh` instead of `detect-windows-arch.sh` directly.
- `detect-windows-arch.sh` is retired; its logic is absorbed into `platform.sh`'s arch detection.

### 2.4 Principle 4 — CI calls fully-qualified recipes only

This is already the stated intent for `build-fd-*` (`justfile:104-106`: "CI recipes below ...
are called directly with explicit values for reproducibility"). Extend the same rule to the
`test-*` and future `setup-*` families: every `run:` line in every workflow names a fully
qualified recipe (`just test-unit-tk-linux-x86`, never bare `just test-unit-tk`), so CI behavior
never depends on runner-detected OS/arch — only on which job matrix entry GitHub scheduled.

### 2.5 Principle 5 — script reduction (see 1.2 table)

Summary of concrete deletions/merges:
- Delete `fd-build-linux.sh` (9-line wrapper; inline its one call into `justfile`'s Linux
  dispatch branch, matching how `fd-build-lib.sh` is already called directly for gcc/clang/arm).
- Resolve `fd-build-windows.ps1` — confirm it's genuinely unused before deleting (D2).
- Delete `detect-windows-arch.sh` — absorbed into `platform.sh`.
- Add `contrib/platform.sh` (new, ~40 lines, replaces >100 lines of duplicated detection logic
  across 5 sites).

### 2.6 Principle 6 — one setup script per lane

New `just` recipes: `setup-linux-x86[-gcc|-clang]`, `setup-linux-arm[-gcc]`, `setup-macos-x86`,
`setup-macos-arm`, `setup-windows-x86`, `setup-windows-arm`, plus a bare `setup` dispatcher
(same auto-detect-and-route pattern as 2.2). Each installs, idempotently, everything that
platform's `build-*`/`test-*`/`quality-*`/`security-*` recipes need:

| Tool | Currently installed by | Moves to `setup-*` |
|---|---|---|
| Zig | `setup-public-gh-runner/action.yml` steps 61-89, via `install-zig.py` | Yes — `setup-*` calls `install-zig.py` itself; this is the **only** Zig install path, for CI and developers alike (D1) |
| `just` | `taiki-e/install-action@just` in the composite action | Out of scope by necessity — `just` has to exist before any `just setup-*` recipe can run. Per D4, this stays a one-line manual prerequisite documented in `doc/execution/build.md` ("install `just`"), not a scripted step and not a bootstrap script. Developers install it themselves; CI keeps `taiki-e/install-action@just` as the composite action's first step. |
| GNU make (macOS) | `setup-public-gh-runner/action.yml:47-53` (`brew install make`) | Yes |
| Firedancer compiler + system deps | `.github/actions/deps` (`contrib/setup/helpers/deps.sh`) | Yes — `setup-*` calls `deps.sh` the way `deps/action.yml` does today |
| gitleaks | `setup-public-gh-runner/action.yml:131-151` | Yes |
| kcov | `setup-public-gh-runner/action.yml:111-129` | Yes, for lanes that run coverage |
| shellcheck, pre-commit, buf, llvm-18 tools | Installed ad hoc across `quality.yml`/`security.yml` workflow steps (not shown in the composite action) | Yes — consolidate into the matching `setup-linux-x86-*` |
| Windows bootstrap tools (LLVM, gitleaks, gmake) | `setup-windows.ps1` | Yes — `setup-windows-*` calls this |

CI's `setup-public-gh-runner` composite action becomes a **thin wrapper** that calls `just
setup-{os}-{arch}[-{compiler}]` instead of containing 100+ lines of inline `if: runner.os ==`
branching. This is what makes "developer" and "CI" installs provably identical: they run the
literal same command.

---

## 3. Target Recipe Matrix (representative, not exhaustive)

| Family | Bare dispatcher (local) | Fully-qualified (CI) |
|---|---|---|
| Build FD | `build-fd` | `build-fd-linux-x86-gcc`, `build-fd-linux-x86-clang`, `build-fd-linux-arm-gcc`, `build-fd-macos-x86`, `build-fd-macos-arm`, `build-fd-windows-x86`, `build-fd-windows-arm` |
| Build TK | `build-tk` | `build-tk-linux-x86`, `build-tk-macos-x86`, `build-tk-macos-arm`, `build-tk-windows-x86`, `build-tk-windows-arm` |
| Test unit FD (native C unit-test binaries) | `test-unit-fd` | `test-unit-fd-linux-x86-gcc`, `test-unit-fd-macos-x86`, `test-unit-fd-macos-arm`, `test-unit-fd-windows-x86`, `test-unit-fd-windows-arm` (D3) |
| Test unit TK | `test-unit-tk` | `test-unit-tk-linux-x86`, `test-unit-tk-macos-x86`, `test-unit-tk-macos-arm`, `test-unit-tk-windows-x86`, `test-unit-tk-windows-arm` |
| Test integration TK | `test-integration-tk` | `test-integration-tk-linux-x86`, `test-integration-tk-macos-x86`, `test-integration-tk-macos-arm`, `test-integration-tk-windows-x86`, `test-integration-tk-windows-arm` |
| Setup | `setup` | `setup-linux-x86-gcc`, `setup-linux-x86-clang`, `setup-linux-arm-gcc`, `setup-macos-x86`, `setup-macos-arm`, `setup-windows-x86`, `setup-windows-arm` |
| Quality/Security (Linux/x86-only, per D3) | unchanged (`quality-lint-check-fd`, `security-seccomp-check-fd`, ...) | unchanged |

`test-unit-all`/`test-integration-all`/`build-all`/`test-all` stay as they are today — aggregate
recipes that call the bare dispatchers, so `just build-all` continues to work unmodified on any
platform.

---

## 4. Documentation Updates Required

- `doc/execution/build.md` — add the single documented manual prerequisite: install `just` (D4).
  Everything else a contributor needs after that comes from `just setup`.
- `doc/execution/development.md` — Prerequisites section currently says "install these tools
  yourself"; replace with "run `just setup`" and point to `build.md` for the `just`-itself
  prerequisite. Update the "Useful current commands" list.
- `doc/execution/ci.md` — Zig Toolchain Policy section (88-112) currently documents two Zig
  install paths (`install-zig.py` for CI, `install-zig-bootstrap.py` for local); collapse to one
  path per D1, and describe `setup-*` as the entrypoint that wraps it. Update workflow tables to
  show fully-qualified recipe names now that CI calls e.g. `test-unit-tk-linux-x86` instead of
  relying on the composite action's inline branching.
- `doc/execution/contribution/tickoni.md` — if it documents the `build-fd-*`/`test-*` naming
  convention, extend it to state the `{command}-{os}-{arch}[-{compiler}]` grid explicitly as a
  rule for any *new* recipe family, not just today's build/test set.
- `doc/execution/testing-tickoni.md` — test command matrix needs the new fully-qualified names,
  including the new cross-platform `test-unit-fd-{os}-{arch}` entries from D3, with a note that
  CI does not currently schedule the macOS/Windows variants (D5) even though they're runnable.

---

## 5. Decisions (resolved 2026-08-06)

**D1 — `install-zig-bootstrap.py`: delete it. One path, for everyone.** No dev-only escape
hatch. Every environment — laptop or CI runner — installs Zig through the same `install-zig.py`
call inside `setup-*`. If the prebuilt-release path ever fails on some platform, the fix goes
into that one script and every consumer picks it up; a parallel bootstrap-from-source path would
just be a second thing to keep in sync (or forget to). `ci.md`'s "local developer machines may
still use `install-zig-bootstrap.py`" language is retired in the same change.

**D2 — `fd-build-windows.ps1`: delete it.** Confirmed no external trigger; the project is
self-contained, so the grep-based "zero in-repo callers" finding is conclusive.

**D3 — `test-unit-fd` is not Linux-only.** Tickoni is a cross-platform project and CI already has
real linux/macOS/Windows lanes; native Firedancer C unit-test binaries should build and run on
every platform the project supports, not just Linux. `test-unit-fd-{os}-{arch}[-{compiler}]`
recipes are added for macOS and Windows too, reusing the already-working `build-fd-macos-*`/
`build-fd-windows-*` native (clang) builds and adapting the `run-unit-test` make invocation per
platform (drop the Linux-only `-Wl,-z,shstk` CET linker flag, replace `nproc` with a portable
core-count lookup via `platform.sh`). This supersedes the fallback this session's earlier fix
introduced (macOS `test-unit-fd` silently running `test-unit-tk` instead) — that was a stopgap
for immediate unblocking, not the target shape; under this plan `test-unit-fd` means "ran the
native C test binaries" on every platform where it's invoked, full stop.

  **Known technical risk carried into implementation, not glossed over here:** `build-fd-macos-x86_64`'s
  own comment (`justfile:150-152`) already documents that `blst`/`zstd`/`lz4` — the exact EXTRAS
  `test` mode requires — "have path mismatches and platform-specific assembly that fails on
  macOS x86_64." So `test-unit-fd-macos-x86` may hit a real, pre-existing build blocker
  independent of this consolidation effort. The implementation phase for D3 should be treated as
  a spike per platform (does the native test binary actually build and link?) rather than an
  assumed-safe rename; if a given platform genuinely cannot build the native test surface, that
  becomes a tracked bug against the FD vendor sources, not a reason to fall back to faking the
  recipe's meaning again.

**D4 — `just` is the sole exception to Principle 1, documented, not scripted.** It's one tool;
developers install it themselves (`brew install just`, `cargo install just`, etc.), same as they
would today. Add a one-line prerequisite note to `doc/execution/build.md` ("install `just`
first") rather than `development.md`, and rather than adding a non-`just` bootstrap script. CI
keeps its existing `taiki-e/install-action@just` first step in the composite action.

**D5 — No new CI lanes.** Consolidate only what already runs. Today's CI shape — full
build+quality+security+unit+integration on Linux, build+`test-unit-tk`+`test-integration-tk`
only on macOS/Windows — is intentional, to control runner-minute cost, and stays that way.
Concretely: the new `test-unit-fd-macos-*`/`test-unit-fd-windows-*` recipes from D3 are added to
the `justfile` and become invocable (locally, or via `workflow_dispatch` if someone wants to run
them by hand), but no workflow file gains a new scheduled job calling them on every PR. If cost
tradeoffs change later, wiring an existing recipe into a workflow is a one-line addition — that's
a separate decision from this consolidation.

---

## 6. Suggested Phased Rollout

1. **Phase 0 (no behavior change):** Add `contrib/platform.sh`. Update `zigw.sh` and
   `fd-build-windows.sh` to call it instead of their own detection. Delete
   `detect-windows-arch.sh`, `fd-build-linux.sh`, `fd-build-windows.ps1` (D2),
   `install-zig-bootstrap.py` (D1), and the corresponding "local bootstrap" section of `ci.md`.
   Verify `build-all`/`test-unit-all`/`test-integration-all` still pass on Linux, macOS, and (if
   available) Windows.
2. **Phase 1 (justfile renames, additive):** Introduce the fully-qualified `-{os}-{arch}`
   recipe names as the canonical targets; keep today's names (`build-fd-gcc`, `build-fd-macos-arm`,
   `build-fd-windows-x86`, ...) as thin aliases so in-flight branches and any external docs don't
   break mid-migration.
3. **Phase 2 (`test-unit-fd` cross-platform spike, D3):** Add `test-unit-fd-macos-x86`,
   `test-unit-fd-macos-arm`, `test-unit-fd-windows-x86`, `test-unit-fd-windows-arm`. Treat each as
   a spike, not a guaranteed-safe rename — validate the native `run-unit-test` binaries actually
   build and link per platform (portable core-count lookup instead of `nproc`, no `-Wl,-z,shstk`
   off Linux), and file a tracked bug against any platform that hits the pre-existing
   `blst`/`zstd`/`lz4` macOS x86_64 vendor-source blocker instead of silently degrading the
   recipe's meaning again. This phase is the highest-risk one in the plan and should ship on its
   own, independent of the mechanical renames in Phases 0/1/4.
4. **Phase 3 (CI cutover):** Update all workflow files to call the new fully-qualified names
   directly (Principle 4), for the exact same jobs that run today — no new scheduled lanes (D5).
   Verify every existing CI lane still passes.
5. **Phase 4 (setup scripts):** Add `setup-*` recipes per 2.6. Convert
   `setup-public-gh-runner/action.yml` into a thin wrapper. Validate a clean CI runner and a
   clean local checkout both go from zero to green using only `just setup && just build-all &&
   just test-unit-all` (plus the one documented manual prerequisite: install `just` itself, D4).
6. **Phase 5 (remove aliases + docs):** Once nothing references the old names, delete the Phase 1
   aliases and update `development.md`/`build.md`/`ci.md`/`testing-tickoni.md`/
   `contribution/tickoni.md`.

Each phase should land as its own reviewable change, not one large rewrite — this is a build-system
change under `CLAUDE.md`'s "Ask Before You Change," and the existing `test-unit-fd` macOS fix
earlier in this session is a good example of the size of change that should ship per step.

---

## 7. Follow-up (Post-Implementation)

Once all phases above have landed, `doc/execution/build.md` and `doc/execution/testing-tickoni.md`
still need to be updated to reflect the final recipe names, `setup-*` flow, and `just`-prerequisite
note described in Section 4 — do not consider this proposal fully closed until both docs are
brought in sync with the shipped `justfile`.
