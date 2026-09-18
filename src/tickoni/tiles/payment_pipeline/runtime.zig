/// Phase 0 Tickoni payment pipeline: shared state and pure helpers.
///
/// This is still a spike: tiles run as in-process threads so tests do not
/// require hugetlbfs, tango workspaces, or sandbox privileges.  The behavior is
/// intentionally product-shaped: bounded links, stable event hashes,
/// append-only audit ordering, deterministic replay, metrics, diagnostics, and
/// crash-only failure propagation.
///
/// Each tile's own run loop lives in its own file (ingest.zig, normalize.zig,
/// dedupe.zig, policy.zig, audit_stage.zig, replay.zig, metric.zig,
/// diag.zig) — see finding 25 in
/// doc/strategy/roadmap/backlog/audits/tech_debt.md. This file owns the
/// PaymentPipelineState every stage shares (queues, dedup table, audit log,
/// atomics) plus config/message contracts and deterministic pure helpers
/// (syntheticPayment/stableEventHash/validFraming) used by more than one
/// stage.
const std = @import("std");
const queue = @import("queue.zig");
const audit_sink = @import("audit_sink.zig");

pub const PolicyDecision = enum(u8) {
    allow,
    deny,
    malformed_drop,
    duplicate_drop,
};

pub const PaymentPipelineConfig = struct {
    event_count: u64 = 10_000,
    queue_depth: usize = 64,
    policy_limit_cents: i64 = 100_000,
    inject_duplicate: bool = true,
    inject_malformed: bool = false,
    /// When set, tkings records a sandbox failure at this source offset and
    /// stops the topology.  This simulates the process-supervisor edge while
    /// the spike still runs in threads.
    sandbox_fail_at: ?u64 = null,
};

pub const RawPayment = struct {
    source_offset: u64,
    idempotency_key: u64,
    account_id: u32,
    amount_cents: i64,
    currency: [3]u8,
    malformed: bool = false,
};

pub const PaymentMessage = struct {
    raw: RawPayment,
    event_hash: u64 = 0,
    pipeline_hops: u8 = 0,
    duplicate: bool = false,
    decision: PolicyDecision = .allow,
    /// Id of the tile stage that finalized `decision` (tknorm for
    /// malformed_drop, tkpoly for allow/deny/duplicate_drop), so tkaudt can
    /// attribute each record to its real producer instead of always tkpoly.
    decided_by: [6]u8 = audit_sink.tile_id_tkpoly,
};

pub const MetricSnapshot = struct {
    produced: u64,
    normalized: u64,
    invalid: u64,
    duplicates: u64,
    allowed: u64,
    denied: u64,
    audited: u64,
    backpressure_waits: u64,
    max_queue_depth: usize,
    max_latency_hops: u64,
};

pub const DiagSnapshot = struct {
    crashed_tile: i32,
    sandbox_failures: u64,
    audit_records: u64,
    replay_checked: bool,
    replay_match: bool,
};

/// Timestamped metric snapshot for per-tile visibility during execution.
/// Fixes V2.22.S4 "No black boxes" audit FAIL #1.
pub const MetricSnapshotWithTime = struct {
    epoch_ns: u64,
    produced: u64,
    normalized: u64,
    invalid: u64,
    duplicates: u64,
    allowed: u64,
    denied: u64,
    audited: u64,
    backpressure_waits: u64,
    max_queue_depth: u64,
    max_latency_hops: u64,
};

/// Format a MetricSnapshotWithTime as a single output line.
pub fn formatSnapshotWithTime(snap: MetricSnapshotWithTime, buf: []u8) ![]const u8 {
    return try std.fmt.bufPrint(
        buf,
        "metrics @ {d}ms  produced={d} normalized={d} invalid={d} dup={d} allow={d} deny={d} audited={d} backpressure={d} qdepth={d} hops={d}\n",
        .{
            snap.epoch_ns / (std.time.ns_per_ms),
            snap.produced,
            snap.normalized,
            snap.invalid,
            snap.duplicates,
            snap.allowed,
            snap.denied,
            snap.audited,
            snap.backpressure_waits,
            snap.max_queue_depth,
            snap.max_latency_hops,
        },
    );
}

const MessageQueue = queue.BoundedQueue(PaymentMessage);
const AuditLog = audit_sink.AuditLog;
pub const crash_none: i32 = -1;

pub const PaymentPipelineState = struct {
    allocator: std.mem.Allocator,
    config: PaymentPipelineConfig,
    q_ing_norm: MessageQueue,
    q_norm_dedu: MessageQueue,
    q_dedu_poly: MessageQueue,
    q_poly_audit: MessageQueue,
    seen_keys: []u64,
    seen_hashes: []u64,
    seen_count: usize,
    audit: AuditLog,

    stop: std.atomic.Value(bool),
    audit_done: std.atomic.Value(bool),
    replay_checked: std.atomic.Value(bool),
    replay_match: std.atomic.Value(bool),
    external_effects_disabled: std.atomic.Value(bool),
    crashed_tile: std.atomic.Value(i32),

    produced: std.atomic.Value(u64),
    normalized: std.atomic.Value(u64),
    invalid: std.atomic.Value(u64),
    duplicates: std.atomic.Value(u64),
    allowed: std.atomic.Value(u64),
    denied: std.atomic.Value(u64),
    audited: std.atomic.Value(u64),
    sandbox_failures: std.atomic.Value(u64),
    metric_snapshots: std.atomic.Value(u64),
    diag_snapshots: std.atomic.Value(u64),
    replay_divergences: std.atomic.Value(u64),
    max_latency_hops: std.atomic.Value(u64),

    pub fn init(allocator: std.mem.Allocator, config: PaymentPipelineConfig) !PaymentPipelineState {
        if (config.queue_depth == 0 or !std.math.isPowerOfTwo(config.queue_depth)) {
            return error.QueueDepthNotPowerOfTwo;
        }

        const audit_cap: usize = @intCast(config.event_count);
        const seen_keys = try allocator.alloc(u64, audit_cap);
        errdefer allocator.free(seen_keys);
        const seen_hashes = try allocator.alloc(u64, audit_cap);
        errdefer allocator.free(seen_hashes);

        var q_ing_norm = try MessageQueue.init(allocator, config.queue_depth);
        errdefer q_ing_norm.deinit(allocator);
        var q_norm_dedu = try MessageQueue.init(allocator, config.queue_depth);
        errdefer q_norm_dedu.deinit(allocator);
        var q_dedu_poly = try MessageQueue.init(allocator, config.queue_depth);
        errdefer q_dedu_poly.deinit(allocator);
        var q_poly_audit = try MessageQueue.init(allocator, config.queue_depth);
        errdefer q_poly_audit.deinit(allocator);

        return .{
            .allocator = allocator,
            .config = config,
            .q_ing_norm = q_ing_norm,
            .q_norm_dedu = q_norm_dedu,
            .q_dedu_poly = q_dedu_poly,
            .q_poly_audit = q_poly_audit,
            .seen_keys = seen_keys,
            .seen_hashes = seen_hashes,
            .seen_count = 0,
            .audit = try AuditLog.init(allocator, audit_cap),
            .stop = std.atomic.Value(bool).init(false),
            .audit_done = std.atomic.Value(bool).init(false),
            .replay_checked = std.atomic.Value(bool).init(false),
            .replay_match = std.atomic.Value(bool).init(false),
            .external_effects_disabled = std.atomic.Value(bool).init(false),
            .crashed_tile = std.atomic.Value(i32).init(crash_none),
            .produced = std.atomic.Value(u64).init(0),
            .normalized = std.atomic.Value(u64).init(0),
            .invalid = std.atomic.Value(u64).init(0),
            .duplicates = std.atomic.Value(u64).init(0),
            .allowed = std.atomic.Value(u64).init(0),
            .denied = std.atomic.Value(u64).init(0),
            .audited = std.atomic.Value(u64).init(0),
            .sandbox_failures = std.atomic.Value(u64).init(0),
            .metric_snapshots = std.atomic.Value(u64).init(0),
            .diag_snapshots = std.atomic.Value(u64).init(0),
            .replay_divergences = std.atomic.Value(u64).init(0),
            .max_latency_hops = std.atomic.Value(u64).init(0),
        };
    }

    pub fn deinit(self: *PaymentPipelineState) void {
        self.closeQueues();
        self.q_ing_norm.deinit(self.allocator);
        self.q_norm_dedu.deinit(self.allocator);
        self.q_dedu_poly.deinit(self.allocator);
        self.q_poly_audit.deinit(self.allocator);
        self.allocator.free(self.seen_keys);
        self.allocator.free(self.seen_hashes);
        self.audit.deinit(self.allocator);
    }

    pub fn closeQueues(self: *PaymentPipelineState) void {
        self.q_ing_norm.close();
        self.q_norm_dedu.close();
        self.q_dedu_poly.close();
        self.q_poly_audit.close();
    }

    pub fn requestStop(self: *PaymentPipelineState) void {
        self.stop.store(true, .release);
        self.closeQueues();
    }

    pub fn snapshotMetrics(self: *PaymentPipelineState) MetricSnapshot {
        return .{
            .produced = self.produced.load(.acquire),
            .normalized = self.normalized.load(.acquire),
            .invalid = self.invalid.load(.acquire),
            .duplicates = self.duplicates.load(.acquire),
            .allowed = self.allowed.load(.acquire),
            .denied = self.denied.load(.acquire),
            .audited = self.audited.load(.acquire),
            .backpressure_waits = self.q_ing_norm.pushWaits() +
                self.q_norm_dedu.pushWaits() +
                self.q_dedu_poly.pushWaits() +
                self.q_poly_audit.pushWaits(),
            .max_queue_depth = @max(
                @max(self.q_ing_norm.maxDepth(), self.q_norm_dedu.maxDepth()),
                @max(self.q_dedu_poly.maxDepth(), self.q_poly_audit.maxDepth()),
            ),
            .max_latency_hops = self.max_latency_hops.load(.acquire),
        };
    }

    pub fn snapshotDiag(self: *PaymentPipelineState) DiagSnapshot {
        return .{
            .crashed_tile = self.crashed_tile.load(.acquire),
            .sandbox_failures = self.sandbox_failures.load(.acquire),
            .audit_records = self.audited.load(.acquire),
            .replay_checked = self.replay_checked.load(.acquire),
            .replay_match = self.replay_match.load(.acquire),
        };
    }

    pub fn seenOrRemember(self: *PaymentPipelineState, msg: PaymentMessage) bool {
        for (self.seen_keys[0..self.seen_count], self.seen_hashes[0..self.seen_count]) |key, hash| {
            if (key == msg.raw.idempotency_key and hash == msg.event_hash) return true;
        }
        self.seen_keys[self.seen_count] = msg.raw.idempotency_key;
        self.seen_hashes[self.seen_count] = msg.event_hash;
        self.seen_count += 1;
        return false;
    }
};

pub fn syntheticPayment(config: PaymentPipelineConfig, offset: u64) RawPayment {
    const canonical_offset: u64 = if (config.inject_duplicate and offset == 3) 1 else offset;
    const amount: i64 = if (offset == 7) config.policy_limit_cents + 1 else @as(i64, @intCast(1_000 + canonical_offset));
    const malformed_offset: u64 = if (config.event_count == 0)
        0
    else if (config.event_count <= 5)
        config.event_count - 1
    else
        5;
    return .{
        .source_offset = offset,
        .idempotency_key = 10_000 + canonical_offset,
        .account_id = @intCast(42 + canonical_offset % 17),
        .amount_cents = amount,
        .currency = .{ 'U', 'S', 'D' },
        .malformed = config.inject_malformed and offset == malformed_offset,
    };
}

pub fn stableEventHash(raw: RawPayment) u64 {
    var h = audit_sink.audit_seed;
    hashU64(&h, raw.idempotency_key);
    hashU32(&h, raw.account_id);
    hashI64(&h, raw.amount_cents);
    hashBytes(&h, &raw.currency);
    return h;
}

pub fn validFraming(raw: RawPayment) bool {
    if (raw.malformed) return false;
    if (!std.mem.eql(u8, &raw.currency, "USD")) return false;
    return raw.amount_cents > 0;
}

fn hashU64(h: *u64, value: u64) void {
    var x = value;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        hashByte(h, @intCast(x & 0xff));
        x >>= 8;
    }
}

fn hashU32(h: *u64, value: u32) void {
    var x = value;
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        hashByte(h, @intCast(x & 0xff));
        x >>= 8;
    }
}

fn hashI64(h: *u64, value: i64) void {
    hashU64(h, @bitCast(value));
}

fn hashBytes(h: *u64, bytes: []const u8) void {
    for (bytes) |byte| hashByte(h, byte);
}

fn hashByte(h: *u64, byte: u8) void {
    h.* = (h.* ^ byte) *% 0x100000001b3;
}

test "stableEventHash is deterministic and ignores source offset" {
    const cfg = PaymentPipelineConfig{};
    const a = syntheticPayment(cfg, 1);
    const b = syntheticPayment(cfg, 3);
    try std.testing.expectEqual(a.idempotency_key, b.idempotency_key);
    try std.testing.expectEqual(stableEventHash(a), stableEventHash(b));
}
