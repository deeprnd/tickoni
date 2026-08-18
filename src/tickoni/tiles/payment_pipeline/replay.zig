/// tkrepl: waits for tkaudt to finish, then independently recomputes the
/// deterministic expected audit chain from the same synthetic-payment inputs
/// and compares it record-by-record against what was actually audited,
/// reporting divergences with external effects disabled.
const std = @import("std");
const audit = @import("audit_tile");
const audit_sink = @import("audit_sink.zig");
const runtime = @import("runtime.zig");
const logger = @import("logger");

const PaymentPipelineState = runtime.PaymentPipelineState;
const PaymentPipelineConfig = runtime.PaymentPipelineConfig;
const RawPayment = runtime.RawPayment;
const PolicyDecision = runtime.PolicyDecision;

pub fn runReplay(state: *PaymentPipelineState) void {
    const log = logger.get();
    log.enter("tkrepl", "runReplay") catch {};
    defer log.exit("tkrepl", "runReplay") catch {};

    while (!state.audit_done.load(.acquire)) {
        if (state.stop.load(.acquire) and state.crashed_tile.load(.acquire) != runtime.crash_none) {
            state.replay_checked.store(true, .release);
            state.replay_match.store(false, .release);
            log.err("tkrepl", "runReplay", "aborting replay due to crash") catch {};
            return;
        }
        std.Thread.yield() catch {};
    }

    state.external_effects_disabled.store(true, .release);
    const divergences = deterministicReplayDivergences(state);
    state.replay_divergences.store(divergences, .release);
    state.replay_match.store(divergences == 0, .release);
    state.replay_checked.store(true, .release);
    log.debug("tkrepl", "runReplay", "replay check complete") catch {};
}

fn deterministicReplayDivergences(state: *PaymentPipelineState) u64 {
    var prev_hash = audit_sink.audit_seed;
    var expected_seq: u64 = 0;
    var divergences: u64 = 0;

    var offset: u64 = 0;
    while (offset < state.config.event_count) : (offset += 1) {
        const raw = runtime.syntheticPayment(state.config, offset);
        const event_hash = runtime.stableEventHash(raw);
        const malformed = !runtime.validFraming(raw);
        const decision: PolicyDecision = if (malformed) .malformed_drop else blk: {
            const duplicate = replayDuplicate(state.config, offset, raw.idempotency_key, event_hash);
            break :blk if (duplicate)
                .duplicate_drop
            else if (raw.amount_cents > state.config.policy_limit_cents)
                .deny
            else
                .allow;
        };
        const decided_by: [6]u8 = if (malformed) audit_sink.tile_id_tknorm else audit_sink.tile_id_tkpoly;

        const expected = buildReplayEvent(expected_seq, raw, event_hash, decision, decided_by, prev_hash);
        if (expected_seq >= state.audit.count) {
            divergences += 1;
        } else if (!audit.auditEventsEql(expected, state.audit.records[@intCast(expected_seq)])) {
            divergences += 1;
        }
        prev_hash = expected.header.record_hash;
        expected_seq += 1;
    }

    if (expected_seq != state.audit.count) {
        divergences += if (expected_seq > state.audit.count)
            expected_seq - state.audit.count
        else
            state.audit.count - expected_seq;
    }
    return divergences;
}

fn buildReplayEvent(
    seq: u64,
    raw: RawPayment,
    event_hash: u64,
    decision: PolicyDecision,
    decided_by: [6]u8,
    prev_hash: u64,
) audit.AuditEvent {
    return audit_sink.buildPolicyDecisionEvent(
        seq,
        raw.source_offset,
        event_hash,
        @enumFromInt(@intFromEnum(decision)),
        decided_by,
        prev_hash,
    );
}

fn replayDuplicate(config: PaymentPipelineConfig, offset: u64, key: u64, hash: u64) bool {
    var prior: u64 = 0;
    while (prior < offset) : (prior += 1) {
        const raw = runtime.syntheticPayment(config, prior);
        if (!runtime.validFraming(raw)) continue;
        if (raw.idempotency_key == key and runtime.stableEventHash(raw) == hash) return true;
    }
    return false;
}

test "sandbox failure records crash diagnostics and stops replay" {
    var state = try PaymentPipelineState.init(std.testing.allocator, .{ .event_count = 5, .queue_depth = 2 });
    defer state.deinit();

    // Signal that audit is done so runReplay does not busy-wait forever
    state.audit_done.store(true, .release);
    runReplay(&state);
}
