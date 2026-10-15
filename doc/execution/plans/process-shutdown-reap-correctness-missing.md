# Process shutdown and reap correctness — what's missing

**Status:** assessment 2026-10-15  \n**Source:** doc/execution/plans/metric-review-done.md (finding 3, 4, 5 and portability/test boundary section)  \n**Related plans:** `process-shutdown-reap-correctness.md`, `metric-tile-macos-support.md`, `metric-tile-windows-support.md`

## Current state

The process shutdown/reap plan is **partially implemented**. Structural changes (state machine, classification table, EINTR retry) are in place, but the C ABI unification, Zig shim mirroring, test seam infrastructure, and cross-platform test suite are all still unwritten.

## What's done

### Finding 3 — No-hang reap
- POSIX branch in `os.c` now retries `EINTR` and exposes errors properly (finding 5, line 138 of metric-review-done.md).
- Semantics are not yet unified across all platforms.

### Finding 4 — Shutdown state machine
- `ChildRecord`-style tracking is in place.
- `forceTerminate()` replaces `termProcess()`.
- Fixed state machine is implemented.

### Finding 5 — Exit classification
- Classification table (matching action → intentional termination) is partially wired in.

## What's missing

### 1. `os.h` as single C ABI definition

**File to create:** `src/tickoni/c_abi/shim/os.h`

**Problem:** No canonical header exists. There are still three duplicate `tk_process_reap_result` declarations scattered across the codebase.

**Contract (from metric-review-done.md):**
- Define result kinds: `RUNNING`, `EXITED`, `SIGNALED`, `STOPPED`, `NO_CHILD`, `FAILED`.
- Result carries `uint exit_code`, `uint signal`, `uint native_status`, portable error category, and `uint native_error`.
- Add `tk_process_force_terminate(process_token, out)` function.
- Include it from `os.c`; delete the three duplicate declarations.

**Done condition:** One no-hang poll has identical semantics on every platform and cannot block.

---

### 2. Zig C ABI mirroring with compile-time assertions

**File to fix:** `src/tickoni/c_abi/os.zig`

**Problem:** `os.zig:163-170` hard-codes platform `ECHILD` values (macOS `77`; Darwin `ECHILD` is `10`). `process_api.zig` still chooses reap-option numbers by OS at lines 59-62. No compile-time size/alignment assertions.

**Contract:**
- Mirror every C struct exactly in `src/tickoni/c_abi/os.zig`.
- Add compile-time size/alignment assertions.
- `src/tickoni/util/os_api.zig` re-exports semantic wrappers only.

**Done condition:** All platform policy is testable through semantic values without compiling an OS-specific branch in the supervisor.

---

### 3. Zig abstraction cleanup

**Files to fix:** `src/tickoni/util/process_api.zig`, `src/tickoni/util/os_api.zig`

**Problem:** `eChildErrno()`, `usesWaitpidReap()`, `killProcessSignal()`, all numeric signal construction, and all `builtin`/`std.posix` imports are still present.

**Contract:**
- Delete `eChildErrno()`, `usesWaitpidReap()`, `killProcessSignal()`, all numeric signal construction, and all OS-tag branches.
- `process_api.zig` exposes exactly three process-domain operations: `tryReapNoHang(child)`, `forceTerminate(child)`, and `classify(observation, successful_action)`.
- `process_api.zig` imports no `builtin` and no `std.posix`.
- Supervisor consumes only `PollResult`, `TerminationAction`, `ProcessError`, and `ProcessOutcome`.

**Done condition:** A repository search over `process_api.zig`, `supervisor.zig`, and process integration tests finds no OS signal, wait, errno, or Win32 constants.

---

### 4. Process unit tests (with test seam)

**File to create/fix:** `src/tickoni/util/test_process_api.zig`

**Problems:**
- `test_process_api.zig:328-330`: The EINTR test still asserts `true` (placeholder).
- `test_process_api.zig:97-100`: Explicitly excludes Windows.

**Contract:**
1. Replace placeholder EINTR test with a `TK_PROCESS_TEST` C seam that returns `EINTR`, `EINTR`, then exit `7`; assert one public call returns exit `7` after three native calls.
2. Test live-child no-hang, exit `0`, exit `42`, POSIX signal, `NO_CHILD`, non-EINTR failure, failed force request, wide Windows exit code, and the complete classification table.
3. Remove the file-wide Windows compile error. Mark only genuinely POSIX signal/ECHILD cases POSIX-only.

**Done condition:** Every test case runs on Linux, macOS, and Windows with no platform skips.

---

### 5. Supervisor unit tests (injected seam)

**File to create:** Supervisor unit test suite

**Problem:** No injected poll, terminate, clock, or sleep seam exists.

**Contract:**
- Extract the child lifecycle state machine behind injected callbacks.
- Script and assert:
  - Nonzero exit before force.
  - Exit between poll and force.
  - Force failure.
  - Transient reap failure.
  - Accepted force without reap.
  - Matching force result.
  - Mismatched signal/result.
  - Detached child.
  - Pre-existing crash preservation.
  - CNC-read suppression.
  - Collective deadline.
  - Teardown blocked by one owned child.

**Done condition:** Every test must assert both ownership and public tile state.

---

### 6. Process integration tests (cross-platform)

**File to fix:** `src/tickoni/test/integration/test_process_topology.zig`

**Problems:**
- `test_process_topology.zig:121-161`: Expects `.signal` crash after a shim kill, which matches Linux but not Windows (Windows uses exit-code termination).
- Tests assert `.signal` instead of semantic terminal observations.

**Contract:**
1. Keep real-process cases for clean CNC HALT, a stuck child that is forcibly requested and then confirmed reaped, and a self-exiting child whose crash survives sibling shutdown.
2. Remove tests that claim to simulate kill/reap failures without controlling those operations; those cases belong in the injected unit suite.
3. Assert semantic terminal observations and tile identity, not `.signal`, in cross-platform tests.

**Done condition:** Tests pass on Linux x86_64/arm64, macOS x86_64/arm64, and Windows x86_64/arm64 with no platform skips.

---

## Implementation priority

Implement in this order:

1. **C ABI definition** — `os.h`, semantic no-hang reap, exact termination-action results, portable error mapping, C/Zig ABI size assertions.
2. **Zig shim mirroring** — Remove `eChildErrno()`, `usesWaitpidReap()`, `killProcessSignal()`, all `builtin`/`std.posix` imports. Fix `os.zig` to mirror C structs with compile-time assertions.
3. **Process unit tests** — Replace placeholder EINTR test with `TK_PROCESS_TEST` seam. Add full classification table coverage. Remove Windows-exclude flag.
4. **Supervisor unit tests** — Injected seam, full state-machine script.
5. **Process integration tests** — Semantic terminal observations, cross-platform assertions.

## Verification

After implementation:
- Run `zig build test` — all tests compile and pass.
- Run `zig build integration-test` — all integration tests pass.
- Run `test_process_pipeline.zig` and `test_process_topology.zig` on Linux clang/ARM lanes (the previously failing configuration).
- Confirm no OS signal, wait, errno, or Win32 constants remain in `process_api.zig`, `supervisor.zig`, or process integration tests.

## Open questions

1. Should the `TK_PROCESS_TEST` seam be a C function that returns predetermined results, or a Zig function that the C shim calls through an injected vtable?
2. For the `forceTerminate()` C function, should it accept a process token (PID/handle) or a pointer to a process structure?
3. What is the minimum grace period that works reliably across all three platforms?
