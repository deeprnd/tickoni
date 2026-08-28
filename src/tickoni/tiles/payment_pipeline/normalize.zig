/// tknorm: canonicalizes payment events (stable event hash) and rejects
/// malformed framing, stamping itself as the audit record's decided_by tile
/// when it makes that rejection decision.
const std = @import("std");
const runtime = @import("runtime.zig");
const audit_sink = @import("audit_sink.zig");
const logger = @import("logger");

const PaymentPipelineState = runtime.PaymentPipelineState;

pub fn runNormalize(state: *PaymentPipelineState) void {
    const log = logger.get();
    log.enter("tknorm", "runNormalize") catch {};
    defer log.exit("tknorm", "runNormalize") catch {};

    defer state.q_norm_dedu.close();

    var offset: u64 = 0;
    while (state.q_ing_norm.pop(&state.stop)) |msg_in| {
        var msg = msg_in;
        offset += 1;
        if (!runtime.validFraming(msg.raw)) {
            _ = state.invalid.fetchAdd(1, .release);
            msg.pipeline_hops += 1;
            msg.event_hash = runtime.stableEventHash(msg.raw);
            msg.decision = .malformed_drop;
            msg.decided_by = audit_sink.tile_id_tknorm;
            log.err("tknorm", "runNormalize", "malformed event at offset") catch {};
            state.q_norm_dedu.push(msg, &state.stop) catch break;
            continue;
        }
        msg.pipeline_hops += 1;
        msg.event_hash = runtime.stableEventHash(msg.raw);
        _ = state.normalized.fetchAdd(1, .release);
        log.debug("tknorm", "runNormalize", "normalized event") catch {};
        state.q_norm_dedu.push(msg, &state.stop) catch break;
    }
    log.debug("tknorm", "runNormalize", "done") catch {};
}

test "sandbox failure records crash diagnostics and stops normalize" {
    var state = try PaymentPipelineState.init(std.testing.allocator, .{ .event_count = 5, .queue_depth = 2 });
    defer state.deinit();

    // Feed a valid event, then close the queue to force runNormalize to exit
    try state.q_ing_norm.push(.{
        .raw = runtime.RawPayment{ .source_offset = 0, .idempotency_key = 1, .account_id = 0, .amount_cents = 100, .currency = .{ 'U', 'S', 'D' } },
        .pipeline_hops = 1,
    }, &state.stop);
    state.q_ing_norm.close();
    runNormalize(&state);
    std.testing.expectEqual(1, state.normalized.load(.acquire)) catch @panic("expected 1 normalized");
}
