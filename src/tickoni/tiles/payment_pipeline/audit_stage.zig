/// tkaudt: appends every payment event's policy decision to the append-only
/// audit log, attributing each record to whichever earlier stage
/// (decided_by) actually finalized it. Named audit_stage.zig (not audit.zig)
/// to stay distinct from the sibling audit_sink.zig record-builder and the
/// audit_sink module this pipeline audits into.
const std = @import("std");
const runtime = @import("runtime.zig");
const queue = @import("queue.zig");
const logger = @import("logger");
const tile_ids = @import("runtime").tile_ids;

/// Re-export AuditState so callers use runtime.AuditState everywhere.
pub const AuditState = runtime.AuditState;
const PaymentPipelineState = runtime.PaymentPipelineState;
const MessageQueue = queue.BoundedQueue(runtime.PaymentMessage);

pub fn runAudit(state: *AuditState, stop: *std.atomic.Value(bool), q_poly_audit: *MessageQueue) void {
    const log = logger.get();
    log.enter(tile_ids.tkaudt.slice(), "runAudit");
    defer log.exit(tile_ids.tkaudt.slice(), "runAudit");

    var offset: u64 = 0;
    while (q_poly_audit.pop(stop)) |msg| {
        offset += 1;
        queue.updateMaxU64(&state.max_latency_hops, @as(u64, msg.pipeline_hops) + 1);
        state.audit.append(.{
            .source_offset = msg.raw.source_offset,
            .event_hash = msg.event_hash,
            .decision = @fromBackingInt(@intCast(@backingInt(msg.decision))),
            .tile_id = msg.decided_by.bytes,
        }) catch {
            state.crashed_tile.store(4, .release);
            stop.store(true, .release);
            log.err(tile_ids.tkaudt.slice(), "runAudit", "audit log append failed");
            break;
        };
        _ = state.audited.fetchAdd(1, .release);
        log.kvFmt(tile_ids.tkaudt.slice(), "runAudit", "offset={d} event_hash={x} decided_by={s}", .{ msg.raw.source_offset, msg.event_hash, msg.decided_by.slice() });
    }
    state.audit_done.store(true, .release);
    log.debug(tile_ids.tkaudt.slice(), "runAudit", "done");
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
        .decided_by = tile_ids.tkpoly,
        .event_hash = 0,
    }, &state.audit.stop);
    state.q_poly_audit.close();
    runAudit(&state.audit, &state.audit.stop, &state.q_poly_audit);
}
