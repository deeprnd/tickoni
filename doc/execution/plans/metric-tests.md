Looking at the test file, the metric tile code, and the debugging patterns from your firedancer-tile-debugging skill, here's the diagnosis and suggested tests.

What's Wrong With the Current Tests

All three failing tests (boot_timestamp, /metrics 200, 404) funnel through the same bottleneck: the Python HTTP subprocess. If any part of the chain breaks — HTTP server bind, tile crash, workspace join failure, CNC corruption, supervisor CNC read — they all produce the same ConnectionTimeout error. There's no way to distinguish between them.

The current test suite is 90% HTTP-dependent. The metric tile does many things beyond serving HTTP, and those non-HTTP behaviors are the ones that would let you pinpoint where it actually fails.

Tests to Add (Ordered by Diagnostic Value)

1. Scratch footprint determinism (no HTTP, no pipeline)
- Build topology twice, compare scratch_footprint, scratch_align, and cnc_obj_id via C API
- Verifies: topology rebuild produces identical scratch layout (catches NULL+offset crashes later)
- Diagnostic power: If this fails, the tile will crash on any boot attempt regardless of HTTP

2. CNC object join verification at boot (no HTTP, no pipeline)
- After privileged_init, verify ctx->cnc is non-NULL (tile found its CNC)
- This requires instrumenting tk_metric_unprivileged_init or adding a supervisor hook to read cnc_obj_id from shared memory after tile boot
- Diagnostic power: If CNC is NULL, tile will never detect HALT and never serve HTTP. Distinguishes "tile didn't boot" from "HTTP didn't bind"

3. Boot timestamp in metrics context (no HTTP, reads shared memory)
- After pipeline completes, supervisor reads ctx->boot_ts directly from the metric tile's scratch region
- Verify it's a large positive nanosecond timestamp (not 0, not negative, not stale from prior run)
- Diagnostic power: If timestamp is 0, unprivileged_init never ran → tile crashed in privileged_init → HTTP never started. If timestamp is valid but HTTP fails → HTTP bind issue specifically.

4. Metrics counter writes to shared memory (no HTTP, reads CNC/metrics)
- After pipeline completes with N events, supervisor reads metric_bytes_read counter directly from shared memory (CNC or metrics object)
- Verify it's > 0 and scales with event count
- Diagnostic power: If counter is 0 but tile didn't crash → tile is alive but not polling/processing. If counter is > 0 but HTTP fails → HTTP subsystem is the only problem. This is the single most discriminative test.

5. Shutdown signal propagation (no HTTP, writes CNC)
- Supervisor sends HALT via CNC after pipeline completes
- Verify tile exits cleanly (exit code 0, not SIGSEGV/SIGABRT)
- Check that ctx->cnc was set (if we can read it)
- Diagnostic power: If tile doesn't respond to HALT, ctx->cnc is NULL → boot-time CNC join failure. If it does respond → tile lifecycle works, only HTTP is broken.

6. Workspace join completeness (no HTTP, inspect workspaces)
- After tile boot, verify tile joined all workspaces it declared in topology
- Check that wksp pointers are non-NULL for each workspace in topo->workspaces referenced by the tile
- Diagnostic power: If a workspace is unjoined, any access to objects in that workspace produces NULL+offset crash. This is the #1 cause of silent tile failures that look like HTTP issues.

7. Multiple sequential pipeline runs (integration stress)
- Run the same topology 3 times in a row on the same port
- Verify each run completes and counters reset correctly
- Diagnostic power: If run 2 or 3 fails → stale workspace files or CNC object collision. If only run 1 fails → initial bind issue.

8. Port conflict detection
- Start two pipeline instances on the same port
- Verify one fails to bind HTTP and the other continues serving
- Diagnostic power: If both crash → tile treats bind failure as fatal. If only one fails gracefully → tile handles it. If neither starts → workspace/CNC issue, not HTTP.

9. Tile health via heartbeat (supervisor-side, no HTTP)
- During pipeline run, verify metric tile heartbeats in CNC at regular intervals
- If no heartbeats for N ms, tile is stuck/crashed
- Diagnostic power: Distinguishes "tile is alive but not processing" from "tile crashed" from "HTTP server not ready"

10. Metrics before_credit polling (no HTTP, verify loop runs)
- After boot, verify that metric_snapshots (or equivalent counter) increments in the CNC during pipeline execution
- Diagnostic power: metric_snapshots increments in before_credit which is called every stem_run iteration. If it increments but HTTP fails → HTTP is isolated. If it doesn't increment → before_credit never runs → stem_run never entered or ctx->cnc is NULL.

Priority Order for Implementation

1. #4 (counter writes) — highest discriminative power. Takes 15 minutes. Tells you if the tile is alive and processing.
2. #3 (boot timestamp in scratch) — tells you if unprivileged_init ran. Takes 15 minutes.
3. #2 (CNC join verification) — tells you if shutdown will work. Takes 10 minutes.
4. #9 (heartbeat) — tells you if the tile is stuck. Takes 10 minutes.
5. #6 (workspace join) — tells you if NULL+offset crashes are possible. Takes 20 minutes.

Once you have tests 4, 3, and 2, you can answer every failure mode without touching HTTP at all:

- Counter 0 + timestamp 0 → crash in privileged_init
- Counter 0 + timestamp > 0 → crash in unprivileged_init or stem_run never entered
- Counter > 0 + timestamp > 0 → tile is alive and processing, HTTP is the only problem
- No heartbeats → tile deadlocked in init

The HTTP tests become a narrow diagnosis of "why isn't the HTTP server responding when we know the tile is alive" instead of "why did everything fail."

Want me to write any of these tests?
╰─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯

────────────────────────────────────────
● which ones of the suggested tests already covered by the integration infra lane?
────────────────────────────────────────

  ┊ 🔎 preparing search_files…
  ┊ 🔎 grep      test ".*integration  0.0s
  ┊ 🔎 find      snapshotProcessMetrics|snapshotProcessMetricsForTile  0.0s
  ┊ 🔎 preparing search_files…
  ┊ 📖 preparing read_file…
  ┊ 🔎 grep      snapshotProcessMetrics|snapshotProcess  0.1s
  ┊ 📖 read      test_process_topology.zig  0.0s

╭─ ☤ Hermes ──────────────────────────────────────────────────────────────────────────────────────╮
Now let me check what snapshotProcessMetrics actually returns and what fields are already exposed:

Based on my review of the existing test suite and supervisor infrastructure, here's the mapping:

Already Covered

Suggested Test: 1. Scratch footprint determinism
Status: ✅ Covered
Evidence: test "metric topology finalizes exact scratch requirements identically" (line 240) —
  builds parent+child, compares footprint/align/offset/validate
────────────────────────────────────────
Suggested Test: 2. CNC object join
Status: ✅ Covered
Evidence: test "CNC join verifies tile finds CNC object" (line 648) + test "metric topology
  preserves descriptor identity, CNC ownership..." (line 314) — checks topoTileInputCount,
  topoTileOutputCount, topoLinkConsumerCount
────────────────────────────────────────
Suggested Test: 5. Shutdown signal propagation
Status: ✅ Covered
Evidence: test "CNC shutdown signal stops tile cleanly" (line 603) — sends HALT via CNC, verifies
  clean exit
────────────────────────────────────────
Suggested Test: 9. Tile health via heartbeat
Status: ✅ Covered
Evidence: test "supervisor marks a truly stuck tile stale..." in test_process_topology.zig (line
  65) — validates stale detection, heartbeat mechanism, and that blocked consumers keep
  heartbeating
────────────────────────────────────────
Suggested Test: 10. Metrics before_credit polling
Status: ✅ Covered
Evidence: ProcessMetricSnapshot.metric_snapshots is already a CNC counter read by
  snapshotProcessMetrics(). All pipeline tests call it. The supervisor already reads
  metric_snapshots` from the metric tile's CNC every poll.

Partially Covered

Suggested Test: 4. Metrics counter writes to shared memory
Status: ⚠️ Partially
Evidence: metric_snapshots and metric_backpressure_waits are already exposed as CNC counters. But
  metric_bytes_read is NOT exposed — it only appears in the Prometheus HTTP output, not as a CNC
  counter. The supervisor can tell you the tile is alive and polling (via metric_snapshots), but
  not how many bytes it consumed.

NOT Covered (still need to add)

#: 3. Boot timestamp in scratch - implemented, verifying
Test: Currently only read via HTTP. Supervisor has no path to read ctx->boot_ts from shared
  memory.
Why It's Missing:
────────────────────────────────────────
#: 6. Workspace join completeness
Test: Tests verify link counts and CNC existence, but nothing checks that every workspace the
  tile declares is actually joined. A NULL+offset crash wouldn't be caught until runtime.
Why It's Missing:
────────────────────────────────────────
#: 7. Multiple sequential pipeline runs
Test: Each test uses a fresh port, but no test runs the same topology 3 times in a row on the
  same port to catch stale workspace/CNC collision.
Why It's Missing:
────────────────────────────────────────
#: 8. Port conflict detection
Test: No test starts two pipelines on the same port. Doesn't tell you if the tile handles bind
  failure gracefully vs fatally.
Why It's Missing:

The One Missing Piece With Immediate Diagnostic Value

metric_bytes_read as a CNC counter (extends #4). Currently the only way to verify the tile consumed events is HTTP. If you add metric_bytes_read to the CNC counter table in tile_registry.zig, then every pipeline test already has a non-HTTP way to verify:

zig
// In tile_registry.zig's metric tile counters:
.{ .name = "metric_bytes_read", .idx = ... }


Then in any existing test, after snapshotProcessMetrics():
zig
try std.testing.expect(metrics.metric_bytes_read > 0);


This single addition turns 5 existing tests into diagnostic tools that can distinguish "tile crashed in boot" from "HTTP bind failed" without any new test code.

Bottom line: 5/10 are covered. 1/10 is partially covered. Only 4 truly new tests are needed, and the highest-value one (#3 — boot timestamp) is the most invasive because it requires supervisor-side shared memory reads. The easiest win is just exposing metric_bytes_read as a CNC counter — 5 lines of change that makes all existing pipeline tests diagnostic.
