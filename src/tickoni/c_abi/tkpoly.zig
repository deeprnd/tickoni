/// Thin Zig wrapper over tk_policy_stem.c — the Firedancer stem tile for tkpoly.
///
/// Exposes the C stem tile's public symbols (run tile descriptor, scratch
/// footprint, field accessors) as extern declarations with Zig-native wrapper
/// functions. This module is the FFI boundary for the tkpoly stem tile.
const std = @import("std");

// ---------------------------------------------------------------------------
// Extern declarations — from c_abi/shim/tk_policy_stem.c
// Link requires tk_policy_stem.c (supervisor shim library).
// ---------------------------------------------------------------------------

/// Opaque handle for fd_topo_run_tile_t. Only shim code knows the real layout.
pub const TopoRunTile = opaque {};

extern fn tk_get_policy_run_name() [*:0]const u8;
extern fn tk_get_policy_run_tile() ?*TopoRunTile;
extern fn tk_get_policy_run_run() ?*anyopaque;
extern fn tk_get_policy_run_scratch_align() ?*anyopaque;
extern fn tk_get_policy_run_scratch_footprint() ?*anyopaque;
extern fn tk_get_policy_run_privileged_init() ?*anyopaque;
extern fn tk_get_policy_run_unprivileged_init() ?*anyopaque;
extern fn tkpoly_tile_scratch_footprint() usize;
extern fn tkpoly_tile_scratch_align() usize;
extern fn tkpoly_set_policy_limit_cents(policy_limit_cents: i64) void;
extern fn tkpoly_set_event_count(event_count: u64) void;
extern fn tkpoly_policy_helper(
    decision: u8,
    is_duplicate: c_int,
    amount_cents: i64,
    policy_limit_cents: i64,
) u8;
extern fn tk_topob_tickoni_tile_scratch_footprint(tile_name: [*:0]const u8) usize;

// ---------------------------------------------------------------------------
// Public Zig wrappers.
// ---------------------------------------------------------------------------

/// Returns the tile name for tkpoly.
pub fn getPolicyRunName() [*:0]const u8 {
    return tk_get_policy_run_name();
}

/// Returns a pointer to the TK_POLICY_RUN tile descriptor.
pub fn getPolicyRunTile() ?*TopoRunTile {
    return tk_get_policy_run_tile();
}

/// Returns the stem run callback pointer.
pub fn getPolicyRun() ?*anyopaque {
    return tk_get_policy_run_run();
}

/// Returns the scratch align callback pointer.
pub fn getPolicyRunScratchAlign() ?*anyopaque {
    return tk_get_policy_run_scratch_align();
}

/// Returns the scratch footprint callback pointer.
pub fn getPolicyRunScratchFootprint() ?*anyopaque {
    return tk_get_policy_run_scratch_footprint();
}

/// Returns the privileged init callback pointer.
pub fn getPolicyRunPrivilegedInit() ?*anyopaque {
    return tk_get_policy_run_privileged_init();
}

/// Returns the unprivileged init callback pointer.
pub fn getPolicyRunUnprivilegedInit() ?*anyopaque {
    return tk_get_policy_run_unprivileged_init();
}

/// Returns the scratch footprint (in bytes) for the tkpoly tile.
pub fn policyScratchFootprint() usize {
    return tkpoly_tile_scratch_footprint();
}

/// Returns the alignment (in bytes) of the tkpoly tile's scratch object —
/// the block holding the context and the output message.
pub fn policyScratchAlign() usize {
    return tkpoly_tile_scratch_align();
}

/// Sets the policy limit in cents for this process.
///
/// Zero is a valid configured policy limit; callers must set it explicitly.
pub fn setPolicyLimitCents(policy_limit_cents: i64) void {
    tkpoly_set_policy_limit_cents(policy_limit_cents);
}

/// Sets the event count for this process.
///
/// This value gates the tile's shutdown when it processes N events.
/// The supervisor and every child must pass the identical value.
pub fn setEventCount(event_count: u64) void {
    tkpoly_set_event_count(event_count);
}

/// Evaluates the preserved tkpoly outcome chain without mutating tile state.
pub fn policyOutcome(
    incoming_decision: u8,
    is_duplicate: bool,
    amount_cents: i64,
    policy_limit_cents: i64,
) u8 {
    return tkpoly_policy_helper(
        incoming_decision,
        @intFromBool(is_duplicate),
        amount_cents,
        policy_limit_cents,
    );
}

// ---------------------------------------------------------------------------
// Identity tests — verify the C stem symbols are linked and accessible.
// These are compile-time linkage checks; they do not require a running pipeline.
// ---------------------------------------------------------------------------

test "tkpoly tile identity — name is TILE_ID_TKPOLY" {
    const name = std.mem.sliceTo(tk_get_policy_run_name(), 0);
    try std.testing.expectEqualStrings("tkpoly", name);
}

test "tkpoly tile identity — run callback is non-null" {
    try std.testing.expect(tk_get_policy_run_run() != null);
}

test "tkpoly tile identity — scratch callbacks are non-null" {
    try std.testing.expect(tk_get_policy_run_scratch_align() != null);
    try std.testing.expect(tk_get_policy_run_scratch_footprint() != null);
}

test "tkpoly scratch align — describes the context block, not fd_stem's stack scratch" {
    // alignof(tkpoly_ctx_t) == 8: the context holds u64s, pointers and ints,
    // and PaymentMessage — which the same footprint carves out of the same
    // block — is 8-aligned too.
    //
    // 128 (FD_STEM_SCRATCH_ALIGN) here means .scratch_align was wired to the
    // STEM-generated tkpolicy_scratch_align() from fd_stem.c, which describes
    // fd_stem's own stack scratch: a different block from the one
    // .scratch_footprint reserves.  See "Tile Scratch Layout" in
    // doc/execution/contribution/tickoni.md.
    try std.testing.expectEqual(@as(usize, 8), tkpoly_tile_scratch_align());
}

test "tkpoly scratch align — footprint is a whole number of alignment units" {
    // The topology places the object on scratch_align and reserves
    // scratch_footprint bytes; a footprint that is not a multiple of the
    // alignment leaves the next object's offset depending on the slack.
    try std.testing.expectEqual(
        @as(usize, 0),
        tkpoly_tile_scratch_footprint() % tkpoly_tile_scratch_align(),
    );
}

test "tkpoly tile identity — init callbacks are non-null" {
    try std.testing.expect(tk_get_policy_run_privileged_init() != null);
    try std.testing.expect(tk_get_policy_run_unprivileged_init() != null);
}

test "tkpoly scratch footprint — returns deterministic value > 1" {
    const footprint = tkpoly_tile_scratch_footprint();
    try std.testing.expect(footprint > 1);
    try std.testing.expectEqual(footprint, tkpoly_tile_scratch_footprint());
}

test "tkpoly scratch footprint — topob wrapper matches direct call" {
    const direct = tkpoly_tile_scratch_footprint();
    const via_topob = tk_topob_tickoni_tile_scratch_footprint("tkpoly");
    try std.testing.expectEqual(direct, via_topob);
}

test "tkpoly scratch footprint — fixed across behavior configuration" {
    const footprint = policyScratchFootprint();
    const alignment = policyScratchAlign();

    for ([_]u64{ 0, 1, 32 }) |event_count| {
        setEventCount(event_count);
        for ([_]i64{ std.math.minInt(i64), -1, 0, 1, std.math.maxInt(i64) }) |limit| {
            setPolicyLimitCents(limit);
            try std.testing.expectEqual(footprint, policyScratchFootprint());
            try std.testing.expectEqual(@as(usize, 0), policyScratchFootprint() % alignment);
        }
    }
}

// ---------------------------------------------------------------------------
// P2.4 — Pure policy helper unit tests.
//
// Branch precedence: malformed > duplicate > high-amount.
// High-amount check: signed comparison amount_cents > limit.
// ---------------------------------------------------------------------------

// Import the C enum constants (translate-c from audit_schema.h).
const audit_mod = @import("audit_mod");

const POLICY_ALLOW = audit_mod.POLICY_ALLOW;
const POLICY_DENY = audit_mod.POLICY_DENY;
const POLICY_MALFORMED_DROP = audit_mod.POLICY_MALFORMED_DROP;
const POLICY_DUPLICATE_DROP = audit_mod.POLICY_DUPLICATE_DROP;

test "tkpoly policy helper — malformed-plus-duplicate/high-amount => MALFORMED_DROP" {
    const got = policyOutcome(POLICY_MALFORMED_DROP, true, std.math.maxInt(i64), 1);
    try std.testing.expectEqual(POLICY_MALFORMED_DROP, got);
}

test "tkpoly policy helper — duplicate-plus-high-amount => DUPLICATE_DROP" {
    const got = policyOutcome(POLICY_ALLOW, true, std.math.maxInt(i64), 1);
    try std.testing.expectEqual(POLICY_DUPLICATE_DROP, got);
}

test "tkpoly policy helper — limit-minus-one => ALLOW" {
    const got = policyOutcome(POLICY_ALLOW, false, 49, 50);
    try std.testing.expectEqual(POLICY_ALLOW, got);
}

test "tkpoly policy helper — equality => ALLOW" {
    const got = policyOutcome(POLICY_ALLOW, false, 50, 50);
    try std.testing.expectEqual(POLICY_ALLOW, got);
}

test "tkpoly policy helper — limit-plus-one => DENY" {
    const got = policyOutcome(POLICY_ALLOW, false, 51, 50);
    try std.testing.expectEqual(POLICY_DENY, got);
}

test "tkpoly policy helper — negative amount => signed comparison" {
    // -100 > 50 is false (negative < positive) → ALLOW
    const got = policyOutcome(POLICY_ALLOW, false, -100, 50);
    try std.testing.expectEqual(POLICY_ALLOW, got);
}

test "tkpoly policy helper — negative amount within limit => ALLOW" {
    // -30 > 50 is false → ALLOW
    const got = policyOutcome(POLICY_ALLOW, false, -30, 50);
    try std.testing.expectEqual(POLICY_ALLOW, got);
}

test "tkpoly policy helper — negative limit => deny positive amounts" {
    const got = policyOutcome(POLICY_ALLOW, false, 1, -1);
    try std.testing.expectEqual(POLICY_DENY, got);
}

test "tkpoly policy helper — negative limit + zero amount => DENY" {
    // 0 > -1 is true → DENY (signed comparison)
    const got = policyOutcome(POLICY_ALLOW, false, 0, -1);
    try std.testing.expectEqual(POLICY_DENY, got);
}

test "tkpoly policy helper — signed extrema i64::MIN amount (overflow-safe)" {
    // LLONG_MIN = -9223372036854775808. -amount overflows back to LLONG_MIN in
    // two's complement. LLONG_MIN > 50 is false (it's negative), so ALLOW.
    // This tests that the C code handles the edge case without UB in fixture
    // construction.
    const got = policyOutcome(POLICY_ALLOW, false, std.math.minInt(i64), 50);
    try std.testing.expectEqual(POLICY_ALLOW, got);
}

test "tkpoly policy helper — signed extrema i64::MAX amount => DENY" {
    const got = policyOutcome(POLICY_ALLOW, false, std.math.maxInt(i64), 50);
    try std.testing.expectEqual(POLICY_DENY, got);
}

test "tkpoly policy helper — zero amount with positive limit => ALLOW" {
    const got = policyOutcome(POLICY_ALLOW, false, 0, 100);
    try std.testing.expectEqual(POLICY_ALLOW, got);
}

test "tkpoly policy helper — duplicate overrides deny => DUPLICATE_DROP" {
    const got = policyOutcome(POLICY_DENY, true, 50, 100);
    try std.testing.expectEqual(POLICY_DUPLICATE_DROP, got);
}

// ---------------------------------------------------------------------------
// P2.5 — Zig FFI parity: pure Zig policy mirrors the C helper.
//
// policyOutcomeZig() is the retained Zig implementation that must always
// produce the same result as the C helper.  Parity tests cover the same
// cases the C helper was tested above plus a bulk sweep over small
// amounts/limits to catch divergences.
// ---------------------------------------------------------------------------

/// Pure Zig implementation of the tkpoly outcome chain.
/// Branch precedence: malformed > duplicate > high-amount.
/// High-amount check: signed comparison amount_cents > limit,
/// matching the C helper exactly.
pub fn policyOutcomeZig(
    incoming_decision: u8,
    is_duplicate: bool,
    amount_cents: i64,
    policy_limit_cents: i64,
) u8 {
    // Branch precedence: malformed > duplicate > high-amount.
    if (incoming_decision == POLICY_MALFORMED_DROP) return POLICY_MALFORMED_DROP;
    if (is_duplicate) return POLICY_DUPLICATE_DROP;

    if (amount_cents > policy_limit_cents) return POLICY_DENY;
    return POLICY_ALLOW;
}

test "tkpoly FFI parity — malformed-plus-duplicate/high-amount" {
    const c_got = policyOutcome(POLICY_MALFORMED_DROP, true, std.math.maxInt(i64), 1);
    const z_got = policyOutcomeZig(POLICY_MALFORMED_DROP, true, std.math.maxInt(i64), 1);
    try std.testing.expectEqual(c_got, z_got);
}

test "tkpoly FFI parity — duplicate-plus-high-amount" {
    const c_got = policyOutcome(POLICY_ALLOW, true, std.math.maxInt(i64), 1);
    const z_got = policyOutcomeZig(POLICY_ALLOW, true, std.math.maxInt(i64), 1);
    try std.testing.expectEqual(c_got, z_got);
}

test "tkpoly FFI parity — limit-minus-one" {
    const c_got = policyOutcome(POLICY_ALLOW, false, 49, 50);
    const z_got = policyOutcomeZig(POLICY_ALLOW, false, 49, 50);
    try std.testing.expectEqual(c_got, z_got);
}

test "tkpoly FFI parity — equality" {
    const c_got = policyOutcome(POLICY_ALLOW, false, 50, 50);
    const z_got = policyOutcomeZig(POLICY_ALLOW, false, 50, 50);
    try std.testing.expectEqual(c_got, z_got);
}

test "tkpoly FFI parity — limit-plus-one" {
    const c_got = policyOutcome(POLICY_ALLOW, false, 51, 50);
    const z_got = policyOutcomeZig(POLICY_ALLOW, false, 51, 50);
    try std.testing.expectEqual(c_got, z_got);
}

test "tkpoly FFI parity — negative amount exceeds limit" {
    const c_got = policyOutcome(POLICY_ALLOW, false, -100, 50);
    const z_got = policyOutcomeZig(POLICY_ALLOW, false, -100, 50);
    try std.testing.expectEqual(c_got, z_got);
}

test "tkpoly FFI parity — negative amount within limit" {
    const c_got = policyOutcome(POLICY_ALLOW, false, -30, 50);
    const z_got = policyOutcomeZig(POLICY_ALLOW, false, -30, 50);
    try std.testing.expectEqual(c_got, z_got);
}

test "tkpoly FFI parity — negative limit" {
    const c_got = policyOutcome(POLICY_ALLOW, false, 1, -1);
    const z_got = policyOutcomeZig(POLICY_ALLOW, false, 1, -1);
    try std.testing.expectEqual(c_got, z_got);
}

test "tkpoly FFI parity — negative limit + zero amount" {
    const c_got = policyOutcome(POLICY_ALLOW, false, 0, -1);
    const z_got = policyOutcomeZig(POLICY_ALLOW, false, 0, -1);
    try std.testing.expectEqual(c_got, z_got);
}

test "tkpoly FFI parity — signed extrema i64::MIN" {
    const c_got = policyOutcome(POLICY_ALLOW, false, std.math.minInt(i64), 50);
    const z_got = policyOutcomeZig(POLICY_ALLOW, false, std.math.minInt(i64), 50);
    try std.testing.expectEqual(c_got, z_got);
}

test "tkpoly FFI parity — signed extrema i64::MAX" {
    const c_got = policyOutcome(POLICY_ALLOW, false, std.math.maxInt(i64), 50);
    const z_got = policyOutcomeZig(POLICY_ALLOW, false, std.math.maxInt(i64), 50);
    try std.testing.expectEqual(c_got, z_got);
}

test "tkpoly FFI parity — duplicate overrides deny" {
    const c_got = policyOutcome(POLICY_DENY, true, 50, 100);
    const z_got = policyOutcomeZig(POLICY_DENY, true, 50, 100);
    try std.testing.expectEqual(c_got, z_got);
}

test "tkpoly FFI parity — bulk sweep (amount, limit)" {
    // Exhaustive sweep over small amounts and limits to catch boundary
    // divergences between C and Zig implementations.
    for ([_]i64{ -10, -5, -2, -1, 0, 1, 2, 5, 10 }) |amt| {
        for ([_]i64{ -2, -1, 0, 1, 2, 5, 10, 50 }) |lim| {
            const c_got = policyOutcome(POLICY_ALLOW, false, amt, lim);
            const z_got = policyOutcomeZig(POLICY_ALLOW, false, amt, lim);
            try std.testing.expectEqual(c_got, z_got);
        }
    }
}
