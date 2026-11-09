/// Shared audit state — owns audit coordination atomics and AuditLog.
///
/// Embedded in PaymentPipelineState so audit modules (audit_stage, replay)
/// only depend on this slim struct instead of the full pipeline state.
///
/// This resolves maintainability-audit Finding C3.

const std = @import("std");
const audit = @import("audit");
const audit_sink = @import("audit_sink.zig");

/// Audit coordination state.  Embedded in PaymentPipelineState so audit
/// modules (audit_stage.zig, replay.zig) depend on this slim struct
/// instead of the full pipeline state.
pub const AuditState = struct {
    /// Stop signal shared by all pipeline threads.
    stop: std.atomic.Value(bool),
    /// Set true by runAudit when the audit loop exits.
    audit_done: std.atomic.Value(bool),
    /// Crash diagnostics — tile index or crash_none.
    crashed_tile: std.atomic.Value(i32),
    /// Total records appended (metric).
    audited: std.atomic.Value(u64),
    /// Max pipeline hops observed (metric).
    max_latency_hops: std.atomic.Value(u64),
    /// The append-only audit log.
    audit: audit_sink.AuditLog,
    /// Divergences detected by replay (metric).
    replay_divergences: std.atomic.Value(u64),
    /// Whether replay matched (metric).
    replay_match: std.atomic.Value(bool),
    /// Whether replay has completed (metric).
    replay_checked: std.atomic.Value(bool),
    /// Whether external effects are disabled for replay.
    external_effects_disabled: std.atomic.Value(bool),

    pub fn init(allocator: std.mem.Allocator, audit_capacity: usize) !AuditState {
        return .{
            .stop = std.atomic.Value(bool).init(false),
            .audit_done = std.atomic.Value(bool).init(false),
            .crashed_tile = std.atomic.Value(i32).init(-1),
            .audited = std.atomic.Value(u64).init(0),
            .max_latency_hops = std.atomic.Value(u64).init(0),
            .audit = try audit_sink.AuditLog.init(allocator, audit_capacity),
            .replay_divergences = std.atomic.Value(u64).init(0),
            .replay_match = std.atomic.Value(bool).init(false),
            .replay_checked = std.atomic.Value(bool).init(false),
            .external_effects_disabled = std.atomic.Value(bool).init(false),
        };
    }

    pub fn deinit(self: *AuditState, allocator: std.mem.Allocator) void {
        self.audit.deinit(allocator);
    }

    /// Read-only access to audit records for replay comparison.
    pub fn auditRecords(self: *const AuditState) []audit.AuditEvent {
        return self.audit.records[0..self.audit.count];
    }

    /// Read-only access to audit record count.
    pub fn auditCount(self: *const AuditState) usize {
        return self.audit.count;
    }
};
