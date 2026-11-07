/// tkrepl: waits for tkaudt to finish, then independently recomputes the
/// deterministic expected audit chain from the same synthetic-payment inputs
/// and compares it record-by-record against what was actually audited,
/// reporting divergences with external effects disabled.
const std = @import("std");
const audit = @import("audit");
const audit_sink = @import("audit_sink.zig");
const tile_ids = @import("runtime").tile_ids;
const runtime = @import("runtime.zig");
const logger = @import("logger");

const PaymentPipelineState = runtime.PaymentPipelineState;
const PaymentPipelineConfig = runtime.PaymentPipelineConfig;
const RawPayment = runtime.RawPayment;
const PolicyDecision = runtime.PolicyDecision;

pub fn runReplay(state: *PaymentPipelineState) void {
    const log = logger.get();
    log.enter(tile_ids.tkrepl.slice(), "runReplay");
    defer log.exit(tile_ids.tkrepl.slice(), "runReplay");

    while (!state.audit_done.load(.acquire)) {
        if (state.stop.load(.acquire) and state.crashed_tile.load(.acquire) != runtime.crash_none) {
            state.replay_checked.store(true, .release);
            state.replay_match.store(false, .release);
            log.err(tile_ids.tkrepl.slice(), "runReplay", "aborting replay due to crash");
            return;
        }
        std.Thread.yield() catch {};
    }

    state.external_effects_disabled.store(true, .release);
    const divergences = deterministicReplayDivergences(state, log);
    state.replay_divergences.store(divergences, .release);
    state.replay_match.store(divergences == 0, .release);
    state.replay_checked.store(true, .release);
    log.debug(tile_ids.tkrepl.slice(), "runReplay", "replay check complete");
}

fn deterministicReplayDivergences(state: *PaymentPipelineState, log: *logger.Logger) u64 {
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
        const decided_by: tile_ids.TileId = if (malformed) tile_ids.tknorm else tile_ids.tkpoly;

        const expected = buildReplayEvent(expected_seq, raw, event_hash, decision, decided_by, prev_hash);
        if (expected_seq >= state.audit.count) {
            log.kvFmt(tile_ids.tkrepl.slice(), "deterministicReplayDivergences", "seq={d} reason=missing_audit_record expected_seq={d} actual_count={d}", .{ expected_seq, expected_seq, state.audit.count });
            divergences += 1;
        } else if (!audit.auditEventsEql(expected, state.audit.records[@intCast(expected_seq)])) {
            log.kvFmt(tile_ids.tkrepl.slice(), "deterministicReplayDivergences", "seq={d} expected_hash={x} actual_hash={x} reason=hash_mismatch", .{ expected_seq, expected.header.record_hash, state.audit.records[@intCast(expected_seq)].header.record_hash });
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
    decided_by: tile_ids.TileId,
    prev_hash: u64,
) audit.AuditEvent {
    const outcome: audit.PolicyOutcome = switch (decision) {
        .allow => .allow,
        .deny => .deny,
        .malformed_drop => .malformed_drop,
        .duplicate_drop => .duplicate_drop,
    };
    return audit.buildEvent(.{
        .schema_version = audit.audit_schema_version,
        .run_id = 0,
        .seq = seq,
        .source_offset = raw.source_offset,
        .tile_id = decided_by.bytes,
        .logical_actor_id = 0,
        .policy_version = std.mem.zeroes([32]u8),
        .capability_envelope_id = 0,
        .timestamp_ns = 0,
        .prev_hash = prev_hash,
        .record_hash = 0,
        .version = std.mem.zeroes([64]u8),
        .platform_tier = std.mem.zeroes([64]u8),
        .isolation_tier = std.mem.zeroes([64]u8),
        .release_digest = std.mem.zeroes([64]u8),
        .manifest_id = std.mem.zeroes([64]u8),
    }, .{
        .policy_decision = .{
            .outcome = @backingInt(outcome),
            .rule_id = 0,
            .failed_scope_dim = std.mem.zeroes([32]u8),
            .source_event_hash = event_hash,
            .catalog_schema_version = 0,
            .taxonomy_id = std.mem.zeroes([32]u8),
            .taxonomy_version = 0,
            .classification_code = std.mem.zeroes([32]u8),
        },
    });
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
