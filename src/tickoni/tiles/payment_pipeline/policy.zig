/// tkpoly: makes the final policy decision for each payment event (allow,
/// deny on amount limit, or duplicate_drop), preserving tknorm's
/// malformed_drop decision unchanged. Stamps itself as decided_by for every
/// decision it makes.
const std = @import("std");
const runtime = @import("runtime.zig");
const tile_ids = @import("runtime").tile_ids;
const logger = @import("logger");
const c_abi = @import("c_abi");

const PaymentPipelineState = runtime.PaymentPipelineState;

/// The decision chain is intentionally small and side-effect free so the
/// process and stem implementations can prove the same financial result.
pub fn decide(
    incoming: runtime.PolicyDecision,
    is_duplicate: bool,
    amount_cents: i64,
    policy_limit_cents: i64,
) runtime.PolicyDecision {
    if (incoming == .malformed_drop) return .malformed_drop;
    if (is_duplicate) return .duplicate_drop;
    if (amount_cents > policy_limit_cents) return .deny;
    return .allow;
}

pub fn runPolicy(state: *PaymentPipelineState) void {
    const log = logger.get();
    log.enter(tile_ids.tkpoly.slice(), "runPolicy");
    defer log.exit(tile_ids.tkpoly.slice(), "runPolicy");

    defer state.q_poly_audit.close();

    var offset: u64 = 0;
    while (state.q_dedu_poly.pop(&state.audit.stop)) |msg_in| {
        var msg = msg_in;
        msg.pipeline_hops += 1;
        offset += 1;
        const decision = decide(msg.decision, msg.duplicate, msg.raw.amount_cents, state.config.policy_limit_cents);
        if (decision == .malformed_drop) {
            // tknorm already made this rejection decision; preserve it (and
            // its decided_by) for audit instead of silently dropping
            // malformed source facts.
        } else if (decision == .duplicate_drop) {
            msg.decision = decision;
            msg.decided_by = tile_ids.tkpoly;
            log.kvFmt(tile_ids.tkpoly.slice(), "runPolicy", "offset={d} decision=duplicate_drop account={d} idempotency_key={d}", .{ msg.raw.source_offset, msg.raw.account_id, msg.raw.idempotency_key });
        } else if (decision == .deny) {
            msg.decision = decision;
            msg.decided_by = tile_ids.tkpoly;
            _ = state.denied.fetchAdd(1, .release);
            log.kvFmt(tile_ids.tkpoly.slice(), "runPolicy", "offset={d} decision=deny account={d} amount={d}c limit={d}c", .{ msg.raw.source_offset, msg.raw.account_id, msg.raw.amount_cents, state.config.policy_limit_cents });
        } else {
            msg.decision = decision;
            msg.decided_by = tile_ids.tkpoly;
            _ = state.allowed.fetchAdd(1, .release);
            log.kvFmt(tile_ids.tkpoly.slice(), "runPolicy", "offset={d} decision=allow account={d} amount={d}c", .{ msg.raw.source_offset, msg.raw.account_id, msg.raw.amount_cents });
        }
        state.q_poly_audit.push(msg, &state.audit.stop) catch break;
    }
    log.debug(tile_ids.tkpoly.slice(), "runPolicy", "done");
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
        .decided_by = tile_ids.tkdedu,
    }, &state.audit.stop);
    state.q_dedu_poly.close();
    runPolicy(&state);
}

test "C policy helper preserves the Zig decision chain for signed boundaries" {
    const Case = struct {
        incoming: runtime.PolicyDecision,
        duplicate: bool,
        amount_cents: i64,
        policy_limit_cents: i64,
    };
    const cases = [_]Case{
        .{ .incoming = .malformed_drop, .duplicate = true, .amount_cents = std.math.maxInt(i64), .policy_limit_cents = std.math.minInt(i64) },
        .{ .incoming = .allow, .duplicate = true, .amount_cents = std.math.maxInt(i64), .policy_limit_cents = std.math.minInt(i64) },
        .{ .incoming = .allow, .duplicate = false, .amount_cents = 999, .policy_limit_cents = 1000 },
        .{ .incoming = .allow, .duplicate = false, .amount_cents = 1000, .policy_limit_cents = 1000 },
        .{ .incoming = .allow, .duplicate = false, .amount_cents = 1001, .policy_limit_cents = 1000 },
        .{ .incoming = .allow, .duplicate = false, .amount_cents = -1, .policy_limit_cents = 0 },
        .{ .incoming = .allow, .duplicate = false, .amount_cents = std.math.minInt(i64), .policy_limit_cents = std.math.maxInt(i64) },
        .{ .incoming = .allow, .duplicate = false, .amount_cents = std.math.maxInt(i64), .policy_limit_cents = std.math.minInt(i64) },
    };

    for (cases) |case| {
        const zig_outcome = decide(case.incoming, case.duplicate, case.amount_cents, case.policy_limit_cents);
        try std.testing.expectEqual(
            auditOutcome(zig_outcome),
            c_abi.tkpoly.policyOutcome(
                auditOutcome(case.incoming),
                case.duplicate,
                case.amount_cents,
                case.policy_limit_cents,
            ),
        );
    }
}

fn auditOutcome(decision: runtime.PolicyDecision) u8 {
    return switch (decision) {
        .allow => 0,
        .deny => 1,
        .malformed_drop => 3,
        .duplicate_drop => 4,
    };
}
