/// Thin Zig wrapper over tk_normalize_stem.c — the Firedancer stem tile for tknorm.
///
/// Exposes the C stem tile's public symbols (run tile descriptor, scratch
/// footprint, field accessors) as extern declarations with Zig-native wrapper
/// functions. This module is the FFI boundary for the tknorm stem tile.
const std = @import("std");

// ---------------------------------------------------------------------------
// Extern declarations — from c_abi/shim/tk_normalize_stem.c
// Link requires tk_normalize_stem.c (supervisor shim library).
// ---------------------------------------------------------------------------

/// Opaque handle for fd_topo_run_tile_t. Only shim code knows the real layout.
pub const TopoRunTile = opaque {};

extern fn tk_get_norm_run_name() [*:0]const u8;
extern fn tk_get_norm_run_tile() ?*TopoRunTile;
extern fn tk_get_norm_run_run() ?*anyopaque;
extern fn tk_get_norm_run_scratch_align() ?*anyopaque;
extern fn tk_get_norm_run_scratch_footprint() ?*anyopaque;
extern fn tk_get_norm_run_privileged_init() ?*anyopaque;
extern fn tk_get_norm_run_unprivileged_init() ?*anyopaque;
extern fn tknorm_tile_scratch_footprint() usize;
extern fn tknorm_tile_scratch_align() usize;
extern fn tk_topob_tickoni_tile_scratch_footprint(tile_name: [*:0]const u8) usize;
extern fn tknorm_set_event_count(event_count: usize) void;

pub const TkEvent = @import("audit_mod").TkEvent;

/// Exported FFI wrappers around the C canonical hash and kind validation.
extern fn tknorm_event_hash_compute(ev: *const TkEvent) u64;
extern fn tknorm_event_valid_compute(ev: *const TkEvent) c_int;

/// tknorm's canonical event hash of `ev`.
pub fn eventHash(ev: *const TkEvent) u64 {
    return tknorm_event_hash_compute(ev);
}

/// Whether tknorm accepts the kind's fields of `ev`.
pub fn eventValid(ev: *const TkEvent) bool {
    return tknorm_event_valid_compute(ev) != 0;
}

// ---------------------------------------------------------------------------
// Public Zig wrappers.
// ---------------------------------------------------------------------------

/// Returns the tile name for tknorm.
pub fn getNormRunName() [*:0]const u8 {
    return tk_get_norm_run_name();
}

/// Returns a pointer to the TK_NORM_RUN tile descriptor.
pub fn getNormRunTile() ?*TopoRunTile {
    return tk_get_norm_run_tile();
}

/// Returns the stem run callback pointer.
pub fn getNormRun() ?*anyopaque {
    return tk_get_norm_run_run();
}

/// Returns the scratch align callback pointer.
pub fn getNormRunScratchAlign() ?*anyopaque {
    return tk_get_norm_run_scratch_align();
}

/// Returns the scratch footprint callback pointer.
pub fn getNormRunScratchFootprint() ?*anyopaque {
    return tk_get_norm_run_scratch_footprint();
}

/// Returns the privileged init callback pointer.
pub fn getNormRunPrivilegedInit() ?*anyopaque {
    return tk_get_norm_run_privileged_init();
}

/// Returns the unprivileged init callback pointer.
pub fn getNormRunUnprivilegedInit() ?*anyopaque {
    return tk_get_norm_run_unprivileged_init();
}

/// Returns the scratch footprint (in bytes) for the tknorm tile.
pub fn normScratchFootprint() usize {
    return tknorm_tile_scratch_footprint();
}

/// Sets the event_count for the tknorm stem tile's shutdown gate.
/// Called by topo_build.build() before any topology queries.
pub fn setEventCount(event_count: u64) void {
    tknorm_set_event_count(@intCast(event_count));
}

// ---------------------------------------------------------------------------
// Identity tests — verify the C stem symbols are linked and accessible.
// These are compile-time linkage checks; they do not require a running pipeline.
// ---------------------------------------------------------------------------

test "tknorm tile identity — name is TILE_ID_TKNORM" {
    const name = std.mem.sliceTo(tk_get_norm_run_name(), 0);
    try std.testing.expectEqualStrings("tknorm", name);
}

test "tknorm tile identity — run callback is non-null" {
    try std.testing.expect(tk_get_norm_run_run() != null);
}

test "tknorm tile identity — scratch callbacks are non-null" {
    try std.testing.expect(tk_get_norm_run_scratch_align() != null);
    try std.testing.expect(tk_get_norm_run_scratch_footprint() != null);
}

test "tknorm scratch align — describes the context block, not fd_stem's stack scratch" {
    // 16: the strictest of tknorm_ctx_t and the output TkEvent the same
    // footprint carves out of the same block (TkEvent is 16-aligned by its
    // 16-byte trace_id).
    //
    // 128 (FD_STEM_SCRATCH_ALIGN) here means .scratch_align was wired to the
    // STEM-generated tknorm_scratch_align() from fd_stem.c, which describes
    // fd_stem's own stack scratch: a different block from the one
    // .scratch_footprint reserves.  See "Tile Scratch Layout" in
    // doc/execution/contribution/tickoni.md.
    try std.testing.expectEqual(@as(usize, 16), tknorm_tile_scratch_align());
}

test "tknorm scratch align — footprint is a whole number of alignment units" {
    try std.testing.expectEqual(
        @as(usize, 0),
        tknorm_tile_scratch_footprint() % tknorm_tile_scratch_align(),
    );
}

test "tknorm tile identity — init callbacks are non-null" {
    try std.testing.expect(tk_get_norm_run_privileged_init() != null);
    try std.testing.expect(tk_get_norm_run_unprivileged_init() != null);
}

test "tknorm scratch footprint — returns deterministic value > 1" {
    const footprint = tknorm_tile_scratch_footprint();
    try std.testing.expect(footprint > 1);
    try std.testing.expectEqual(footprint, tknorm_tile_scratch_footprint());
}

test "tknorm scratch footprint — topob wrapper matches direct call" {
    const direct = tknorm_tile_scratch_footprint();
    const via_topob = tk_topob_tickoni_tile_scratch_footprint("tknorm");
    try std.testing.expectEqual(direct, via_topob);
}

// ---------------------------------------------------------------------------
// FNV-1a hash parity tests — C vs Zig stableEventHash
// ---------------------------------------------------------------------------

const audit_mod = @import("audit_mod");

/// A payment event matching the plan's fixture:
///   idempotency_key=1, account_id=2, amount_cents=100, currency="USD"
fn makeFixture() TkEvent {
    var ev = std.mem.zeroes(TkEvent);
    ev.version = audit_mod.TK_EVENT_WIRE_VERSION;
    ev.kind = audit_mod.TK_EVENT_KIND_PAYMENT;
    ev.source = audit_mod.TK_EVENT_SOURCE_TKAPI;
    ev.trace_id = 1;
    ev.idempotency_key = 1;
    ev.body.payment.account_id = 2;
    ev.body.payment.amount_cents = 100;
    ev.body.payment.currency = .{ 'U', 'S', 'D' };
    return ev;
}

fn fnv(h: *u64, x: u64, n: usize) void {
    var v = x;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        h.* = (h.* ^ (v & 0xff)) *% 0x100000001b3;
        v >>= 8;
    }
}

test "FNV-1a C hash is deterministic for identical inputs" {
    const fixture = makeFixture();
    const h1 = eventHash(&fixture);
    try std.testing.expectEqual(h1, eventHash(&fixture));
    try std.testing.expectEqual(h1, eventHash(&fixture));
    try std.testing.expect(h1 > 0);
}

test "FNV-1a C hash differs for different inputs" {
    const fixture1 = makeFixture();
    var fixture2 = makeFixture();
    fixture2.idempotency_key = 99;
    try std.testing.expect(eventHash(&fixture1) != eventHash(&fixture2));
    var fixture3 = makeFixture();
    fixture3.body.payment.amount_cents = 9999;
    try std.testing.expect(eventHash(&fixture1) != eventHash(&fixture3));
}

test "the payment hash ignores the envelope fields tiles stamp" {
    const fixture = makeFixture();
    var stamped = makeFixture();
    stamped.trace_id = 77;
    stamped.source_offset = 5;
    stamped.pipeline_hops = 3;
    stamped.case_id = 9;
    try std.testing.expectEqual(eventHash(&fixture), eventHash(&stamped));
}

test "FNV-1a payment hash matches expected value from fixture" {
    // Fields: idempotency_key=1 (u64), account_id=2 (u32), amount_cents=100
    // (i64->u64), currency "USD"; seed 0 (AUDIT_INITIAL_HASH), little-endian.
    // The same order as runtime.zig:stableEventHash.
    const fixture = makeFixture();
    var h: u64 = 0;
    fnv(&h, 1, 8);
    fnv(&h, 2, 4);
    fnv(&h, @bitCast(@as(i64, 100)), 8);
    for ("USD") |c| h = (h ^ @as(u64, c)) *% 0x100000001b3;
    try std.testing.expectEqual(eventHash(&fixture), h);
}

fn agentFixture() TkEvent {
    var ev = makeFixture();
    ev.kind = audit_mod.TK_EVENT_KIND_AGENT_REQUEST;
    ev.body = std.mem.zeroes(@TypeOf(ev.body));
    const r = &ev.body.agent_request;
    r.version = audit_mod.TK_AGENT_WIRE_VERSION;
    r.request_type = audit_mod.TK_AGENT_REQ_CHAT;
    r.requested_tier = 6;
    r.prompt_ref.prompt_hash = 0xabcdef;
    r.prompt_ref.prompt_len = 96;
    r.scope.version = audit_mod.TKMODL_WIRE_VERSION;
    r.scope.replay_substitution_id = 1000;
    return ev;
}

test "an agent request's hash is its content, not the identities tiles stamp" {
    const base = agentFixture();
    var stamped = agentFixture();
    stamped.trace_id = 42;
    stamped.body.agent_request.scope.run_id = 5;
    stamped.body.agent_request.scope.trace_id = 42;
    stamped.body.agent_request.scope.request_id = 3;
    stamped.body.agent_request.scope.prompt_hash = 0x99;
    try std.testing.expectEqual(eventHash(&base), eventHash(&stamped));

    var other = agentFixture();
    other.body.agent_request.prompt_ref.prompt_hash = 0xabcdee;
    try std.testing.expect(eventHash(&base) != eventHash(&other));
    var tier = agentFixture();
    tier.body.agent_request.requested_tier = 7;
    try std.testing.expect(eventHash(&base) != eventHash(&tier));
    // The kind is part of the hash: a payment never collides with a request.
    try std.testing.expect(eventHash(&base) != eventHash(&makeFixture()));
}

test "tknorm validates each kind's own fields" {
    try std.testing.expect(eventValid(&makeFixture()));
    var bad_currency = makeFixture();
    bad_currency.body.payment.currency = .{ 'E', 'U', 'R' };
    try std.testing.expect(!eventValid(&bad_currency));
    var zero = makeFixture();
    zero.body.payment.amount_cents = 0;
    try std.testing.expect(!eventValid(&zero));
    var flagged = makeFixture();
    flagged.body.payment.malformed = 1;
    try std.testing.expect(!eventValid(&flagged));

    try std.testing.expect(eventValid(&agentFixture()));
    var no_prompt = agentFixture();
    no_prompt.body.agent_request.prompt_ref.prompt_len = 0;
    try std.testing.expect(!eventValid(&no_prompt));
    var huge = agentFixture();
    huge.body.agent_request.prompt_ref.prompt_len = audit_mod.TKAGNT_PROMPT_MAX_BYTES + 1;
    try std.testing.expect(!eventValid(&huge));
    var bad_type = agentFixture();
    bad_type.body.agent_request.request_type = 9;
    try std.testing.expect(!eventValid(&bad_type));
    var bad_wire = agentFixture();
    bad_wire.body.agent_request.version = audit_mod.TK_AGENT_WIRE_VERSION + 1;
    try std.testing.expect(!eventValid(&bad_wire));
    var bad_scope = agentFixture();
    bad_scope.body.agent_request.scope.version = audit_mod.TKMODL_WIRE_VERSION + 1;
    try std.testing.expect(!eventValid(&bad_scope));
}
