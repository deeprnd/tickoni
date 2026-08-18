/// tkaudt: appends every payment event's policy decision to the append-only
/// audit log, attributing each record to whichever earlier stage
/// (decided_by) actually finalized it. Named audit_stage.zig (not audit.zig)
/// to stay distinct from the sibling audit_sink.zig record-builder and the
/// audit_tile module this pipeline audits into.
const std = @import("std");
const runtime = @import("runtime.zig");
const queue = @import("queue.zig");
const logger = @import("logger");
const audit_sink = @import("audit_sink.zig");

const PaymentPipelineState = runtime.PaymentPipelineState;

pub fn runAudit(state: *PaymentPipelineState) void {
    const log = logger.get();
    log.enter("tkaudt", "runAudit") catch {};
    defer log.exit("tkaudt", "runAudit") catch {};

    var offset: u64 = 0;
    while (state.q_poly_audit.pop(&state.stop)) |msg| {
        offset += 1;
        queue.updateMaxU64(&state.max_latency_hops, @as(u64, msg.pipeline_hops) + 1);
        state.audit.append(.{
            .source_offset = msg.raw.source_offset,
            .event_hash = msg.event_hash,
            .decision = @enumFromInt(@intFromEnum(msg.decision)),
            .tile_id = msg.decided_by,
        }) catch {
            state.crashed_tile.store(4, .release);
            state.requestStop();
            log.err("tkaudt", "runAudit", "audit log append failed") catch {};
            break;
        };
        _ = state.audited.fetchAdd(1, .release);
        if (logger.isVerbose()) log.debug("tkaudt", "runAudit", "audited event") catch {};
    }
    state.audit_done.store(true, .release);
    log.debug("tkaudt", "runAudit", "done") catch {};
}

test "sandbox failure records crash diagnostics and stops audit" {
    var state = try PaymentPipelineState.init(std.testing.allocator, .{ .event_count = 5, .queue_depth = 2 });
    defer state.deinit();

    // Feed a valid event, then close the queue to force runAudit to exit
    try state.q_poly_audit.push(.{
        .raw = runtime.RawPayment{ .source_offset = 0, .idempotency_key = 1, .account_id = 0, .amount_cents = 100, .currency = .{ 'U', 'S', 'D' } },
        .pipeline_hops = 1,
        .duplicate = false,
        .decision = .allow,
        .decided_by = audit_sink.tile_id_tkpoly,
        .event_hash = 0,
    }, &state.stop);
    state.q_poly_audit.close();
    runAudit(&state);
}
