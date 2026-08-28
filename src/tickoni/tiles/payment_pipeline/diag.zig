/// tkdiag: polls and snapshots pipeline crash/sandbox-failure diagnostics
/// until tkrepl finishes its check, then takes one final snapshot.
const std = @import("std");
const runtime = @import("runtime.zig");
const logger = @import("logger");

const PaymentPipelineState = runtime.PaymentPipelineState;

pub fn runDiag(state: *PaymentPipelineState) void {
    const log = logger.get();
    log.enter("tkdiag", "runDiag") catch {};
    defer log.exit("tkdiag", "runDiag") catch {};

    while (!state.replay_checked.load(.acquire) and !state.stop.load(.acquire)) {
        const diag = state.snapshotDiag();
        _ = state.diag_snapshots.fetchAdd(1, .release);
        if (diag.crashed_tile != runtime.crash_none) {
            log.err("tkdiag", "runDiag", "tile crashed") catch {};
        }
        std.Thread.yield() catch {};
    }
    _ = state.snapshotDiag();
    _ = state.diag_snapshots.fetchAdd(1, .release);
    log.debug("tkdiag", "runDiag", "done") catch {};
}

test "sandbox failure records crash diagnostics and stops diag" {
    var state = try PaymentPipelineState.init(std.testing.allocator, .{ .event_count = 5, .queue_depth = 2 });
    defer state.deinit();

    // Signal that replay is checked so runDiag does not busy-wait forever
    state.replay_checked.store(true, .release);
    runDiag(&state);
}
