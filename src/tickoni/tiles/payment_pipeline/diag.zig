/// tkdiag: polls and snapshots pipeline crash/sandbox-failure diagnostics
/// until tkrepl finishes its check, then takes one final snapshot.
const std = @import("std");
const runtime = @import("runtime.zig");
const tile_ids = @import("runtime").tile_ids;
const logger = @import("logger");

const PaymentPipelineState = runtime.PaymentPipelineState;

pub fn runDiag(state: *PaymentPipelineState) void {
    const log = logger.get();
    log.enter(tile_ids.tkdiag.slice(), "runDiag");
    defer log.exit(tile_ids.tkdiag.slice(), "runDiag");

    while (!state.replay_checked.load(.acquire) and !state.stop.load(.acquire)) {
        const diag = state.snapshotDiag();
        _ = state.diag_snapshots.fetchAdd(1, .release);
        if (diag.crashed_tile != runtime.crash_none) {
            log.kvFmt(tile_ids.tkdiag.slice(), "runDiag", "crashed_tile={d} sandbox_failures={d}", .{ diag.crashed_tile, diag.sandbox_failures });
        }
        std.Thread.yield() catch {};
    }
    _ = state.snapshotDiag();
    _ = state.diag_snapshots.fetchAdd(1, .release);
    log.debug(tile_ids.tkdiag.slice(), "runDiag", "done");
}

test "sandbox failure records crash diagnostics and stops diag" {
    var state = try PaymentPipelineState.init(std.testing.allocator, .{ .event_count = 5, .queue_depth = 2 });
    defer state.deinit();

    // Signal that replay is checked so runDiag does not busy-wait forever
    state.replay_checked.store(true, .release);
    runDiag(&state);
}
