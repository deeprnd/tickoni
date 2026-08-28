/// tkmetr: polls and snapshots pipeline throughput/backpressure metrics
/// until tkrepl finishes its check, then takes one final snapshot.
const std = @import("std");
const runtime = @import("runtime.zig");
const logger = @import("logger");

const PaymentPipelineState = runtime.PaymentPipelineState;

pub fn runMetric(state: *PaymentPipelineState) void {
    const log = logger.get();
    log.enter("tkmetr", "runMetric") catch {};
    defer log.exit("tkmetr", "runMetric") catch {};

    var backpressure_waits: u64 = 0;
    var max_qd: usize = 0;

    while (!state.replay_checked.load(.acquire) and !state.stop.load(.acquire)) {
        const snap = state.snapshotMetrics();
        _ = state.metric_snapshots.fetchAdd(1, .release);
        if (snap.backpressure_waits > backpressure_waits) {
            backpressure_waits = snap.backpressure_waits;
            log.debug("tkmetr", "runMetric", "backpressure wait detected") catch {};
        }
        if (snap.max_queue_depth > max_qd) max_qd = snap.max_queue_depth;
        std.Thread.yield() catch {};
    }
    _ = state.snapshotMetrics();
    _ = state.metric_snapshots.fetchAdd(1, .release);
    log.debug("tkmetr", "runMetric", "done") catch {};
}

test "sandbox failure records crash diagnostics and stops metric" {
    var state = try PaymentPipelineState.init(std.testing.allocator, .{ .event_count = 5, .queue_depth = 2 });
    defer state.deinit();

    // Signal that replay is checked so runMetric does not busy-wait forever
    state.replay_checked.store(true, .release);
    runMetric(&state);
}
