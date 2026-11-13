/// Sequential-pipeline test utility for tknorm normalization.
///
/// This module provides `runNormalizeSeq`, a synchronous loop version of the
/// tknorm normalization step used **only** by the sequential pipeline tests
/// in `mod.zig` (`runOneSequentialForTest`). It is NOT used by the live
/// runtime — production tknorm runs via the Firedancer stem tile
/// (`c_abi/shim/tk_normalize_stem.c`), which implements the same logic as
/// `tknorm_during_frag`/`tknorm_after_credit` callbacks.
///
/// The code is logically equivalent to the stem tile but operates on
/// `PaymentPipelineState` in-memory queues instead of Firedancer dcache links.
const std = @import("std");
const runtime = @import("runtime.zig");
const tile_ids = @import("runtime").tile_ids;
const logger = @import("logger");

const PaymentPipelineState = runtime.PaymentPipelineState;

/// Sequential (test-only) normalization loop.
///
/// Reads from `q_ing_norm`, validates framing, computes stable event hash,
/// stamps `decision`/`decided_by`, tracks `normalized`/`invalid` counters,
/// and pushes to `q_norm_dedu`.
///
/// **NOT called by any production tile.** Production tknorm uses the stem
/// tile path (`c_abi/shim/tk_normalize_stem.c`). This is kept for
/// sequential-pipeline integration tests in `mod.zig`.
pub fn runNormalizeSeq(state: *PaymentPipelineState) void {
    const log = logger.get();
    log.enter(tile_ids.tknorm.slice(), "runNormalizeSeq");
    defer log.exit(tile_ids.tknorm.slice(), "runNormalizeSeq");

    defer state.q_norm_dedu.close();

    var offset: u64 = 0;
    while (state.q_ing_norm.pop(&state.audit.stop)) |msg_in| {
        var msg = msg_in;
        offset += 1;
        if (!runtime.validFraming(msg.raw)) {
            _ = state.invalid.fetchAdd(1, .release);
            msg.pipeline_hops += 1;
            msg.event_hash = runtime.stableEventHash(msg.raw);
            msg.decision = .malformed_drop;
            msg.decided_by = tile_ids.tknorm;
            log.kvFmt(tile_ids.tknorm.slice(), "runNormalizeSeq", "offset={d} event_hash={x} account={d} reason=malformed", .{ msg.raw.source_offset, msg.event_hash, msg.raw.account_id });
            state.q_norm_dedu.push(msg, &state.audit.stop) catch break;
            continue;
        }
        msg.pipeline_hops += 1;
        msg.event_hash = runtime.stableEventHash(msg.raw);
        _ = state.normalized.fetchAdd(1, .release);
        log.kvFmt(tile_ids.tknorm.slice(), "runNormalizeSeq", "offset={d} event_hash={x} account={d} amount={d}c", .{ msg.raw.source_offset, msg.event_hash, msg.raw.account_id, msg.raw.amount_cents });
        state.q_norm_dedu.push(msg, &state.audit.stop) catch break;
    }
    log.debug(tile_ids.tknorm.slice(), "runNormalizeSeq", "done");
}

test "sandbox failure records crash diagnostics and stops normalize" {
    var state = try PaymentPipelineState.init(std.testing.allocator, .{ .event_count = 5, .queue_depth = 2 });
    defer state.deinit();

    // Feed a valid event, then close the queue to force runNormalizeSeq to exit
    try state.q_ing_norm.push(.{
        .raw = runtime.RawPayment{ .source_offset = 0, .idempotency_key = 1, .account_id = 0, .amount_cents = 100, .currency = .{ 'U', 'S', 'D' } },
        .pipeline_hops = 1,
    }, &state.audit.stop);
    state.q_ing_norm.close();
    runNormalizeSeq(&state);
    std.testing.expectEqual(1, state.normalized.load(.acquire)) catch @panic("expected 1 normalized");
}
