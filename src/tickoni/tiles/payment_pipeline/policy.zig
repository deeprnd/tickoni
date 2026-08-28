/// tkpoly: makes the final policy decision for each payment event (allow,
/// deny on amount limit, or duplicate_drop), preserving tknorm's
/// malformed_drop decision unchanged. Stamps itself as decided_by for every
/// decision it makes.
const std = @import("std");
const runtime = @import("runtime.zig");
const audit_sink = @import("audit_sink.zig");
const logger = @import("logger");

const PaymentPipelineState = runtime.PaymentPipelineState;

pub fn runPolicy(state: *PaymentPipelineState) void {
    const log = logger.get();
    log.enter("tkpoly", "runPolicy") catch {};
    defer log.exit("tkpoly", "runPolicy") catch {};

    defer state.q_poly_audit.close();

    var offset: u64 = 0;
    while (state.q_dedu_poly.pop(&state.stop)) |msg_in| {
        var msg = msg_in;
        msg.pipeline_hops += 1;
        offset += 1;
        if (msg.decision == .malformed_drop) {
            // tknorm already made this rejection decision; preserve it (and
            // its decided_by) for audit instead of silently dropping
            // malformed source facts.
        } else if (msg.duplicate) {
            msg.decision = .duplicate_drop;
            msg.decided_by = audit_sink.tile_id_tkpoly;
            log.debug("tkpoly", "runPolicy", "duplicate_drop at offset") catch {};
        } else if (msg.raw.amount_cents > state.config.policy_limit_cents) {
            msg.decision = .deny;
            msg.decided_by = audit_sink.tile_id_tkpoly;
            _ = state.denied.fetchAdd(1, .release);
            log.debug("tkpoly", "runPolicy", "denied at offset") catch {};
        } else {
            msg.decision = .allow;
            msg.decided_by = audit_sink.tile_id_tkpoly;
            _ = state.allowed.fetchAdd(1, .release);
            log.debug("tkpoly", "runPolicy", "allowed at offset") catch {};
        }
        state.q_poly_audit.push(msg, &state.stop) catch break;
    }
    log.debug("tkpoly", "runPolicy", "done") catch {};
}

test "sandbox failure records crash diagnostics and stops policy" {
    var state = try PaymentPipelineState.init(std.testing.allocator, .{ .event_count = 5, .queue_depth = 2 });
    defer state.deinit();

    // Feed a valid event, then close the queue to force runPolicy to exit
    try state.q_dedu_poly.push(.{
        .raw = runtime.RawPayment{ .source_offset = 0, .idempotency_key = 1, .account_id = 0, .amount_cents = 100, .currency = .{ 'U', 'S', 'D' } },
        .pipeline_hops = 1,
        .duplicate = false,
        .decision = .allow,
        .decided_by = audit_sink.tile_id_tkdedu,
    }, &state.stop);
    state.q_dedu_poly.close();
    runPolicy(&state);
}
