# Plan: Supervisor Background Monitoring Thread (ADR-07)

> **ADR:** [doc/knowledge/rant/supervisor-monitoring-thread.md](doc/knowledge/rant/supervisor-monitoring-thread.md)

**Goal:** Eliminate manual `reapExitedChildrenNoHang()` calls from tests and production code by introducing a single background thread that polls tile health and updates handle state automatically, with a 5ms interval.

**Architecture:**

```
┌─────────────────────────────────────────────┐
│  Supervisor                                 │
│                                             │
│  ┌─ main thread ──────────────────────────┐ │
│  │  startPaymentPipelineProcess → spawn   │ │
│  │  monitor thread, then free to serve    │ │
│  │  metrics, API, signals, user input     │ │
│  │  stopProcess → join monitor, teardown  │ │
│  └────────────────────────────────────────┘ │
│                                             │
│  ┌─ monitor thread ───────────────────────┐ │
│  │  loop while process_state != null:      │ │
│  │    1. reapExitedChildrenNoHang()       │ │
│  │    2. refreshProcessHealth()           │ │
│  │    3. sleepNanos(5ms)                  │ │
│  │  exits when process_state = null       │ │
│  └────────────────────────────────────────┘ │
│                                             │
│  Shared state:                              │
│    TileHandle.state — monitor writes, main reads
│    process_state  — main sets null to stop
│                    monitor
└─────────────────────────────────────────────┘
```

---

## Current State (Before Change)

The supervisor owns tile-crash primitives (`reapExitedChildrenNoHang`, `refreshProcessHealth`, `hasCrashed`) but no component calls them periodically:

- Tile crashes (non-zero exit, signal, `FileNotFound`) leave `TileState` as `.running` until someone calls reap
- Tests must manually insert `reapExitedChildrenNoHang()` calls in every wait loop — easy to forget
- `hasCrashed()` is a passive getter that reads stale `.running` state until a manual reap updates it
- Production callers (API handlers, metrics collectors) will inevitably duplicate this pattern

Relevant code locations:

- `src/app/tickoni/supervisor.zig` — `reapExitedChildrenNoHang()` (line 607), `refreshProcessHealth()` (line 710), `hasCrashed()` (line 735, already a passive getter)
- `src/tickoni/runtime/tile.zig` — `TileHandle` (line 90), `TileState` (line 35), `CrashReason` (line 56)

---

## Target State (After Change)

One background thread per pipeline instance. Main thread is free. `hasCrashed()` is a pure getter that returns accurate state because the monitor updates it continuously.

---

## Task 1: Add monitor thread infrastructure to `Supervisor` struct

**File:** `src/app/tickoni/supervisor.zig`

Add two fields to the `Supervisor` struct (after `handles`):

```zig
pub const Supervisor = struct {
    allocator: std.mem.Allocator,
    topo: Topology,
    handles: []TileHandle,
    /// Non-null while a v2.14 process-mode pipeline is running.
    process_state: ?*ProcessState = null,
    /// Monitor thread that calls reap + health check periodically.
    /// Set to null before start, joined and freed in stopProcess.
    monitor_thread: ?std.Thread = null,
    ...
};
```

No structural changes to `TileHandle` are needed — the monitor writes `TileState` and `CrashReason` fields, the main thread reads them. Since only the monitor writes and only the main thread reads (no concurrent writes to the same handle), this is safe on x86-64 without atomics. On platforms where 32-bit writes are not atomic (e.g. ARM), `TileState` and `CrashReason` are small enums that fit in a single aligned word, so still safe.

---

## Task 2: Implement `monitor_loop` function

**File:** `src/app/tickoni/supervisor.zig`

Add a `fn monitorLoop(self: *Supervisor, io: std.Io) void` method. The loop:

1. Calls `reapExitedChildrenNoHang()` to collect exited children and update handles
2. Calls `refreshProcessHealth()` to check CNC heartbeats
3. Sleeps 5ms

Exits immediately when `process_state == null` (set by `stopProcess` before joining).

```zig
fn monitorLoop(self: *Supervisor, io: std.Io) void {
    const log = logger.get();
    log.enter("supervisor", "monitorLoop");
    defer log.exit("supervisor", "monitorLoop");

    while (self.process_state != null) {
        self.reapExitedChildrenNoHang();
        self.refreshProcessHealth();
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }
}
```

The `while (self.process_state != null)` check is the exit signal. `process_state` is set to `null` by `stopProcess` at the end of teardown, which the monitor thread sees on its next loop iteration.

**Thread safety note:** `process_state` is written by the main thread and read by the monitor. This is a single pointer write (8 bytes) that the monitor reads every loop iteration. On all target platforms (Linux x86-64, Linux ARM64, macOS), pointer-sized aligned writes are atomic. No mutex needed.

---

## Task 3: Launch monitor thread in `startPaymentPipelineProcess`

**File:** `src/app/tickoni/supervisor.zig`

After all tile processes are spawned (end of the `for (self.handles, 0..) |*h, i|` loop inside `startPaymentPipelineProcess`, after the CPU affinity block), launch the monitor thread:

```zig
// Launch the background monitor thread.
// If it fails to start, fail closed — do not run tiles without monitoring.
self.monitor_thread = try std.Thread.init();
errdefer self.monitor_thread = null;
try self.monitor_thread.?.init(.{ .name = "supervisor-monitor" }, self.monitorLoop);
```

This must come **after** all tile children are spawned and **before** `startPaymentPipelineProcess` returns. The errdefer ensures the thread field is cleaned up if anything after it fails.

---

## Task 4: Join and destroy monitor thread in `stopProcess`

**File:** `src/app/tickoni/supervisor.zig`

In `stopProcess`, **before** `process_state` is set to `null`, join the monitor thread so it exits its loop, then clear the field:

```zig
// StopProcess is called to tear down the pipeline.
// Join the monitor thread first so it stops updating handles,
// then null process_state, then tear down process_state.
if (self.monitor_thread) |*thread| {
    thread.join();
    self.monitor_thread = null;
}
```

Insert this right at the start of `stopProcess`, before `self.refreshProcessHealth()` (line 843 in the current file). The monitor thread must stop before the main thread proceeds with halt signals and force termination, so that handle state updates from the monitor don't race with the shutdown sequence.

Order in `stopProcess`:

1. **Join monitor thread** (new — stops monitor before shutdown)
2. `self.refreshProcessHealth()` (existing)
3. Stale detection and halt signaling (existing)
4. Force termination if needed (existing)
5. `waitProcess` (existing)
6. State normalization (existing)
7. `state.deinit` / destroy / null process_state (existing)

---

## Task 5: Verify `hasCrashed()` is a pure getter

**File:** `src/app/tickoni/supervisor.zig`

`hasCrashed()` (line 735) is already a passive getter — it only reads `self.handles` and returns `true` if any handle is `.crashed`. No changes needed. Confirm no side effects remain after Task 4 joins the monitor thread before shutdown.

Current implementation (no changes needed):

```zig
pub fn hasCrashed(self: *const Supervisor) bool {
    for (self.handles) |h| {
        if (h.state == .crashed) return true;
    }
    return false;
}
```

---

## Task 6: Update integration tests — remove manual reap calls

**File:** `src/tickoni/test/integration/test_process_shutdown_reap.zig`

Remove the `sup.reapExitedChildrenNoHang();` calls that were added in earlier patches:

- Test 1 (`non-zero exit before force-phase reap is preserved as crash`) — remove reap from wait loop
- Test 3 (`pre-existing crash survives stopProcess`) — remove reap from wait loop
- Test 6 (`HALT concurrent with tile failure retains crash evidence`) — remove reap from wait loop
- Test 7 (`non-zero exit during grace → force-phase preserves .exited_code`) — remove reap from wait loop

After the change, `hasCrashed()` returns accurate state without manual reap.

Also add a new test:

```zig
test "monitor thread starts and stops with pipeline" {
    // Verify the background monitor thread is launched on start
    // and joined on stop (no manual reap needed).
    const topo = topologies.paymentPipelineProcess();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    const run_dir = "/tmp/tickoni-test-monitor-thread";
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = 16,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    });

    // Monitor thread should be running.
    try std.testing.expect(sup.monitor_thread != null);

    // Poll for completion without manual reap.
    const max_polls: u32 = 400;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= 16) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }

    // Crash tkings (tile 0) via crash hook.
    var sup2 = try Supervisor.init(std.testing.allocator, topo);
    defer sup2.deinit();
    var crash_after: [8]u32 = std.mem.zeroes([8]u32);
    crash_after[0] = 1;
    try sup2.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = "/tmp/tickoni-test-monitor-crash",
        .event_count = 10,
        .crash_after_heartbeats = crash_after,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    });

    // Wait for crash detection — no manual reap needed.
    var poll2: u32 = 0;
    const max_polls2: u32 = 400;
    while (poll2 < max_polls2) : (poll2 += 1) {
        if (sup2.hasCrashed()) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }

    try std.testing.expectEqual(TileState.crashed, sup2.monitor()[0].state);
    try std.testing.expectEqual(@as(u8, 1), sup2.monitor()[0].exit_code);

    // stopProcess joins the monitor thread.
    sup2.stopProcess(std.testing.io);
    try std.testing.expect(sup2.monitor_thread == null);
}
```

---

## Task 7: Build and verify

Run:

```bash
just test-integration-tk
```

Expected: all 14 tests pass. The 4 crash-detection tests (1, 3, 6, 7) should pass **without** manual reap calls. The new monitor-thread test should pass.

---

## Verification Checklist

- [ ] `Supervisor` struct has `monitor_thread: ?std.Thread = null` field
- [ ] `monitorLoop` function runs reap → health → sleep loop, exits on `process_state == null`
- [ ] Monitor thread launched after all tiles spawn in `startPaymentPipelineProcess`
- [ ] Monitor thread joined before shutdown in `stopProcess`
- [ ] `hasCrashed()` is confirmed as a pure getter (no changes needed)
- [ ] Manual `reapExitedChildrenNoHang()` calls removed from tests 1, 3, 6, 7
- [ ] New test added: monitor thread lifecycle and crash detection without manual reap
- [ ] `just test-integration-tk` exits 0 with all 14 tests passing
- [ ] Thread name is `"supervisor-monitor"` for process listing visibility
- [ ] Build passes with `-Dtest=true` on supported platforms (Linux, macOS)

---

## Risks and Mitigations

| Risk | Mitigation |
| --- | --- |
| Monitor thread fails to start | Fail closed in `startPaymentPipelineProcess` — pipeline does not run if monitor cannot start |
| Monitor thread does not exit on `stopProcess` | Loop checks `process_state == null` each iteration; `stopProcess` sets it to null after joining monitor |
| Handle state race between monitor and main thread | Monitor writes handles, main thread reads — no concurrent writes to same handle |
| Monitor thread joins after `process_state` is nulled | Join monitor **before** setting `process_state = null` in `stopProcess` |

---

## Order of Operations

1. Task 1 — Add `monitor_thread` field
2. Task 2 — Implement `monitorLoop`
3. Task 3 — Launch monitor thread in `startPaymentPipelineProcess`
4. Task 4 — Join monitor thread in `stopProcess`
5. Task 5 — Verify `hasCrashed()` (no changes needed)
6. Task 6 — Update tests, add new test
7. Task 7 — Build and verify

Tasks 1-4 modify supervisor.zig. Task 6 modifies the integration test file. Task 7 runs the verification suite.
