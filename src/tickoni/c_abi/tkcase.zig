/// Thin Zig wrapper over tk_case_stem.c — tkcase, the case router of the event
/// spine. It opens the run's case on the first event (a random case id), stamps
/// every event with it, keeps every event in the case capsule, forwards each to
/// tkpoly and tkdisp, and audits the case's creation and completion to tkaudt.
/// Accessors take the tile object's scratch base and never return a
/// child-process pointer.
const std = @import("std");
const stem_run = @import("stem_run.zig");
const audit_mod = @import("audit_mod");

pub const TopoRunTile = opaque {};

/// The case scope as tkcase holds it (audit_schema.h).
pub const Scope = audit_mod.TkCaseScope;
/// One capsule entry: the event as tkcase forwarded it.
pub const Event = audit_mod.TkEvent;

pub const State = enum(u8) {
    none = audit_mod.TK_CASE_STATE_NONE,
    active = audit_mod.TK_CASE_STATE_ACTIVE,
    completed = audit_mod.TK_CASE_STATE_COMPLETED,
};

const run_desc = stem_run.RunDescriptor("case", TopoRunTile);

extern fn tkcase_tile_scratch_footprint() usize;
extern fn tkcase_tile_scratch_align() usize;
extern fn tkcase_set_event_count(event_count: usize) void;
extern fn tkcase_set_rng_seed(seed: usize) void;
extern fn tkcase_consumed(scratch: ?*anyopaque) usize;
extern fn tkcase_forwarded(scratch: ?*anyopaque) usize;
extern fn tkcase_case_audit_emitted(scratch: ?*anyopaque) usize;
extern fn tkcase_capsule_count(scratch: ?*anyopaque) usize;
extern fn tkcase_capsule_hash(scratch: ?*anyopaque) usize;
extern fn tkcase_scope_copy(scratch: ?*anyopaque, dst: *anyopaque, dst_sz: usize) void;
extern fn tkcase_capsule_copy(scratch: ?*anyopaque, idx: usize, dst: *anyopaque, dst_sz: usize) void;
extern fn tk_topob_tickoni_tile_scratch_footprint(tile_name: [*:0]const u8) usize;

pub fn getRunName() [*:0]const u8 {
    return run_desc.name();
}

pub fn getRunTile() ?*TopoRunTile {
    return run_desc.tile();
}

pub fn scratchFootprint() usize {
    return tkcase_tile_scratch_footprint();
}

pub fn scratchAlign() usize {
    return tkcase_tile_scratch_align();
}

/// The run's event count: the shutdown gate, the event that closes the case,
/// and the capsule size. Part of the workspace layout: topo_build.build() sets
/// it before any footprint query.
pub fn setEventCount(event_count: u64) void {
    tkcase_set_event_count(@intCast(event_count));
}

/// Seeds the case-id generator for this process; 0 (the default) seeds it
/// from the tile's tick counter. Children set it from TopologySpec before the
/// tile runs.
pub fn setRngSeed(seed: u64) void {
    tkcase_set_rng_seed(@intCast(seed));
}

/// Events tkcase has committed from its input.
pub fn consumed(scratch: ?*anyopaque) u64 {
    return tkcase_consumed(scratch);
}

/// Event fragments published, summed over tkpoly and tkdisp (two per event).
pub fn forwarded(scratch: ?*anyopaque) u64 {
    return tkcase_forwarded(scratch);
}

/// Case lifecycle records published to tkaudt.
pub fn caseAuditEmitted(scratch: ?*anyopaque) u64 {
    return tkcase_case_audit_emitted(scratch);
}

/// Events in the case capsule.
pub fn capsuleCount(scratch: ?*anyopaque) u64 {
    return tkcase_capsule_count(scratch);
}

/// The capsule's running hash (tk_capsule_hash.h): what tkcase reports to
/// tkrepl in its capsule summary.
pub fn capsuleHash(scratch: ?*anyopaque) u64 {
    return tkcase_capsule_hash(scratch);
}

/// Copies the case scope out of the tile's scratch.
pub fn scope(scratch: ?*anyopaque) Scope {
    var out: Scope = undefined;
    tkcase_scope_copy(scratch, &out, @sizeOf(Scope));
    return out;
}

/// Copies capsule entry `idx` (below capsuleCount) out of the tile's scratch.
pub fn capsuleEvent(scratch: ?*anyopaque, idx: usize) Event {
    var out: Event = undefined;
    tkcase_capsule_copy(scratch, idx, &out, @sizeOf(Event));
    return out;
}

test "tkcase identity — name is TILE_ID_TKCASE with non-null callbacks" {
    try std.testing.expectEqualStrings("tkcase", std.mem.sliceTo(run_desc.name(), 0));
    try std.testing.expect(run_desc.tile() != null);
    try std.testing.expect(run_desc.run() != null);
    try std.testing.expect(run_desc.privilegedInit() != null);
    try std.testing.expect(run_desc.unprivilegedInit() != null);
    try std.testing.expect(run_desc.scratchAlign() != null);
    try std.testing.expect(run_desc.scratchFootprint() != null);
}

test "tkcase scratch — the capsule holds every event of the run, aligned, topob parity" {
    defer setEventCount(0);
    for ([_]u64{ 1, 6, 64 }) |n| {
        setEventCount(n);
        const footprint = scratchFootprint();
        try std.testing.expect(footprint >= n * @sizeOf(Event));
        try std.testing.expectEqual(@as(usize, 0), footprint % scratchAlign());
        try std.testing.expectEqual(@as(usize, 0), scratchAlign() % @alignOf(Event));
        try std.testing.expectEqual(footprint, tk_topob_tickoni_tile_scratch_footprint("tkcase"));
    }
    // One more event is exactly one more capsule entry.
    setEventCount(6);
    const six = scratchFootprint();
    setEventCount(7);
    try std.testing.expect(scratchFootprint() >= six + @sizeOf(Event));
    // No event gate: the default capsule, still deterministic.
    setEventCount(0);
    try std.testing.expectEqual(scratchFootprint(), scratchFootprint());
    try std.testing.expect(scratchFootprint() > 64 * @sizeOf(Event));
}

test "tkcase wire contract — scope and lifecycle record sizes" {
    try std.testing.expectEqual(@as(usize, 72), @sizeOf(Scope));
    try std.testing.expectEqual(@as(usize, 80), @sizeOf(audit_mod.TkCaseAuditMsg));
    try std.testing.expect(@sizeOf(audit_mod.TkCaseAuditMsg) <= audit_mod.TK_CASE_AUDIT_LINK_MTU);
    try std.testing.expectEqual(@as(u8, 13), @as(u8, audit_mod.RECORD_CASE_CREATION));
    try std.testing.expectEqual(@as(u8, 14), @as(u8, audit_mod.RECORD_CASE_COMPLETION));
}
