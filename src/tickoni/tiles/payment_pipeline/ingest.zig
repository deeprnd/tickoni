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
    log.enter("tkings", "runIngest");
    defer log.exit("tkings", "runIngest");

    defer state.q_ing_norm.close();

    var offset: u64 = 0;
    while (offset < state.config.event_count) : (offset += 1) {
        if (state.stop.load(.acquire)) break;
        // Test-only sandbox-failure hook. @import("builtin").is_test is a
        // compile-time constant; when false the entire inner branch is dead
        // code eliminated.
        if (@import("builtin").is_test) {
            if (state.config.sandbox_fail_hook) |hook| {
                hook(offset, state);
            }
        }

        const raw = runtime.syntheticPayment(state.config, offset);
        if (state.q_ing_norm.push(.{ .raw = raw, .pipeline_hops = 1 }, &state.stop)) |_| {
            _ = state.produced.fetchAdd(1, .release);
            log.kvFmt("tkings", "runIngest", "offset={d} account={d} amount={d}c", .{ offset, raw.account_id, raw.amount_cents });
        } else |_| {
            log.kvFmt("tkings", "runIngest", "offset={d} reason=queue_full", .{offset});
            break;
        }
    }
}

test "sandbox failure records crash diagnostics and stops ingest" {
    const hook = struct {
        pub fn trigger(offset: u64, state: *PaymentPipelineState) callconv(.c) void {
            if (offset == 2) {
                _ = state.sandbox_failures.fetchAdd(1, .release);
                state.crashed_tile.store(tile_tkings, .release);
                state.requestStop();
            }
        }
    }.trigger;
    var state = try PaymentPipelineState.init(std.testing.allocator, .{ .event_count = 10, .queue_depth = 2, .sandbox_fail_hook = &hook });
    defer state.deinit();
    runIngest(&state);
    const diag = state.snapshotDiag();
    try std.testing.expectEqual(tile_tkings, diag.crashed_tile);
    try std.testing.expectEqual(@as(u64, 1), diag.sandbox_failures);
    try std.testing.expect(state.stop.load(.seq_cst));
}
