/// Thin Zig wrapper over tk_agent_sink_stem.c — the bounded result-sink stem
/// tile registered as tkagnt. It observes the tkmodl result link; it is not an
/// agent. Accessors take the tile object's scratch base and never return a
/// child-process pointer.
const std = @import("std");
const stem_run = @import("stem_run.zig");

pub const TopoRunTile = opaque {};

const run_desc = stem_run.RunDescriptor("agent_sink", TopoRunTile);

extern fn tkagnt_tile_scratch_footprint() usize;
extern fn tkagnt_tile_scratch_align() usize;
extern fn tkagnt_set_event_count(event_count: u64) void;
extern fn tkagnt_result_count(scratch: ?*anyopaque) usize;
extern fn tkagnt_result_request_id(scratch: ?*anyopaque, idx: usize) u64;
extern fn tkagnt_result_run_id(scratch: ?*anyopaque, idx: usize) u64;
extern fn tkagnt_result_decision(scratch: ?*anyopaque, idx: usize) c_uint;
extern fn tkagnt_result_prompt_hash(scratch: ?*anyopaque, idx: usize) u64;
extern fn tkagnt_result_response_hash(scratch: ?*anyopaque, idx: usize) u64;
extern fn tkagnt_result_replay_substitution_id(scratch: ?*anyopaque, idx: usize) u64;
extern fn tkagnt_result_total_tokens(scratch: ?*anyopaque, idx: usize) c_uint;
extern fn tkagnt_result_prompt_tokens(scratch: ?*anyopaque, idx: usize) c_uint;
extern fn tkagnt_result_completion_tokens(scratch: ?*anyopaque, idx: usize) c_uint;
extern fn tkagnt_result_failed_scope_dim(scratch: ?*anyopaque, idx: usize, dst: *[32]u8) void;
extern fn tkagnt_result_model_id(scratch: ?*anyopaque, idx: usize, dst: *[32]u8) void;
extern fn tk_topob_tickoni_tile_scratch_footprint(tile_name: [*:0]const u8) usize;

pub fn getRunName() [*:0]const u8 {
    return run_desc.name();
}

pub fn getRunTile() ?*TopoRunTile {
    return run_desc.tile();
}

pub fn scratchFootprint() usize {
    return tkagnt_tile_scratch_footprint();
}

pub fn scratchAlign() usize {
    return tkagnt_tile_scratch_align();
}

pub fn setEventCount(event_count: u64) void {
    tkagnt_set_event_count(event_count);
}

/// Committed result count. Slots at or beyond it are not observable.
pub fn resultCount(scratch: ?*anyopaque) u64 {
    return tkagnt_result_count(scratch);
}

pub fn resultRequestId(scratch: ?*anyopaque, idx: usize) u64 {
    return tkagnt_result_request_id(scratch, idx);
}

pub fn resultRunId(scratch: ?*anyopaque, idx: usize) u64 {
    return tkagnt_result_run_id(scratch, idx);
}

/// `ModelDecision` tag of the result at `idx`.
pub fn resultDecision(scratch: ?*anyopaque, idx: usize) u32 {
    return tkagnt_result_decision(scratch, idx);
}

pub fn resultPromptHash(scratch: ?*anyopaque, idx: usize) u64 {
    return tkagnt_result_prompt_hash(scratch, idx);
}

pub fn resultResponseHash(scratch: ?*anyopaque, idx: usize) u64 {
    return tkagnt_result_response_hash(scratch, idx);
}

pub fn resultReplaySubstitutionId(scratch: ?*anyopaque, idx: usize) u64 {
    return tkagnt_result_replay_substitution_id(scratch, idx);
}

pub fn resultTotalTokens(scratch: ?*anyopaque, idx: usize) u32 {
    return tkagnt_result_total_tokens(scratch, idx);
}

pub fn resultPromptTokens(scratch: ?*anyopaque, idx: usize) u32 {
    return tkagnt_result_prompt_tokens(scratch, idx);
}

pub fn resultCompletionTokens(scratch: ?*anyopaque, idx: usize) u32 {
    return tkagnt_result_completion_tokens(scratch, idx);
}

pub fn resultFailedScopeDim(scratch: ?*anyopaque, idx: usize, dst: *[32]u8) void {
    tkagnt_result_failed_scope_dim(scratch, idx, dst);
}

pub fn resultModelId(scratch: ?*anyopaque, idx: usize, dst: *[32]u8) void {
    tkagnt_result_model_id(scratch, idx, dst);
}

test "tkagnt sink identity — name is TILE_ID_TKAGNT with non-null callbacks" {
    try std.testing.expectEqualStrings("tkagnt", std.mem.sliceTo(run_desc.name(), 0));
    try std.testing.expect(run_desc.run() != null);
    try std.testing.expect(run_desc.privilegedInit() != null);
    try std.testing.expect(run_desc.unprivilegedInit() != null);
    try std.testing.expect(run_desc.scratchAlign() != null);
    try std.testing.expect(run_desc.scratchFootprint() != null);
}

test "tkagnt sink scratch — aligned, larger than the placeholder, topob parity" {
    const footprint = scratchFootprint();
    try std.testing.expect(footprint > 1);
    try std.testing.expectEqual(@as(usize, 0), footprint % scratchAlign());
    try std.testing.expectEqual(footprint, tk_topob_tickoni_tile_scratch_footprint("tkagnt"));
    // Fixed across the event-count gate.
    for ([_]u64{ 0, 1, 32 }) |n| {
        setEventCount(n);
        try std.testing.expectEqual(footprint, scratchFootprint());
    }
}
