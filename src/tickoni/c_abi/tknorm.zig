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
extern fn tk_topob_tickoni_tile_scratch_footprint(tile_name: [*:0]const u8) usize;

/// RawPayment layout — must match the C struct in audit_schema.h
/// so FFI hash tests can construct identical inputs for both C and Zig.
pub const FfiRawPayment = extern struct {
    source_offset: u64,
    idempotency_key: u64,
    amount_cents: i64,
    account_id: u32,
    currency: [3]u8,
    _pad: u8 = 0,
};

/// Exported FFI function — wrapper around the static C FNV-1a implementation.
extern fn tknorm_stable_event_hash_compute(raw: *const FfiRawPayment) u64;

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

/// Construct an FfiRawPayment matching the plan's fixture:
///   idempotency_key=1, account_id=2, amount_cents=100, currency="USD"
fn makeFixture() FfiRawPayment {
    return .{
        .source_offset = 0,
        .idempotency_key = 1,
        .account_id = 2,
        .amount_cents = 100,
        .currency = .{ 'U', 'S', 'D' },
    };
}

test "FNV-1a C hash is deterministic for identical inputs" {
    var fixture = makeFixture();
    const h1 = tknorm_stable_event_hash_compute(&fixture);
    const h2 = tknorm_stable_event_hash_compute(&fixture);
    const h3 = tknorm_stable_event_hash_compute(&fixture);
    try std.testing.expectEqual(h1, h2);
    try std.testing.expectEqual(h2, h3);
    try std.testing.expect(h1 > 0);
}

test "FNV-1a C hash differs for different inputs" {
    var fixture1 = makeFixture();
    var fixture2 = makeFixture();
    fixture2.idempotency_key = 99;
    try std.testing.expect(tknorm_stable_event_hash_compute(&fixture1) !=
                            tknorm_stable_event_hash_compute(&fixture2));

    var fixture3 = makeFixture();
    fixture3.amount_cents = 9999;
    try std.testing.expect(tknorm_stable_event_hash_compute(&fixture1) !=
                            tknorm_stable_event_hash_compute(&fixture3));
}

test "FNV-1a C hash matches Zig stableEventHash" {
    var fixture = makeFixture();
    const c_hash = tknorm_stable_event_hash_compute(&fixture);

    // Inline FNV-1a matching runtime.zig:stableEventHash exactly:
    // seed=0, prime=0x100000001b3, fields: idempotency_key(u64),
    // account_id(u32), amount_cents(i64→u64 bitcast), currency(3 bytes)
    var h: u64 = 0;
    var x: u64 = fixture.idempotency_key;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        h = (h ^ @as(u64, @intCast(x & 0xff))) *% 0x100000001b3;
        x >>= 8;
    }
    x = @as(u64, @intCast(fixture.account_id));
    i = 0;
    while (i < 4) : (i += 1) {
        h = (h ^ @as(u64, @intCast(x & 0xff))) *% 0x100000001b3;
        x >>= 8;
    }
    x = @bitCast(fixture.amount_cents);
    i = 0;
    while (i < 8) : (i += 1) {
        h = (h ^ @as(u64, @intCast(x & 0xff))) *% 0x100000001b3;
        x >>= 8;
    }
    h = (h ^ @as(u64, fixture.currency[0])) *% 0x100000001b3;
    h = (h ^ @as(u64, fixture.currency[1])) *% 0x100000001b3;
    h = (h ^ @as(u64, fixture.currency[2])) *% 0x100000001b3;

    try std.testing.expectEqual(c_hash, h);
}

test "FNV-1a hash matches expected value from fixture" {
    var fixture = makeFixture();
    const c_hash = tknorm_stable_event_hash_compute(&fixture);

    // Manually compute FNV-1a for the fixture:
    // Fields: idempotency_key=1, account_id=2, amount_cents=100, currency="USD"
    // Seed = 0 (AUDIT_INITIAL_HASH)
    // Algorithm: h = (h ^ byte) * 0x100000001b3 for each byte, little-endian

    var h: u64 = 0;
    // Hash idempotency_key=1 (8 bytes LE: 01 00 00 00 00 00 00 00)
    var x: u64 = 1;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        h = (h ^ @as(u64, @intCast(x & 0xff))) *% 0x100000001b3;
        x >>= 8;
    }
    // Hash account_id=2 (4 bytes LE: 02 00 00 00)
    x = 2;
    i = 0;
    while (i < 4) : (i += 1) {
        h = (h ^ @as(u64, @intCast(x & 0xff))) *% 0x100000001b3;
        x >>= 8;
    }
    // Hash amount_cents=100 (i64→u64, 8 bytes LE: 64 00 00 00 00 00 00 00)
    x = @bitCast(@as(i64, 100));
    i = 0;
    while (i < 8) : (i += 1) {
        h = (h ^ @as(u64, @intCast(x & 0xff))) *% 0x100000001b3;
        x >>= 8;
    }
    // Hash currency "USD" (3 bytes: 55 53 44)
    h = (h ^ 0x55) *% 0x100000001b3; // 'U'
    h = (h ^ 0x53) *% 0x100000001b3; // 'S'
    h = (h ^ 0x44) *% 0x100000001b3; // 'D'

    try std.testing.expectEqual(c_hash, h);
}
