const std = @import("std");
const audit = @import("audit_tile");
const runtime = @import("runtime.zig");
const ingest = @import("ingest.zig");
const normalize = @import("normalize.zig");
const dedupe = @import("dedupe.zig");
const policy = @import("policy.zig");
const audit_stage = @import("audit_stage.zig");
const replay = @import("replay.zig");
const diag = @import("diag.zig");

pub const audit_sink = @import("audit_sink.zig");
pub const process = @import("process.zig");
pub const PolicyDecision = runtime.PolicyDecision;
pub const PaymentPipelineConfig = runtime.PaymentPipelineConfig;
pub const RawPayment = runtime.RawPayment;
pub const PaymentMessage = runtime.PaymentMessage;
pub const MetricSnapshot = runtime.MetricSnapshot;
pub const DiagSnapshot = runtime.DiagSnapshot;
pub const PaymentPipelineState = runtime.PaymentPipelineState;
pub const runIngest = ingest.runIngest;
pub const runNormalize = normalize.runNormalize;
pub const runDedupe = dedupe.runDedupe;
pub const runPolicy = policy.runPolicy;
pub const runAudit = audit_stage.runAudit;
pub const runReplay = replay.runReplay;
pub const runDiag = diag.runDiag;
pub const syntheticPayment = runtime.syntheticPayment;
pub const stableEventHash = runtime.stableEventHash;
pub const validFraming = runtime.validFraming;

// Cross-stage integration tests: exercise the pipeline end to end
// sequentially, so they belong to the pipeline as a whole rather than any
// one tile's own file.

fn runOneSequentialForTest(state: *PaymentPipelineState, raw: RawPayment) !void {
    try state.q_ing_norm.push(.{ .raw = raw, .pipeline_hops = 1 }, &state.stop);
    state.q_ing_norm.close();
    runNormalize(state);
    runDedupe(state);
    runPolicy(state);
    runAudit(state);
    runReplay(state);
}

test "payment tile stages audit and replay one valid payment sequentially" {
    var state = try PaymentPipelineState.init(std.testing.allocator, .{ .event_count = 1, .queue_depth = 1 });
    defer state.deinit();

    try runOneSequentialForTest(&state, syntheticPayment(state.config, 0));

    const metrics = state.snapshotMetrics();
    try std.testing.expectEqual(@as(u64, 1), metrics.normalized);
    try std.testing.expectEqual(@as(u64, 1), metrics.audited);
    try std.testing.expectEqual(@as(u64, 1), metrics.allowed);
    try std.testing.expectEqual(@as(u64, 5), metrics.max_latency_hops);
    try std.testing.expect(state.replay_checked.load(.seq_cst));
    try std.testing.expect(state.replay_match.load(.seq_cst));
    try std.testing.expect(state.external_effects_disabled.load(.seq_cst));
}

test "Phase 0 rejects malformed payment framing" {
    var state = try PaymentPipelineState.init(std.testing.allocator, .{ .event_count = 1, .queue_depth = 1, .inject_malformed = true });
    defer state.deinit();
    try runOneSequentialForTest(&state, syntheticPayment(state.config, 0));
    try std.testing.expectEqual(@as(u64, 1), state.invalid.load(.seq_cst));
    try std.testing.expectEqual(@as(u64, 0), state.normalized.load(.seq_cst));
    try std.testing.expectEqual(@as(u64, 1), state.audited.load(.seq_cst));
    try std.testing.expectEqual(audit.PolicyOutcome.malformed_drop, state.audit.records[0].payload.policy_decision.outcome);
    try std.testing.expect(state.replay_match.load(.seq_cst));
}

test {
    _ = @import("runtime.zig");
    _ = @import("ingest.zig");
    _ = @import("normalize.zig");
    _ = @import("dedupe.zig");
    _ = @import("policy.zig");
    _ = @import("audit_stage.zig");
    _ = @import("replay.zig");
    _ = @import("diag.zig");
    _ = @import("process.zig");
}
