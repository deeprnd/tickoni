/// Thin Zig wrapper over tk_repl_stem.c — tkrepl, the replay tile of the
/// investment workflow's side-channel. It folds the case capsule tkcase streams
/// it, asks the Zig verdict (tiles/replay/decision.zig, installed through
/// `setHooks`) whether it matches what tkcase recorded, and reports the verdict
/// to tkaudt (RECORD_REPLAY_RESULT) and on its CNC slots 0 (replay_checked) and
/// 1 (replay_match). Accessors take the tile object's scratch base and never
/// return a child-process pointer.
const std = @import("std");
const stem_run = @import("stem_run.zig");
const audit_mod = @import("audit_mod");

pub const TopoRunTile = opaque {};

/// The Zig-owned verdict hook (tkrepl_frag.h).
pub const Hooks = audit_mod.TkReplHooks;
/// The verdict as the tile holds it.
pub const Verdict = audit_mod.TkReplVerifyDirective;

const run_desc = stem_run.RunDescriptor("replay", TopoRunTile);

extern fn tkrepl_tile_scratch_footprint() usize;
extern fn tkrepl_tile_scratch_align() usize;
extern fn tkrepl_set_hooks(hooks: ?*const Hooks) c_int;
extern fn tkrepl_replay_checked(scratch: ?*anyopaque) usize;
extern fn tkrepl_replay_match(scratch: ?*anyopaque) usize;
extern fn tkrepl_observed_count(scratch: ?*anyopaque) usize;
extern fn tkrepl_observed_hash(scratch: ?*anyopaque) usize;
extern fn tkrepl_rejected(scratch: ?*anyopaque) usize;
extern fn tkrepl_verdict_copy(scratch: ?*anyopaque, dst: *anyopaque, dst_sz: usize) void;
extern fn tk_topob_tickoni_tile_scratch_footprint(tile_name: [*:0]const u8) usize;

pub const wire_version: u16 = audit_mod.TK_REPL_WIRE_VERSION;

pub fn getRunName() [*:0]const u8 {
    return run_desc.name();
}

pub fn getRunTile() ?*TopoRunTile {
    return run_desc.tile();
}

pub fn scratchFootprint() usize {
    return tkrepl_tile_scratch_footprint();
}

pub fn scratchAlign() usize {
    return tkrepl_tile_scratch_align();
}

/// Registers the Zig-owned verdict hook for this process. A tile with a
/// capsule input refuses to start without it: it never decides a divergence
/// itself.
pub fn setHooks(hooks: *const Hooks) error{MissingHook}!void {
    if (tkrepl_set_hooks(hooks) != 0) return error.MissingHook;
}

/// True once the verdict is reported.
pub fn replayChecked(scratch: ?*anyopaque) bool {
    return tkrepl_replay_checked(scratch) != 0;
}

/// True when the verdict found no divergence (meaningful once checked).
pub fn replayMatch(scratch: ?*anyopaque) bool {
    return tkrepl_replay_match(scratch) != 0;
}

/// Capsule events tkrepl folded.
pub fn observedCount(scratch: ?*anyopaque) u64 {
    return tkrepl_observed_count(scratch);
}

/// The capsule hash of the events tkrepl folded (tk_capsule_hash.h).
pub fn observedHash(scratch: ?*anyopaque) u64 {
    return tkrepl_observed_hash(scratch);
}

/// Fragments refused: wrong sig, size or framing, or after the verdict.
pub fn rejected(scratch: ?*anyopaque) u64 {
    return tkrepl_rejected(scratch);
}

/// Copies the verdict out of the tile's scratch.
pub fn verdict(scratch: ?*anyopaque) Verdict {
    var out: Verdict = undefined;
    tkrepl_verdict_copy(scratch, &out, @sizeOf(Verdict));
    return out;
}

test "tkrepl identity — name is TILE_ID_TKREPL with non-null callbacks" {
    try std.testing.expectEqualStrings("tkrepl", std.mem.sliceTo(run_desc.name(), 0));
    try std.testing.expect(run_desc.tile() != null);
    try std.testing.expect(run_desc.run() != null);
    try std.testing.expect(run_desc.privilegedInit() != null);
    try std.testing.expect(run_desc.unprivilegedInit() != null);
    try std.testing.expect(run_desc.scratchAlign() != null);
    try std.testing.expect(run_desc.scratchFootprint() != null);
}

test "tkrepl scratch — deterministic, aligned, topob parity" {
    const footprint = scratchFootprint();
    try std.testing.expect(footprint > 0);
    try std.testing.expectEqual(footprint, scratchFootprint());
    try std.testing.expectEqual(@as(usize, 0), footprint % scratchAlign());
    try std.testing.expectEqual(footprint, tk_topob_tickoni_tile_scratch_footprint("tkrepl"));
}

test "tkrepl hooks — a missing verdict hook is refused" {
    const empty: Hooks = .{ .verify = null };
    try std.testing.expectError(error.MissingHook, setHooks(&empty));
}

test "tkrepl wire contract — summary, audit message and verdict sizes" {
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(audit_mod.TkCaseCapsuleMsg));
    try std.testing.expectEqual(@as(usize, 80), @sizeOf(audit_mod.TkReplAuditMsg));
    try std.testing.expect(@sizeOf(audit_mod.TkReplAuditMsg) <= audit_mod.TK_REPL_AUDIT_LINK_MTU);
    try std.testing.expect(@sizeOf(audit_mod.TkEvent) <= audit_mod.TK_REPL_CAPSULE_LINK_MTU);
    try std.testing.expectEqual(@as(usize, 128), @sizeOf(audit_mod.TkReplVerifyQuery));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(Verdict));
    try std.testing.expectEqual(@as(u8, 11), @as(u8, audit_mod.RECORD_REPLAY_RESULT));
}
