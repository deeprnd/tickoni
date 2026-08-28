/// tkings: synthesizes payment events and publishes them to tknorm, with a
/// test-hook sandbox-failure edge that simulates the process-supervisor
/// crash path while the pipeline still runs in threads.
const std = @import("std");
const runtime = @import("runtime.zig");
const logger = @import("logger");

const PaymentPipelineState = runtime.PaymentPipelineState;

pub const tile_tkings: i32 = 0;

pub fn runIngest(state: *PaymentPipelineState) void {
    const log = logger.get();
    log.enter("tkings", "runIngest") catch {};
    defer log.exit("tkings", "runIngest") catch {};

    defer state.q_ing_norm.close();

    var offset: u64 = 0;
    while (offset < state.config.event_count) : (offset += 1) {
        if (state.stop.load(.acquire)) break;
        if (state.config.sandbox_fail_at) |fail_at| {
            if (offset == fail_at) {
                _ = state.sandbox_failures.fetchAdd(1, .release);
                state.crashed_tile.store(tile_tkings, .release);
                log.err("tkings", "runIngest", "sandbox failure triggered at offset") catch {};
                state.requestStop();
                break;
            }
        }

        const raw = runtime.syntheticPayment(state.config, offset);
        if (state.q_ing_norm.push(.{ .raw = raw, .pipeline_hops = 1 }, &state.stop)) |_| {
            _ = state.produced.fetchAdd(1, .release);
            log.debug("tkings", "runIngest", "produced event") catch {};
        } else |_| {
            log.debug("tkings", "runIngest", "queue full, stopping") catch {};
            break;
        }
    }
}

test "sandbox failure records crash diagnostics and stops ingest" {
    var state = try PaymentPipelineState.init(std.testing.allocator, .{ .event_count = 10, .queue_depth = 2, .sandbox_fail_at = 2 });
    defer state.deinit();
    runIngest(&state);
    const diag = state.snapshotDiag();
    try std.testing.expectEqual(tile_tkings, diag.crashed_tile);
    try std.testing.expectEqual(@as(u64, 1), diag.sandbox_failures);
    try std.testing.expect(state.stop.load(.seq_cst));
}
