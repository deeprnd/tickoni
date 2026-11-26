//! Zig-owned replay verdict for the C fd_stem tkrepl tile (tk_repl_stem.c).
//!
//! tkcase streams tkrepl the case capsule (every event it attached, then a
//! summary of what it recorded; tkrepl_frag.h). tkrepl folds the events into its
//! own observation and asks `verify` whether the observation matches the
//! summary. The stem only transports and folds; whether, and where, the replay
//! diverges is decided here and reaches the stem through the one hook in
//! `hooks` (tkrepl_frag.h, under tk_agent_hooks.h's rules: fixed-size data in
//! and out, no allocator, no I/O, pure).
//!
//! Divergences are counted per field, the way the capsule verifiers in mod.zig
//! count them (DivergenceTracker, shared with them). The capsule position of a
//! divergence is 1-based: event i is position i, and the summary, which closes
//! the capsule, is position observed_count + 1. An unreadable summary (a wire
//! version tkrepl does not know) is a hard divergence: nothing else in it is
//! interpreted, as with checkCapsuleVersions' schema-version reject.
const std = @import("std");
const audit_mod = @import("audit_mod");

pub const Query = audit_mod.TkReplVerifyQuery;
pub const Directive = audit_mod.TkReplVerifyDirective;
pub const Hooks = audit_mod.TkReplHooks;
pub const Summary = audit_mod.TkCaseCapsuleMsg;

pub const wire_version: u16 = audit_mod.TK_REPL_WIRE_VERSION;

/// The field a divergence names (TK_REPL_FIELD_*).
pub const Field = enum(u8) {
    none = audit_mod.TK_REPL_FIELD_NONE,
    capsule_version = audit_mod.TK_REPL_FIELD_CAPSULE_VERSION,
    event_case_id = audit_mod.TK_REPL_FIELD_EVENT_CASE_ID,
    case_id = audit_mod.TK_REPL_FIELD_CASE_ID,
    event_count = audit_mod.TK_REPL_FIELD_EVENT_COUNT,
    first_source_offset = audit_mod.TK_REPL_FIELD_FIRST_SOURCE_OFFSET,
    last_source_offset = audit_mod.TK_REPL_FIELD_LAST_SOURCE_OFFSET,
    capsule_hash = audit_mod.TK_REPL_FIELD_CAPSULE_HASH,
};

/// Counts divergences and keeps the first one's field and position. A
/// position of 0 means none is recorded yet, so callers note 1-based
/// positions. The one definition every replay verifier uses.
pub fn Tracker(comptime FieldT: type, comptime none: FieldT) type {
    return struct {
        count: u64 = 0,
        first_field: FieldT = none,
        first_seq: u64 = 0,

        const Self = @This();

        pub fn note(self: *Self, field: FieldT, seq: u64) void {
            self.count += 1;
            if (self.first_seq == 0) {
                self.first_field = field;
                self.first_seq = seq;
            }
        }
    };
}

/// The capsule verifiers' tracker (mod.zig, through capsule.zig): fields named
/// by string.
pub const DivergenceTracker = Tracker([]const u8, "");

const CaseTracker = Tracker(Field, .none);

fn directive(t: CaseTracker) Directive {
    var d = std.mem.zeroes(Directive);
    d.divergences = t.count;
    d.first_divergent_seq = t.first_seq;
    d.first_field = @backingInt(if (t.count == 0) Field.none else t.first_field);
    return d;
}

/// The replay verdict for one case capsule.
pub fn verify(q: Query) Directive {
    var t = CaseTracker{};
    const end = q.observed_count + 1;
    if (q.summary.version != wire_version) {
        t.note(.capsule_version, end);
        return directive(t);
    }
    // Event-level first: they were seen before the summary.
    if (q.case_id_mismatches != 0) t.note(.event_case_id, q.first_case_id_mismatch_seq);
    if (q.summary.case_id == 0 or q.observed_case_id != q.summary.case_id) t.note(.case_id, end);
    if (q.observed_count != q.summary.event_count) t.note(.event_count, end);
    if (q.observed_first_source_offset != q.summary.first_source_offset) t.note(.first_source_offset, end);
    if (q.observed_last_source_offset != q.summary.last_source_offset) t.note(.last_source_offset, end);
    if (q.observed_hash != q.summary.capsule_hash) t.note(.capsule_hash, end);
    return directive(t);
}

fn verifyC(q: [*c]const Query) callconv(.c) Directive {
    if (q == null) {
        // No query: nothing can be read, the hard divergence.
        var t = CaseTracker{};
        t.note(.capsule_version, 1);
        return directive(t);
    }
    return verify(q.*);
}

/// The function-pointer table the tkrepl child registers into the C stem.
pub const hooks: Hooks = .{ .verify = verifyC };

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn matching(n: u64) Query {
    var q = std.mem.zeroes(Query);
    q.summary.version = wire_version;
    q.summary.case_id = 0x5eed;
    q.summary.event_count = n;
    q.summary.first_source_offset = 0;
    q.summary.last_source_offset = n - 1;
    q.summary.capsule_hash = 0xfeed_f00d;
    q.observed_count = n;
    q.observed_case_id = 0x5eed;
    q.observed_first_source_offset = 0;
    q.observed_last_source_offset = n - 1;
    q.observed_hash = 0xfeed_f00d;
    return q;
}

test "verify: an observation equal to the summary is a match" {
    const d = verify(matching(4));
    try std.testing.expectEqual(@as(u64, 0), d.divergences);
    try std.testing.expectEqual(@as(u64, 0), d.first_divergent_seq);
    try std.testing.expectEqual(@backingInt(Field.none), d.first_field);
}

test "verify: an unknown summary version is one hard divergence at the summary" {
    var q = matching(4);
    q.summary.version = wire_version + 1;
    q.observed_hash ^= 1; // not looked at
    const d = verify(q);
    try std.testing.expectEqual(@as(u64, 1), d.divergences);
    try std.testing.expectEqual(@as(u64, 5), d.first_divergent_seq);
    try std.testing.expectEqual(@backingInt(Field.capsule_version), d.first_field);
}

test "verify: an event attached to another case is the first divergence, at that event" {
    var q = matching(4);
    q.case_id_mismatches = 2;
    q.first_case_id_mismatch_seq = 3;
    q.observed_hash ^= 1;
    const d = verify(q);
    // One per field: event_case_id and capsule_hash.
    try std.testing.expectEqual(@as(u64, 2), d.divergences);
    try std.testing.expectEqual(@as(u64, 3), d.first_divergent_seq);
    try std.testing.expectEqual(@backingInt(Field.event_case_id), d.first_field);
}

test "verify: each summary field that differs counts once, first in field order" {
    var q = matching(4);
    q.observed_count = 3;
    q.observed_last_source_offset = 2;
    q.observed_hash ^= 1;
    const d = verify(q);
    try std.testing.expectEqual(@as(u64, 3), d.divergences);
    try std.testing.expectEqual(@as(u64, 4), d.first_divergent_seq);
    try std.testing.expectEqual(@backingInt(Field.event_count), d.first_field);
}

test "verify: a summary without a case, or for another case, diverges on case_id" {
    var q = matching(2);
    q.summary.case_id = 0;
    try std.testing.expectEqual(@backingInt(Field.case_id), verify(q).first_field);
    q = matching(2);
    q.observed_case_id = 0x1234;
    const d = verify(q);
    try std.testing.expectEqual(@as(u64, 1), d.divergences);
    try std.testing.expectEqual(@backingInt(Field.case_id), d.first_field);
}

test "verify: the C hook is the same verdict, and a missing query is a hard divergence" {
    const q = matching(3);
    try std.testing.expectEqual(verify(q), hooks.verify.?(&q));
    const d = hooks.verify.?(null);
    try std.testing.expectEqual(@as(u64, 1), d.divergences);
    try std.testing.expectEqual(@backingInt(Field.capsule_version), d.first_field);
}

test "DivergenceTracker keeps the first field and position" {
    var t = DivergenceTracker{};
    t.note("basket_id", 1);
    t.note("proposal_hash", 6);
    try std.testing.expectEqual(@as(u64, 2), t.count);
    try std.testing.expectEqualStrings("basket_id", t.first_field);
    try std.testing.expectEqual(@as(u64, 1), t.first_seq);
}
