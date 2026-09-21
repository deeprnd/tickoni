/// v2.14.S1 T14 process-mode metrics integration: snapshotProcessMetrics()
/// aggregates counters from every tile in the 2-tile topology
/// (tkings producer -> tkaudt consumer) and snapshotProcessMetricsForTile()
/// isolates per-tile counters.  Also exercises snapshotProcessMetricsWithTime()
/// to verify the timestamped path used by periodic sampling.
const std = @import("std");
const rt = @import("runtime");
const supervisor_mod = @import("supervisor");
const util = @import("util");
const topologies = @import("topologies");

const Supervisor = supervisor_mod.Supervisor;

/// Run the pipeline until completion.  The caller owns the returned
/// Supervisor and must call `stopProcess` + `deinit` when done.
fn runAndWait(
    io: std.Io,
    event_count: u64,
    inject_duplicate: bool,
    inject_malformed: bool,
) !struct {
    sup: *Supervisor,
    metrics: Supervisor.ProcessMetricSnapshot,
} {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.paymentPipelineProcess();
    var sup_ptr = try std.testing.allocator.create(Supervisor);
    errdefer std.testing.allocator.destroy(sup_ptr);
    sup_ptr.* = try Supervisor.init(std.testing.allocator, topo);

    try sup_ptr.startPaymentPipelineProcess(io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .inject_duplicate = inject_duplicate,
        .inject_malformed = inject_malformed,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
    });

    const max_polls: u32 = 400; // 2s bound at 5ms per poll
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup_ptr.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }

    return .{ .sup = sup_ptr, .metrics = sup_ptr.snapshotProcessMetrics() };
}

test "process_metrics_integration: snapshotProcessMetrics aggregates all tile counters correctly" {
    const result = try runAndWait(std.testing.io, 32, true, false);
    defer {
        result.sup.stopProcess(std.testing.io);
        result.sup.deinit();
        std.testing.allocator.destroy(result.sup);
    }

    const m = result.metrics;
    // Full throughput: every event produced, normalized, audited.
    try std.testing.expectEqual(@as(u64, 32), m.produced);
    try std.testing.expectEqual(@as(u64, 32), m.normalized);
    try std.testing.expectEqual(@as(u64, 32), m.audited);
    // No invalid events (all payloads are well-formed).
    try std.testing.expectEqual(@as(u64, 0), m.invalid);
    // One duplicate (offset 3 duplicates offset 1's idempotency key).
    try std.testing.expectEqual(@as(u64, 1), m.duplicates);
    // One denied (offset 7 exceeds default policy_limit_cents).
    try std.testing.expectEqual(@as(u64, 1), m.denied);
    // Allowed = produced - denied = 30.
    try std.testing.expectEqual(@as(u64, 30), m.allowed);
    // Conservation: produced == audited (every event reaches audit).
    try std.testing.expectEqual(m.produced, m.audited);
    // Audit count == allowed + denied (the audit path records both).
    try std.testing.expectEqual(m.allowed + m.denied, m.audited);
}

test "process_metrics_integration: per-tile counters split correctly between producer and consumer" {
    const result = try runAndWait(std.testing.io, 32, true, false);
    defer {
        result.sup.stopProcess(std.testing.io);
        result.sup.deinit();
        std.testing.allocator.destroy(result.sup);
    }

    const topo = topologies.paymentPipelineProcess();
    // Tile 0 = tkings (producer), tile 1 = tkaudt (consumer).
    try std.testing.expectEqualStrings("tkings", topo.tiles[0].id.slice());
    try std.testing.expectEqualStrings("tkaudt", topo.tiles[1].id.slice());

    // Producer should have produced all events and normalized them all.
    const prod_snap = try result.sup.snapshotProcessMetricsForTile(0);
    try std.testing.expectEqual(@as(u64, 32), prod_snap.produced);
    try std.testing.expectEqual(@as(u64, 32), prod_snap.normalized);
    // Producer does not audit — that's the consumer's job.
    try std.testing.expectEqual(@as(u64, 0), prod_snap.audited);

    // Consumer should have received all events and audited all of them.
    const cons_snap = try result.sup.snapshotProcessMetricsForTile(1);
    try std.testing.expectEqual(@as(u64, 32), cons_snap.audited);
    // Consumer sees the deduped/denied counts from its own policy check.
    try std.testing.expectEqual(@as(u64, 1), cons_snap.duplicates);
    try std.testing.expectEqual(@as(u64, 1), cons_snap.denied);
    try std.testing.expectEqual(@as(u64, 30), cons_snap.allowed);
    // Consumer's produced/normalized are set by the producer, so they reflect
    // the global values read from cnc counters (which are per-tile).
    _ = cons_snap.produced; // consumer doesn't produce
    _ = cons_snap.normalized; // consumer doesn't normalize

    // Aggregate of per-tile snapshots must match the combined snapshot.
    const combined = result.metrics;
    try std.testing.expectEqual(combined.audited, cons_snap.audited);
    try std.testing.expectEqual(combined.duplicates, cons_snap.duplicates);
    try std.testing.expectEqual(combined.denied, cons_snap.denied);
    try std.testing.expectEqual(combined.allowed, cons_snap.allowed);
}

test "process_metrics_integration: snapshotProcessMetricsWithTime carries epoch timestamp" {
    const result = try runAndWait(std.testing.io, 8, true, false);
    defer {
        result.sup.stopProcess(std.testing.io);
        result.sup.deinit();
        std.testing.allocator.destroy(result.sup);
    }

    const snapped = result.sup.snapshotProcessMetricsWithTime();
    try std.testing.expectEqual(@as(u64, 8), snapped.produced);
    try std.testing.expectEqual(@as(u64, 8), snapped.audited);
    // Epoch must be non-zero (set at snapshot time).
    try std.testing.expect(snapped.epoch_ns > 0);
    // All metric fields must match the plain snapshot.
    const plain = result.sup.snapshotProcessMetrics();
    try std.testing.expectEqual(plain.produced, snapped.produced);
    try std.testing.expectEqual(plain.normalized, snapped.normalized);
    try std.testing.expectEqual(plain.invalid, snapped.invalid);
    try std.testing.expectEqual(plain.duplicates, snapped.duplicates);
    try std.testing.expectEqual(plain.allowed, snapped.allowed);
    try std.testing.expectEqual(plain.denied, snapped.denied);
    try std.testing.expectEqual(plain.audited, snapped.audited);
}

test "process_metrics_integration: metrics are consistent with different event counts and injection modes" {
    const counts: []const u64 = &.{8, 16, 64};

    for (counts) |event_count| {
        const result = try runAndWait(std.testing.io, event_count, true, false);
        defer {
            result.sup.stopProcess(std.testing.io);
            result.sup.deinit();
            std.testing.allocator.destroy(result.sup);
        }

        const m = result.metrics;
        // Produced and normalized must always match the event count.
        try std.testing.expectEqual(event_count, m.produced);
        try std.testing.expectEqual(event_count, m.normalized);
        try std.testing.expectEqual(event_count, m.audited);
        // No invalid events when malformed injection is off.
        try std.testing.expectEqual(@as(u64, 0), m.invalid);
        // At least one duplicate for event_count >= 4 (offset 3 duplicates offset 1).
        try std.testing.expect(m.duplicates >= 1);
        // Audit = produced (every event reaches audit).
        try std.testing.expectEqual(m.produced, m.audited);
    }
}

test "process_metrics_integration: malformed input increments invalid counter" {
    const result = try runAndWait(std.testing.io, 8, false, true);
    defer {
        result.sup.stopProcess(std.testing.io);
        result.sup.deinit();
        std.testing.allocator.destroy(result.sup);
    }

    const m = result.metrics;
    // All events produced/normalized regardless of validity.
    try std.testing.expectEqual(@as(u64, 8), m.produced);
    try std.testing.expectEqual(@as(u64, 8), m.normalized);
    // Malformed injection ensures at least one invalid event.
    try std.testing.expect(m.invalid > 0);
    // Invalid events should not be allowed.
    try std.testing.expectEqual(@as(u64, 0), m.allowed);
    // Invalid + denied should account for all events (no allowed).
    try std.testing.expectEqual(m.invalid + m.denied, m.audited);
}
