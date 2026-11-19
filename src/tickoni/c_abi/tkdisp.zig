/// Thin Zig wrapper over tk_disp_stem.c — the bounded sink stem registered as
/// tkdisp. It consumes tkagnt's terminal-result link and keeps each committed
/// result in a fixed ring for inspection. Accessors take the tile object's
/// scratch base and never return a child-process pointer.
const std = @import("std");
const stem_run = @import("stem_run.zig");
const audit_mod = @import("audit_mod");

pub const TopoRunTile = opaque {};

/// One terminal agent result (tk_agent_wire.h): hashes and status, no content.
pub const Result = audit_mod.TkAgentResultMsg;

const run_desc = stem_run.RunDescriptor("disp", TopoRunTile);

extern fn tkdisp_tile_scratch_footprint() usize;
extern fn tkdisp_tile_scratch_align() usize;
extern fn tkdisp_set_event_count(event_count: u64) void;
extern fn tkdisp_set_template(hdr: ?*const audit_mod.TkAgentRequestHdr, prompt: ?[*]const u8, prompt_len: usize) c_int;
extern fn tkdisp_scheduled(scratch: ?*anyopaque) usize;
extern fn tkdisp_events_seen(scratch: ?*anyopaque) usize;
extern fn tkdisp_result_count(scratch: ?*anyopaque) usize;
extern fn tkdisp_result_copy(scratch: ?*anyopaque, idx: usize, dst: *anyopaque, dst_sz: usize) void;
extern fn tk_topob_tickoni_tile_scratch_footprint(tile_name: [*:0]const u8) usize;

pub fn getRunName() [*:0]const u8 {
    return run_desc.name();
}

pub fn getRunTile() ?*TopoRunTile {
    return run_desc.tile();
}

pub fn scratchFootprint() usize {
    return tkdisp_tile_scratch_footprint();
}

pub fn scratchAlign() usize {
    return tkdisp_tile_scratch_align();
}

pub fn setEventCount(event_count: u64) void {
    tkdisp_set_event_count(event_count);
}

pub const TemplateError = error{ BadHeader, BadPrompt, Unknown };

/// Installs the request template a scheduler-shaped tkdisp sends for each event
/// it receives. The tier, scope and prompt come from the template, never from
/// the event's contents.
pub fn setTemplate(hdr: *const audit_mod.TkAgentRequestHdr, prompt: []const u8) TemplateError!void {
    return switch (tkdisp_set_template(hdr, prompt.ptr, prompt.len)) {
        0 => {},
        1, 2 => error.BadHeader,
        3 => error.BadPrompt,
        else => error.Unknown,
    };
}

/// `setTemplate` from one request body: a `TkAgentRequestHdr` followed by the
/// prompt bytes, the form the request source builds.
pub fn setTemplateBody(body: []const u8) TemplateError!void {
    const hdr_len = @sizeOf(audit_mod.TkAgentRequestHdr);
    if (body.len <= hdr_len) return error.BadPrompt;
    var hdr: audit_mod.TkAgentRequestHdr = undefined;
    @memcpy(std.mem.asBytes(&hdr), body[0..hdr_len]);
    return setTemplate(&hdr, body[hdr_len..]);
}

/// Requests a scheduler-shaped tkdisp has started.
pub fn scheduled(scratch: ?*anyopaque) u64 {
    return tkdisp_scheduled(scratch);
}

/// Events a scheduler-shaped tkdisp has received.
pub fn eventsSeen(scratch: ?*anyopaque) u64 {
    return tkdisp_events_seen(scratch);
}

/// Committed result count. Slots at or beyond it are not observable.
pub fn resultCount(scratch: ?*anyopaque) u64 {
    return tkdisp_result_count(scratch);
}

/// Copies committed result `idx` out of the tile's scratch.
pub fn result(scratch: ?*anyopaque, idx: usize) Result {
    var out: Result = undefined;
    tkdisp_result_copy(scratch, idx, &out, @sizeOf(Result));
    return out;
}

test "tkdisp identity — name is TILE_ID_TKDISP with non-null callbacks" {
    try std.testing.expectEqualStrings("tkdisp", std.mem.sliceTo(run_desc.name(), 0));
    try std.testing.expect(run_desc.run() != null);
    try std.testing.expect(run_desc.privilegedInit() != null);
    try std.testing.expect(run_desc.unprivilegedInit() != null);
    try std.testing.expect(run_desc.scratchAlign() != null);
    try std.testing.expect(run_desc.scratchFootprint() != null);
}

test "tkdisp scratch — aligned, covers the result ring and request buffer, topob parity" {
    const footprint = scratchFootprint();
    try std.testing.expect(footprint > 256 * @sizeOf(Result) + audit_mod.TK_MP_MAX_MESSAGE_BYTES);
    try std.testing.expectEqual(@as(usize, 0), footprint % scratchAlign());
    try std.testing.expectEqual(footprint, tk_topob_tickoni_tile_scratch_footprint("tkdisp"));
    for ([_]u64{ 0, 1, 32 }) |n| {
        setEventCount(n);
        try std.testing.expectEqual(footprint, scratchFootprint());
    }
}

test "tkdisp refuses a template that is not a well-formed agent request" {
    var hdr = std.mem.zeroes(audit_mod.TkAgentRequestHdr);
    try std.testing.expectError(error.BadHeader, setTemplate(&hdr, "prompt")); // wire version 0
    hdr.version = audit_mod.TK_AGENT_WIRE_VERSION;
    try std.testing.expectError(error.BadPrompt, setTemplate(&hdr, "")); // no prompt
    var big: [64 * 1024 + 1]u8 = undefined;
    @memset(&big, 'x');
    try std.testing.expectError(error.BadPrompt, setTemplate(&hdr, &big)); // over the template bound
}
