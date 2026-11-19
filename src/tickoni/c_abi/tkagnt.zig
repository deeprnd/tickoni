/// Thin Zig wrapper over tk_agent_stem.c — the Firedancer stem tile for the
/// tkagnt agent worker. Accessors take the tile object's scratch base and never
/// return a child-process pointer. The agent's routing and result-interpretation
/// decisions are Zig's and reach the tile through `setHooks`.
const std = @import("std");
const stem_run = @import("stem_run.zig");
const audit_mod = @import("audit_mod");

pub const TopoRunTile = opaque {};

/// The two Zig-owned decision hooks (tk_agent_hooks.h).
pub const Hooks = audit_mod.TkAgentHooks;

const run_desc = stem_run.RunDescriptor("agent", TopoRunTile);

extern fn tkagnt_tile_scratch_footprint() usize;
extern fn tkagnt_tile_scratch_align() usize;
extern fn tkagnt_set_event_count(event_count: u64) void;
extern fn tkagnt_set_hooks(hooks: ?*const Hooks) c_int;
extern fn tkagnt_set_route(tier: u8, kind_id: u8) c_int;
extern fn tkagnt_admitted(scratch: ?*anyopaque) usize;
extern fn tkagnt_terminal_done(scratch: ?*anyopaque) usize;
extern fn tkagnt_dispatched(scratch: ?*anyopaque) usize;
extern fn tkagnt_results(scratch: ?*anyopaque) usize;
extern fn tkagnt_denied(scratch: ?*anyopaque) usize;
extern fn tkagnt_tokens(scratch: ?*anyopaque) usize;
extern fn tkagnt_embeddings(scratch: ?*anyopaque) usize;
extern fn tkagnt_mismatched(scratch: ?*anyopaque) usize;
extern fn tkagnt_transport_dropped(scratch: ?*anyopaque) usize;
extern fn tk_topob_tickoni_tile_scratch_footprint(tile_name: [*:0]const u8) usize;

pub const wire_version: u16 = audit_mod.TK_AGENT_WIRE_VERSION;

/// Tier ordinal meaning "none" in a terminal result.
pub const tier_none: u8 = audit_mod.TK_AGENT_TIER_NONE;

/// Terminal outcome of one agent run (`TkAgentResultMsg.outcome`).
pub const Outcome = enum(u8) {
    ok = audit_mod.TK_AGENT_OUT_OK,
    deny_invalid_request = audit_mod.TK_AGENT_OUT_DENY_INVALID_REQUEST,
    deny_absent_tier = audit_mod.TK_AGENT_OUT_DENY_ABSENT_TIER,
    model_denied = audit_mod.TK_AGENT_OUT_MODEL_DENIED,
    invalid_content = audit_mod.TK_AGENT_OUT_INVALID_CONTENT,
    invalid_tier = audit_mod.TK_AGENT_OUT_INVALID_TIER,
    content_too_large = audit_mod.TK_AGENT_OUT_CONTENT_TOO_LARGE,
    model_timeout = audit_mod.TK_AGENT_OUT_MODEL_TIMEOUT,
    transport_failure = audit_mod.TK_AGENT_OUT_TRANSPORT_FAILURE,
    result_mismatch = audit_mod.TK_AGENT_OUT_RESULT_MISMATCH,
    capacity = audit_mod.TK_AGENT_OUT_CAPACITY,
    shutdown = audit_mod.TK_AGENT_OUT_SHUTDOWN,
};

/// A classifier result's reported confidence (`TkAgentResultMsg.confidence`).
pub const Confidence = enum(u8) {
    none = audit_mod.TK_AGENT_CONF_NONE,
    low = audit_mod.TK_AGENT_CONF_LOW,
    medium = audit_mod.TK_AGENT_CONF_MEDIUM,
    high = audit_mod.TK_AGENT_CONF_HIGH,
};

pub const ConfigError = error{ MissingHook, UnknownTier, DuplicateTier, DuplicateKind, Unknown };

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

/// Registers the Zig-owned decision hooks for this process. The tile refuses to
/// start without them: it never decides routing itself.
pub fn setHooks(hooks: *const Hooks) ConfigError!void {
    if (tkagnt_set_hooks(hooks) != 0) return error.MissingHook;
}

/// Declares that tier ordinal `tier` is served by the tkmodl instance whose
/// Firedancer kind_id is `kind_id`. The tile binds its request and result links
/// from these declarations and the verified channel endpoints.
pub fn setRoute(tier: u8, kind_id: u8) ConfigError!void {
    return switch (tkagnt_set_route(tier, kind_id)) {
        0 => {},
        1 => error.UnknownTier,
        2 => error.DuplicateTier,
        3 => error.DuplicateKind,
        else => error.Unknown,
    };
}

/// Agent requests accepted: each is one run and ends in one terminal result.
pub fn admitted(scratch: ?*anyopaque) u64 {
    return tkagnt_admitted(scratch);
}

/// Terminal results published (after their audit record was committed).
pub fn terminalDone(scratch: ?*anyopaque) u64 {
    return tkagnt_terminal_done(scratch);
}

pub fn dispatched(scratch: ?*anyopaque) u64 {
    return tkagnt_dispatched(scratch);
}

pub fn results(scratch: ?*anyopaque) u64 {
    return tkagnt_results(scratch);
}

pub fn denied(scratch: ?*anyopaque) u64 {
    return tkagnt_denied(scratch);
}

pub fn tokens(scratch: ?*anyopaque) u64 {
    return tkagnt_tokens(scratch);
}

pub fn embeddings(scratch: ?*anyopaque) u64 {
    return tkagnt_embeddings(scratch);
}

/// Results that matched no pending dispatch (unknown, duplicate, stale, or
/// from the wrong model): counted and ignored, never completing a run.
pub fn mismatched(scratch: ?*anyopaque) u64 {
    return tkagnt_mismatched(scratch);
}

/// Request or result streams dropped for a framing fault.
pub fn transportDropped(scratch: ?*anyopaque) u64 {
    return tkagnt_transport_dropped(scratch);
}

test "tkagnt identity — name is TILE_ID_TKAGNT with non-null callbacks" {
    try std.testing.expectEqualStrings("tkagnt", std.mem.sliceTo(run_desc.name(), 0));
    try std.testing.expect(run_desc.run() != null);
    try std.testing.expect(run_desc.privilegedInit() != null);
    try std.testing.expect(run_desc.unprivilegedInit() != null);
    try std.testing.expect(run_desc.scratchAlign() != null);
    try std.testing.expect(run_desc.scratchFootprint() != null);
}

test "tkagnt scratch — aligned, covers the message buffers, topob parity" {
    const footprint = scratchFootprint();
    // One reassembly buffer per input (request + one per tier) and the request
    // slots are each a full multipart message.
    try std.testing.expect(footprint > (audit_mod.TK_AGENT_TIER_COUNT + 1) * audit_mod.TK_MP_MAX_MESSAGE_BYTES);
    try std.testing.expectEqual(@as(usize, 0), footprint % scratchAlign());
    try std.testing.expectEqual(footprint, tk_topob_tickoni_tile_scratch_footprint("tkagnt"));
    // Fixed across the event-count gate.
    for ([_]u64{ 0, 1, 32 }) |n| {
        setEventCount(n);
        try std.testing.expectEqual(footprint, scratchFootprint());
    }
}

test "tkagnt route declarations are validated" {
    // A tier outside the supported set, and a tier or an instance declared twice.
    try std.testing.expectError(error.UnknownTier, setRoute(audit_mod.TK_AGENT_TIER_COUNT, 0));
    try setRoute(3, 5);
    try std.testing.expectError(error.DuplicateTier, setRoute(3, 6));
    try std.testing.expectError(error.DuplicateKind, setRoute(4, 5));
}

test "tkagnt refuses a hook table with a missing hook" {
    var hooks = std.mem.zeroes(Hooks);
    try std.testing.expectError(error.MissingHook, setHooks(&hooks));
}
