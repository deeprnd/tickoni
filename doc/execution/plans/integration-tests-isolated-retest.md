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
| 13 | `test_tile_tkaudt.zig` | 4 | TODO | | |
| 14 | `test_tile_tkdiag.zig` | 6 | TODO | | |
| 15 | `test_tile_tkapi.zig` | 4 | TODO | | |
| 16 | `test_tile_tkmodl.zig` | 8 | TODO | | |
| 17 | `test_tile_tkagnt.zig` | 20 | TODO | | |
| 18 | `test_stem_heartbeat.zig` | 3 | TODO | | |
| 19 | `test_model_http_backend.zig` | 4 | TODO | | |

### Domain lane (`LaneKind.domain`, 7 files)

| # | File | shouldSkip count | Status | Date | Fix / notes |
|---|------|-----------------:|--------|------|-------------|
| 20 | `test_investment_decision_cards.zig` | 1 | TODO | | |
| 21 | `test_investment_input_policy_denials.zig` | 2 | TODO | | |
| 22 | `test_investment_restricted_instrument.zig` | 2 | TODO | | |
| 23 | `test_investment_blocked_limits.zig` | 2 | TODO | | |
| 24 | `test_investment_allowed_trade.zig` | 1 | TODO | | |
| 25 | `test_investment_fixture_system_suite.zig` | 1 | TODO | | |
| 26 | `test_investment_replay.zig` | 5 | TODO | | |

Total: 141 `shouldSkip` guards across 26 files (re-verified with Grep at plan start
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
   while file 19 runs. Open question for the user: add it as file 27?

6. **Link and memory leaks.** `std.testing.allocator` leak reports and Firedancer
   workspace/link-bound violations (depth/MTU/overrun) are real failures. Do not
   suppress them.

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

- [ ] All 26 rows in the tables are `PASS`, with zero skipped tests in each file
      (other than the file-scoped runtime skips noted in "Known hazards").
- [ ] `Grep` for `shouldSkip = false` under `src/tickoni/test` returns nothing.
- [ ] `Grep` for `shouldSkip = true` count equals the pre-plan count (141 in the
      integration directory, plus the 4 untouched in `mocks/`).
- [ ] Final `just test-integration-tk` (everything skipped again) is green and its
      pass/skip counts equal the baseline.
- [ ] `just test-unit-tk` is green (fixes must not regress the unit lane).
- [ ] `git diff` contains only root-cause fixes and this plan. No stray fixture or
      line-ending churn.

## Status values

`TODO` · `IN PROGRESS` · `PASS` · `BLOCKED (needs user decision)`
