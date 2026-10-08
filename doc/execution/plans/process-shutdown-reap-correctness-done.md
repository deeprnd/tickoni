# Process shutdown and reap correctness

**Status:** planned  
**Scope:** `src/tickoni/c_abi/shim/os.c`, `src/tickoni/util/process_api.zig`, `src/app/tickoni/supervisor.zig`, process-mode tests

## Problem and evidence

The current shutdown path can report a genuine child failure as a clean stop. `outcomeFromTerm(.exited(nonzero), true)` returns `.force_terminated`, although a POSIX `SIGKILL` produces a *signaled* wait status, not an exit code. The force-phase `.reaped` arm in `stopProcess()` passes `true` even though it has not attempted a kill for that child. Conversely, `waitProcess()`'s final reap passes `false` regardless of whether a kill was attempted. `termProcess()` returns success even when `killProcess()` fails.

The C `tk_process_reap()` shim maps all `waitpid()` errors to `pid = -1`, losing the old `EINTR` retry and `ECHILD` distinction. In the force loop, `.failed` clears the child without a confirmed reap; `waitProcess()` can also treat `.failed` or a still-running child as `.exited_ok`. These are correctness issues independent of the observed Linux clang/ARM timing. **Do not assume EINTR or a slow HALT response caused the reported failure without evidence.** Passing integration runs are not proof of that cause.

## Firedancer comparison and policy boundary

Firedancer's PID-namespace supervisor logs each reaped tile's identity and raw signal or exit code. It accepts exit code 0 only for tiles explicitly marked `allow_shutdown`; non-zero exits and signals remain failures (`src/app/shared/commands/run/run.c`). Tickoni should similarly preserve the observed per-tile result, **not** copy Firedancer's policy of terminating all sibling tiles on one failure. Tickoni intentionally supports stopping live tiles while retaining independently crashed tiles.

Firedancer's outer process can still lose detail: it propagates a numeric status rather than the original tile reason, and its parent signal handler exits directly during intentional shutdown. Treat that as a warning, not a pattern to reproduce. Specify Tickoni's shutdown contract separately: an observed non-zero exit remains a crash; an observed signal matching a successful supervisor kill request can be reported as an intentional stop; clean exit 0 remains a stop. Keep the raw wait status and whether HALT/kill were requested available in diagnostics so a reported `.stopped` does not erase *how* the tile ended. A process that has not been reaped has no known exit reason; do not invent one. A shutdown racing an unobserved failure cannot always identify which happened first—document that limit rather than claiming perfect attribution.

## Plan

### 1. Restore trustworthy reap results

- In the POSIX branch of `tk_process_reap()`, retry `waitpid()` on `EINTR` and expose `ECHILD` separately from other failures. Keep Windows behavior explicit and preserve the existing cross-platform API contract; update the C/Zig result type together if a new result field or status is needed.
- In `tryReapNoHang()`, map `ECHILD` to `.detached` (the prior behavior). Preserve `.failed` for other errors and make it diagnosable (at least errno/error category and PID). Confirm the Windows path remains non-blocking and preserves its current exit-status mapping.
- Audit every caller (`reapExitedChildrenNoHang()`, `refreshProcessHealth()`, `stopProcess()`, `waitProcess()`, `ProcessState.deinit()`). A transient `.failed` must not be interpreted as a confirmed exit or silently discard ownership of a potentially live child. Distinguish an unreapable/detached child from a clean exit; bound retries and report unresolved children rather than claiming `.stopped`.

### 2. Make outcome classification evidence-based

- Restore `.exited(nonzero)` -> `.exited_code` in `outcomeFromTerm()`, even after a kill request. Keep `.exited(0)` as a clean exit. Classify a signaled termination as an intentional stop only when the supervisor has evidence it successfully requested that termination for this child; otherwise preserve crash reporting. Account for Windows's explicit force-kill exit code separately: a numeric code by itself is not proof the supervisor caused it.
- In the force-phase `.reaped` arm of `stopProcess()`, pass the normal/non-forced classification: no kill was attempted for that child. Do not blanket-classify grace-period reaps as clean stops; preserve a tile's independently observed crash, including one racing with shutdown.
- Record kill-request success accurately: do not set the per-child flag after `killProcess()` fails. Decide and document what the flag means (successful kill request, not proof that it caused the exit). Match an intentional POSIX signal to the requested signal rather than treating any later signal as proof of that kill. Make `waitProcess()`'s ordinary and final reap paths apply the same policy. Preserve already-recorded crashes; do not kill healthy siblings merely because another tile failed.
- Retain or emit per-tile PID, raw exit kind/code/signal, HALT and kill request/result, and classified handle state at the point of observation (before workspace teardown). Keep raw evidence distinct from the derived stop/crash label and ensure failures are visible even when the top-level shutdown completes successfully; avoid unbounded logging or allocations in the polling loop.
- If the desired product policy is to forgive non-zero exits *after HALT*, specify that policy separately and expose the loss of crash visibility. Do not encode it as a false claim that `SIGKILL` caused an exit code.

### 3. Identify why the affected tiles do not stop cleanly

- On the failing Linux clang/ARM configuration, record per-child PID, tile ID, HALT time, grace deadline, each reap result (including errno), kill request/result, and final exit kind/status. Keep logging outside hot paths unless needed for the investigation.
- Check whether the tile received/observed HALT, whether its run loop can block without polling CNC, and whether the configured grace period (`resolvedStopGraceNs()`, currently bounded to 500 ms–2 s) fits that path. Adjust the tile's shutdown behavior or the grace policy only if the trace supports it; do not make the test pass by hiding non-zero exits.

### 4. Add deterministic regression coverage

- Test POSIX shim results for `EINTR` retry, `ECHILD`, other errors, running, normal exit, and signal termination. Use a controllable test seam or isolated child processes; avoid relying on scheduling to trigger `EINTR`.
- Test outcome classification for `.exited(0)`, `.exited(1)`, and signaled exits with and without a successful kill request, including Windows's distinct termination status.
- Test supervisor boundaries: non-zero exit immediately before the force-phase reap; child exit between a `.running` check and the kill request; kill failure; transient reap failure; final timeout reap; and a pre-existing crashed handle. Also test HALT concurrent with a tile failure: if its status was observed, retain the tile identity and raw failure even while other tiles are stopped; if not observed, do not fabricate a clean exit. Assert both tile state/reason and that a live child is not dropped from tracking.
- Re-run `zig build test` and `zig build integration-test`, including `test_process_pipeline.zig` and `test_process_topology.zig`. Repeat on the previously failing Linux clang/ARM lanes and retain the trace for failures; distinguish passing stress runs from deterministic proof.

## Acceptance criteria

1. No non-zero POSIX exit is converted to a clean stop solely because shutdown was in progress or a kill was attempted.
2. Successfully requested termination is distinguishable from an unrelated signal crash; failed kill requests do not set the forced flag.
3. `EINTR` does not lose a child, `ECHILD` is distinguishable from other errors, and other reap failures neither masquerade as successful exits nor silently orphan children.
4. Observed tile exits retain their identity and raw wait result in diagnostics independently of the derived state; shutdown does not hide a known failure or cascade an unrelated tile failure to healthy siblings.
5. Regression tests cover the force-phase/pre-kill window and both `waitProcess()` reap paths; process-mode tests pass on the affected toolchains without masking self-exiting tiles.
