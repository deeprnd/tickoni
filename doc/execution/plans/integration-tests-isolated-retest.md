# Re-test every integration test file in isolation

## Goal

Every integration test file under `src/tickoni/test/integration/` currently has its
tests disabled by a per-test `const shouldSkip = true;` guard. Re-enable them
**one file at a time**, so any failure is attributable to exactly one file. Run the
integration lane, find the root cause of each failure, fix it, and re-run until that
file is green. Then re-disable the file and move to the next.

When the plan is complete:

- every file was proven green on its own,
- every `shouldSkip` is back to `true`,
- the only diff left is the root-cause fixes (and the plan's progress table).

DO NOT RUN ANYTHING IN PARALLEL. One file is un-skipped at a time. Never run two
`zig build` / `just` invocations at once, because the lane uses shared workspaces,
ports and a shared Zig cache.

---

## How a single file is processed (the loop)

For each file `X` in the order below:

1. **Enable** — in `X` only, change every `const shouldSkip = true;` to
   `const shouldSkip = false;`.
   - Confirm with `Grep` that `X` has zero `shouldSkip = true` and that the
     number of `shouldSkip = false` matches the "shouldSkip count" in the table.
   - Confirm no other file has `shouldSkip = false` (isolation check).
2. **Run** — `just test-integration-tk` (from the repo root, nothing else running).
   - Save the full output to a log under the scratchpad, not the repo, e.g.
     `<scratchpad>\it-<file>.log`.
   - Read the Zig summary: tests passed / failed / **skipped**. All of `X`'s tests
     must show as passed. Every other file must show as skipped.
3. **Investigate** — for each failure (assertion, crash, hang, link error,
   leaked-memory report from `std.testing.allocator`):
   - Reproduce it. Re-run the same single-file loop. Never "fix" a failure you
     have not seen twice.
   - Identify the **root cause**: read the failing test, the code under test, and
     the owning doc (see "Rules for fixes"). Decide whether the test, the code, or
     the doc is wrong. Do not paper over it with sleeps, retries, widened
     tolerances or new skips.
   - Fix the root cause. Add or adjust a test that pins the behavior if none
     covers it.
4. **Re-test** — go back to step 2. Repeat until all of `X`'s tests pass
   with the full summary clean.
5. **Disable** — change every `const shouldSkip = false;` in `X` back to
   `const shouldSkip = true;`. Confirm with `Grep` that no `shouldSkip = false`
   remains anywhere under `src/tickoni/test`.
6. **Record** — update the progress table (status, date, fixes made, commit).
   Commit the fix(es) for `X` separately from the plan update, so each file's
   changes are reviewable and revertible on their own.
7. Move to the next file.

### Mechanical flip

Use a byte-preserving edit so the working copy's line endings are not rewritten
(git already warns about LF/CRLF on these files):

```bash
# enable
sed -i 's/const shouldSkip = true;/const shouldSkip = false;/' src/tickoni/test/integration/<X>.zig
# disable
sed -i 's/const shouldSkip = false;/const shouldSkip = true;/' src/tickoni/test/integration/<X>.zig
```

After the disable step, `git diff -U0 -- <X>.zig` must show **no** `shouldSkip`
hunks that were not already in the working tree before the plan started.

---

## Preconditions

- [x] Working tree is on `story/tkapi-fd-stem` and has a lot of uncommitted work
      (stem tile, `os` shim, harness changes). Commit or stash it first so a
      per-file fix commit contains only that file's fix. Do not mix the plan with
      unrelated edits.
      *Done 2026-11-24: committed as `4127a2e41` (WIP baseline). Plan docs kept
      out of it.*
- [x] Firedancer libs are built (`just build-fd`) and `zig build` of the Tickoni
      binary works (`just build-tk`); the lane depends on `exe_install`.
- [ ] Baseline: run `just test-integration-tk` once with **everything skipped** and
      record the pass/skip counts. This is the "all green because nothing runs"
      reference, and it proves the toolchain, cache and link steps work before any
      test is enabled.
      *Done 2026-11-24: 27 test binaries, **0 passed, 145 skipped, 0 failed**,
      exit 0, about 4m24s wall time (141 integration guards + 4 in `mocks/`).
      FD libs and `tickoni.exe` were already built under `build/`.*
- [x] Host platform. The lane dispatches on `{{ os }}-{{ arch }}`. The host here is
      Windows 11 (`test-integration-tk-windows-x86`). All platforms have equivalent
      capabilities, so there are **no OS-specific tests and no platform exclusions**.
      The old `builtin.target.os.tag` guards (tkings, tkapi, tkpoly, tkdiag, metric,
      `stem_liveness`) were removed on purpose. A failure on Windows is a real bug
      in the code or the test to root-cause and fix, never a "platform-unsupported"
      result. Do not re-add OS guards or skip a file because of the host OS.
      Platform differences belong behind the portable shim APIs (`os.c`,
      `os_api.zig`, `process_api`), not in the tests.
- [ ] Freeze/resume is the only OS-flavoured area (tkdiag's frozen-tile test, and
      `stem_liveness.signalTile`). It goes through the portable
      `tk_process_suspend` / `tk_process_resume` (SIGSTOP/SIGCONT on POSIX,
      `NtSuspendProcess` / `NtResumeProcess` on Windows). Run these tests on the
      host and fix the shim if they fail. Do not skip them on Windows.
- [ ] `/proc`-style per-tile OS metrics (`tkdiag`, `test_tile_metric`, the tkpoly
      launch test) must be served through the portable `tk_os_stats` layer, with
      one implementation per platform behind one interface. If a test fails
      because it reads `/proc` directly, fix the test to use the portable path.

---

## Test files and order

There are 26 test files (the two other `.zig` files in the directory,
`ingest_harness.zig` and `stem_liveness.zig`, are helpers with no tests and no
`shouldSkip`; they are exercised through their consumers and never flipped).

Order: infrastructure first, from the smallest and least-coupled to the stem/agent
topologies, then the domain lane. This puts the files that every later test depends
on (links, metrics, process topology) first, so a failure there is found before it
shows up as noise in a higher-level file. Counts are current `shouldSkip` counts.

### Infra lane (`LaneKind.infra`, 18 process files + model HTTP)

| # | File | shouldSkip count | Status | Date | Fix / notes |
|---|------|-----------------:|--------|------|-------------|
| 1 | `test_minimal_setup.zig` | 6 | PASS | 2026-11-24 | 6/6 passed on the first run (lane: 6 passed, 139 skipped, 0 failed; 110s). No fix needed. No orphans. |
| 2 | `test_link_bounds.zig` | 4 | PASS | 2026-11-24 | 4/4 passed on the first run (lane: 4 passed, 141 skipped, 0 failed; 120s). No fix needed. No orphans. |
| 3 | `test_tile_metric.zig` | 17 | PASS | 2026-11-24 | 17/17 passed on the first run (lane: 17 passed, 128 skipped, 0 failed; 147s). No fix needed. No orphans. No direct /proc reads in the test. |
| 4 | `test_process_topology.zig` | 5 | PASS | 2026-11-24 | 5/5 passed on the first run (lane: 5 passed, 140 skipped, 0 failed; 139s). No fix needed. No orphans. |
| 5 | `test_process_pipeline.zig` | 2 | PASS | 2026-11-24 | 2/2 passed on the first run (lane: 2 passed, 143 skipped, 0 failed; 117s). No fix needed. No orphans. |
| 6 | `test_process_shutdown_reap.zig` | 7 | PASS | 2026-11-24 | 7/7 passed on the first run (lane: 7 passed, 138 skipped, 0 failed; 163s). No fix needed. No orphans. |
| 7 | `test_process_cpu_placement.zig` | 5 | PASS | 2026-11-24 | 5/5 passed on the first run (lane: 5 passed, 140 skipped, 0 failed; 182s). No fix needed. No orphans. |
| 8 | `test_process_fixture_parity.zig` | 1 | PASS | 2026-11-24 | 1/1 passed on the first run (lane: 1 passed, 144 skipped, 0 failed; 166s). No fix needed. No orphans. |
| 9 | `test_tile_tkings.zig` | 2 | PASS | 2026-11-24 | 2/2 passed on the first run (lane: 2 passed, 143 skipped, 0 failed; 163s). No fix needed. No orphans. |
| 10 | `test_tile_tknorm.zig` | 6 | PASS | 2026-11-24 | 6/6 passed on the first run (lane: 6 passed, 139 skipped, 0 failed; 192s). No fix needed. No orphans. |
| 11 | `test_tile_tkdedu.zig` | 6 | PASS | 2026-11-24 | 6/6 passed on the first run (lane: 6 passed, 139 skipped, 0 failed; 140s). No fix needed. No orphans. |
| 12 | `test_tile_tkpoly.zig` | 17 | PASS | 2026-11-24 | 17/17 passed on the first run (lane: 17 passed, 128 skipped, 0 failed; 155s). No fix needed. No orphans. |
| 13 | `test_tile_tkaudt.zig` | 4 | PASS | 2026-11-24 | 4/4 passed on the first run (lane: 4 passed, 141 skipped, 0 failed; 129s). No fix needed. No orphans. |
| 14 | `test_tile_tkdiag.zig` | 6 | PASS | 2026-11-24 | r1 failed (tkdiag stale, 119 ms). Fixed by F1 (stem idle sleep, `610efa214`). F2: the tkdiag lifecycle/fan-in helper uses the 1 s liveness threshold (user decision: logic tests, not latency). fix2 and fix3 both 6/6 (lane: 6 passed, 141 skipped). No orphans. |
| 15 | `test_tile_tkapi.zig` | 4 | PASS | 2026-11-24 | 4/4 passed on the first run (lane: 4 passed, 141 skipped, 0 failed; 141s). No fix needed. No orphans. |
| 16 | `test_tile_tkmodl.zig` | 8 | PASS | 2026-11-24 | 8/8 passed on the first run (lane: 8 passed, 137 skipped, 0 failed; 150s). No fix needed. No orphans. |
| 17 | `test_tile_tkagnt.zig` | 20 | PASS | 2026-11-24 | 20/20 passed on the first run (lane: 20 passed, 125 skipped, 0 failed; 224s). No fix needed. No orphans. Includes the frozen-tile stale test (portable suspend/resume works on Windows). |
| 18 | `test_stem_heartbeat.zig` | 5 (was 3) | PASS | 2026-11-24 | 3/3 on the first run. F1 added 2 tests (idle CPU < 1/5 core, sustained idle liveness), which failed before the fix. After `610efa214`: 5/5 (lane: 5 passed, 142 skipped). Idle stem CPU 0-46 ms per 2 s. |
| 19 | `test_model_http_backend.zig` | 4 | PASS | 2026-11-24 | 4/4 passed on the first run (lane: 4 passed, 141 skipped, 0 failed; 146s). No fix needed. test_mock_servers stayed skipped (hazard 5). No orphans. |

### Domain lane (`LaneKind.domain`, 7 files)

| # | File | shouldSkip count | Status | Date | Fix / notes |
|---|------|-----------------:|--------|------|-------------|
| 20 | `test_investment_decision_cards.zig` | 1 | PASS | 2026-11-24 | 1/1 passed on the first run (lane: 1 passed, 144 skipped, 0 failed; 112s). No fix needed. |
| 21 | `test_investment_input_policy_denials.zig` | 2 | PASS | 2026-11-24 | 2/2 passed on the first run (lane: 2 passed, 143 skipped, 0 failed; 98s). No fix needed. |
| 22 | `test_investment_restricted_instrument.zig` | 2 | PASS | 2026-11-24 | 2/2 passed on the first run (lane: 2 passed, 143 skipped, 0 failed; 106s). No fix needed. |
| 23 | `test_investment_blocked_limits.zig` | 2 | PASS | 2026-11-24 | 2/2 passed on the first run (lane: 2 passed, 143 skipped, 0 failed; 112s). No fix needed. |
| 24 | `test_investment_allowed_trade.zig` | 1 | PASS | 2026-11-24 | 1/1 passed on the first run (lane: 1 passed, 144 skipped, 0 failed; 126s). No fix needed. |
| 25 | `test_investment_fixture_system_suite.zig` | 1 | PASS | 2026-11-24 | 1/1 passed on the first run (lane: 1 passed, 144 skipped, 0 failed; 129s). No fix needed. |
| 26 | `test_investment_replay.zig` | 5 | PASS | 2026-11-24 | 5/5 passed on the first run, 0 runtime skips (lane: 5 passed, 140 skipped, 0 failed; 119s). The generator test ran and rewrote the fixture byte-identically (sha256 3279cde1..., saved copy diffed, no change). No fix needed. |

### Re-verification after F1 (`610efa214` changed every stem tile's loop)

Files 1-13 and 15-17 passed before the `fd_stem` idle-sleep change. The ones that
spawn tile processes are re-run once each on the new code (same single-file loop).
`test_link_bounds` (2) and the domain files (19-26) run in-process with no stem
tiles, so their results stand.

| # | File | Status | Fix / notes |
|---|------|--------|-------------|
| 1 | `test_minimal_setup.zig` | PASS | 6/6 (6 passed, 141 skipped; 105s). No orphans. |
| 3 | `test_tile_metric.zig` | PASS | 17/17 (130 skipped; 106s). No orphans. |
| 4 | `test_process_topology.zig` | PASS | 5/5 (96s). No orphans. |
| 5 | `test_process_pipeline.zig` | PASS | 2/2 (93s). No orphans. |
| 6 | `test_process_shutdown_reap.zig` | PASS | 7/7 (107s). No orphans. |
| 7 | `test_process_cpu_placement.zig` | PASS | 5/5 (99s). No orphans. |
| 8 | `test_process_fixture_parity.zig` | PASS | 1/1 (95s). No orphans. |
| 9 | `test_tile_tkings.zig` | PASS | 2/2 (89s). No orphans. |
| 10 | `test_tile_tknorm.zig` | PASS | 6/6. The first run took 532s, all of it before the tests started (they took 4 s): a one-off build/host stall. The rerun took 120s. No orphans. |
| 11 | `test_tile_tkdedu.zig` | PASS | 6/6 (100s). No orphans. |
| 12 | `test_tile_tkpoly.zig` | PASS | 17/17 (112s). No orphans. |
| 13 | `test_tile_tkaudt.zig` | PASS | 4/4 (95s). No orphans. |
| 15 | `test_tile_tkapi.zig` | PASS | 4/4 (95s). No orphans. |
| 16 | `test_tile_tkmodl.zig` | PASS | 8/8 (111s). No orphans. |
| 17 | `test_tile_tkagnt.zig` | PASS | 20/20 (120s). No orphans. |

### Added by user decision (2026-11-24)

| # | File | shouldSkip count | Status | Date | Fix / notes |
|---|------|-----------------:|--------|------|-------------|
| 27 | `mocks/test_mock_servers.zig` | 4 | PASS | 2026-11-24 | 4/4 on the first run (lane: 4 passed, 143 skipped, 0 failed; 99s). No fix needed. Re-disabled. |

Total after F1: **143** guards in the integration directory (`test_stem_heartbeat` 3 -> 5).
Pre-F1 total: 141 `shouldSkip` guards across 26 files (re-verified with Grep at plan start
on 2026-11-24. The first draft said 142 and listed tkpoly as 18, but tkpoly has 17
tests and every one is guarded. `shouldSkip = false` occurs nowhere).

`just test-integration-tk` runs the `all` lane. It registers the 18 process files, then
one series step that runs `test_mock_servers.zig` followed by `test_model_http_backend.zig`,
then the 7 domain files, chained sequentially (`build-lib/lanes/integration.zig`).
Because each test binary is chained to the previous one, a hang or failure in an earlier
binary blocks every later file's run. That is another reason to keep exactly one file
enabled at a time.

---

## Known hazards (read before starting)

1. **Fixture-generating test (`test_investment_replay.zig`, file 26).**
   `test "gen audit allowed trade jsonl"` is guarded by `shouldSkip` and, when
   enabled, truncates and rewrites the tracked file
   `src/tickoni/test/fixtures/investment/scenarios/fixture_audit_allowed_2000.jsonl`
   (already modified in the working tree). Before enabling file 26:
   - copy that fixture aside (scratchpad) and note its hash,
   - after the run, diff the regenerated fixture against the saved copy.
   An audit-schema or hash-chain change is a "Ask Before You Change" item in
   `AGENTS.md`. If the regenerated fixture differs, stop and ask the user. Do not
   commit a changed fixture silently. Restore the saved copy if the diff is not
   approved. Running this generator inside a "retest" is a side effect; confirm
   with the user whether it should stay enabled in step 1 or be left skipped.

2. **Other skips in `test_investment_replay.zig`.** It has 7 `SkipZigTest` returns
   but only 5 are `shouldSkip` guards. The other two (`error.InvalidPath`,
   `error.FileNotFound` while loading the fixture) are runtime skips. A run can look
   "green" while those tests were skipped. For this file, a pass means the skipped
   count for the file is **zero**, so the fixture path must resolve from the test's
   working directory.

3. **Process-spawning tests (`test_process_*`, `test_stem_heartbeat`,
   `test_tile_*`).** They start the installed `tickoni` supervisor and tiles as child
   processes with shared memory workspaces, ports and CPU pinning. A failed run can
   leave orphan processes or stale workspaces that make the next run fail for
   unrelated reasons. Before every run, check for leftover `tickoni*` processes and
   stale workspace/shm artifacts; clean them and record it if found. Treat orphan
   leakage as a bug in the test or tile shutdown, not as noise.

4. **Hangs.** A stuck child can hang the chain. Run with a wall-clock timeout
   (suggested: 10 minutes per file run). A timeout is a failure with a root cause to
   find (usually a liveness or shutdown bug), not a reason to raise the timeout.

5. **`test_model_http_backend.zig` shares its step with `test_mock_servers.zig`.**
   `src/tickoni/test/mocks/test_mock_servers.zig` has 4 `shouldSkip` guards too,
   but it is outside `src/tickoni/test/integration`. The request scopes this plan to
   the integration directory, so it is **not** flipped here. Its tests keep skipping
   while file 19 runs. Decision (2026-11-24): added as file 27.

6. **Link and memory leaks.** `std.testing.allocator` leak reports and Firedancer
   workspace/link-bound violations (depth/MTU/overrun) are real failures. Do not
   suppress them.

---

## Findings and open decisions

### F1. Idle stem tiles spin and starve each other on small hosts (file 14)

- **Symptom.** `tkdiag_integration: stem tkdiag keeps running until the supervisor
  halts it` polls `refreshProcessHealth` for 2 s under the supervisor's default
  stale threshold (100 ms = 5 x 20 ms heartbeat interval) and expects tkdiag to stay
  `.running`. On r1 it saw `.stale` (age 119 ms). On r2 it passed, but in the same
  test metric was marked stale (116 ms), and in r1 tkrepl (224 ms) and metric
  (112 ms) were too. Staleness is sticky, so one late heartbeat is final.
- **Host.** Windows 11 ARM64 VM on Apple Silicon, 4 vCPUs.
- **Root cause.** `fd_stem` (`src/disco/stem/fd_stem.c`) never sleeps when idle;
  it only `FD_SPIN_PAUSE`s. The payment pipeline is 9 stem-loop processes (tkings,
  tknorm, tkdedu, tkpoly, tkaudt, tkrepl, metric, tkdiag, tkapi), plus the test
  process and the feed harness: 10+ CPU-bound threads on 4 vCPUs. A runnable tile
  can wait more than 100 ms for a time slice. The median heartbeat age is 0-20 ms,
  so the tiles are not wedged. They are not scheduled.
- **Doc vs code.** `doc/knowledge/tile-orchestration.md` "Staleness budget"
  derives the 2.5x margin from the in-loop housekeeping gap (about 40 ms) of a tile
  that is running. Its "Deviation: Bounded Sleep Instead of Pure Spin" section says
  Tickoni runs on consumer hardware with limited cores and "must sleep during idle
  to keep the total tile-to-core ratio manageable". That holds for the generic link
  primitives, but the stem-migrated tiles do not sleep, so every idle stem tile
  burns a full core. This discrepancy is the real defect. The test exposes it.
- **Options (user decision, tile loop behavior is an "Ask Before You Change" item):**
  1. Code to docs: give Tickoni stem tiles a bounded idle sleep (for example in
     `BEFORE_CREDIT`/`AFTER_CREDIT` when nothing was polled), keeping the heartbeat
     and HALT checks per iteration.
  2. Test only: test 1 configures `stem_liveness.stale_after_ns` (1 s), as the
     other liveness tests in this file already do, because its stated contract is
     "no self-exit and no crash until HALT", not scheduler latency.
  3. Supervisor: raise or scale the default stale threshold with the
     tile-to-CPU ratio.
- **Decision (user, 2026-11-24): option 1, in the infrastructure.** Every
  `fd_stem` tile gets the idle sleep from `src/disco/stem/fd_stem.c` itself,
  since all Tickoni tiles migrate to `fd_stem`. Firedancer could spin because it
  owns a core per tile; Tickoni is multi-process on limited retail hardware.
- **Work in progress:**
  - Docs first: `doc/knowledge/tile-orchestration.md` (stem loop step 7, "The same
    deviation in `fd_stem`", staleness budget with the idle sleep).
  - Tests next, added to `test_stem_heartbeat.zig` (its guard count goes from 3
    to 5): "an idle stem tile sleeps instead of spinning on a core" (CPU per idle
    stem tile over 2 s < 1/5 core, via new `c_abi.os_stats.processCpuNanos`) and
    "no idle stem tile is classified stale under the default threshold". Both
    fail on the unfixed code: tkings used 609 ms of CPU in 2047 ms, and metric
    went stale.
  - Code: `fd_stem.c` (`STEM_IDLE_SPIN_MAX` 4096, `STEM_IDLE_SLEEP_NS` 100 us)
    and `fd_log_windows.c` (`fd_log_sleep` below 1 ms uses a high-resolution
    waitable timer). Measured on the host: mingw `nanosleep(100 us)` returns at
    once, `Sleep(1)` takes 9.2 ms, and the high-resolution timer takes 1.0 to
    1.4 ms at about 2% of a core.
  - Pitfall: after editing only `fd_stem.c` (which is `#include`d into the
    `tk_*_stem.c` shims), the lane relinked `tickoni-supervisor.exe` against the
    new `libfd_util.a` but did not recompile the exe's stem objects. Child tiles
    kept running the old loop (every tk stem tile at about 35% of a core). Cleared
    `build/.zig-cache` and rebuilt cold. Rebuild `just build-fd` after any
    `src/util` change, because the lane links the prebuilt FD libs.
  - A second cause, also fixed: the metric tile polled HTTP with a 1 ms timeout
    (upstream's per-tile idle wait). On Windows `WSAPoll(1 ms)` takes 10 ms on
    average (34 ms max), which stretched metric's housekeeping cycle. It now polls
    with timeout 0 and idles through the stem sleep. `fd_metric_tile.o` comes from
    make (`libfd_disco.a`), so this also needs `just build-fd`.
  - **Result after the fix:** idle stem tiles use 0 to 62 ms of CPU per 2 s, down
    from 560 to 780 ms (the CPU test passes). Steady-state heartbeat intervals
    average about 15 ms, about `STEM_LAZY`, with a max of about 50 ms, the
    documented `4 x STEM_LAZY`.

### F2. The host itself stalls longer than the default stale threshold

- **Evidence.** After F1, the remaining over-threshold heartbeats (105 to 127 ms)
  line up with moments when every tile and the supervisor's own refresh loop jump
  by 40 to 80 ms together. A standalone probe with nothing else running (a 1 ms
  high-resolution waiter for 20 s) saw max gap 225 ms, 4 gaps over 50 ms and 1
  over 100 ms. The Windows ARM VM on Apple Silicon pauses vCPUs. No tile can
  meet a 100 ms heartbeat on this host.
- **Effect.** Any assertion of "never stale under the default 100 ms threshold"
  is flaky here: `test_tile_tkdiag` test 1 (r1 after F1: metric 111 ms, tkdiag
  116 ms) and the new `test_stem_heartbeat` test 4.
- **Decision (user, 2026-11-24):** these are logic tests, not performance tests.
  Tune the test thresholds so they pass on this VM and on faster non-VM machines.
  Applied: the tkdiag lifecycle/fan-in tests and the new sustained-idle test use
  `stem_liveness.stale_after_ns` (1 s). The supervisor default is unchanged.

---

## Rules for fixes

These come from `AGENTS.md` and apply to every fix made during this plan.

- Docs, then tests, then implementation. If a failure shows the documented behavior
  and the code disagree, flag the discrepancy. The default remediation is to bring
  the **code** in line with the docs
  (`doc/knowledge/architecture.md`, `doc/knowledge/tile-topology.md`,
  `doc/execution/tile-delivery-status.md`), not to rewrite the docs to match.
- Surgical changes: touch only what the failure requires. Mention unrelated dead
  code or bugs found along the way, and do not fix them in the same change.
- **Stop and ask the user** instead of fixing when the root cause needs a change to:
  tile ownership/IDs/lifecycle/link semantics; event framing, source offsets,
  normalization, dedupe or hash behavior; case lifecycle; capability envelope or
  policy outcomes; audit schema, hash chaining or replay substitution; public
  `tkapi`/model/tool/adapter contracts; storage roles; or model/adapter access rules.
  Present the root cause and the options; do not pick silently.
- No weakening a test to make it pass (looser assertions, longer sleeps, added
  retries, new skips, or removing the test). If a test itself is wrong, fix it and
  explain why in the commit message.
- Required env vars fail closed. Test-only helpers may set defaults locally.
- Do not add developer tooling targets to upstream Firedancer Makefiles. Use the
  `justfile` and Tickoni-owned scripts.
- If a throwaway script seems necessary to diagnose a failure, that is a sign of a
  missing test. Write the test and wire it into the right lane per
  `doc/execution/testing-tickoni.md` instead.

---

## Done criteria

Status 2026-11-24: **all met.**

- [x] All 27 rows in the tables are `PASS`, with zero skipped tests in each file
      (file 26 had 0 runtime skips). Files that spawn tile processes were re-run on
      the F1 code (see "Re-verification after F1").
- [x] `Grep` for `shouldSkip = false` under `src/tickoni/test` returns nothing.
- [x] `shouldSkip = true` count: 143 in the integration directory (141 before the
      plan, plus F1's 2 new tests in `test_stem_heartbeat.zig`) and 4 in `mocks/`.
- [x] Final `just test-integration-tk` (everything skipped again) is green:
      0 passed, 147 skipped, 0 failed, 27 binaries. That is the baseline (145) plus
      the 2 new tests.
- [x] `just test-unit-tk` is green: 942 passed, 18 skipped (pre-existing guards),
      0 failed, 60 binaries.
- [x] `git diff` since the baseline commit `4127a2e41` holds one code commit
      (`610efa214`, F1/F2 root-cause fix with tests and docs) and plan updates.
      The replay fixture is byte-identical. The only untracked file,
      `integration-tests-isolated-retest-template.md`, predates the plan and is
      not part of it.

Follow-ups noticed and not changed (out of scope):
- `tk_normalize_stem.c`: `idle_ticks` is reset and checked (`> 10000`) but never
  incremented, so that shutdown clause is dead code.
- On Windows `long` is 32-bit, so `long` nanosecond arithmetic on
  `fd_log_wallclock()` values overflows (seen with temporary instrumentation;
  no committed code is affected).
- `c_abi/os_stats.zig` unit tests are Linux-only guarded, so the Windows and
  macOS probes are compile-checked only.
- Build caching: after editing only an `#include`d `fd_stem.c`, the lane once
  relinked `tickoni-supervisor.exe` without recompiling its stem shim objects.
  Clearing `build/.zig-cache` fixed it. `fd_metric_tile.c` (with its copy of
  `fd_stem.c`) builds through make into `libfd_disco.a`, so it needs
  `just build-fd`.

## Status values

`TODO` · `IN PROGRESS` · `PASS` · `BLOCKED (needs user decision)`
