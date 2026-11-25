/// Thin Zig wrapper over tk_diag_stem.c — the fd_stem diagnostics tile registered
/// as tkdiag, modelled on Firedancer's diag tile. It receives one diagnostic
/// fragment per pipeline tile over dedicated unreliable links
/// (plans/v2.10-s14-tkdiag-fan-in.md), keeps the latest fragment per input and
/// aggregates them; it watches every tile's process and writes each tile's
/// OS-level metrics; it reads tkrepl's replay result. It publishes nothing and
/// opens no socket: its outputs are its CNC app slots 0 to 4 (read by the
/// supervisor through tile_registry.zig) and the `tkdiag` metrics kind (served
/// by the metric tile). This module is the identity and scratch contract plus
/// the unit tests of the fragment layout, the aggregation rules and the liveness
/// rule, which live in tk_diag_fragment.h and are exercised through the same
/// translate-c step the runtime uses (`audit_mod`); no Zig struct mirrors a C
/// struct.
const std = @import("std");
const stem_run = @import("stem_run.zig");
const audit_mod = @import("audit_mod");

pub const TopoRunTile = opaque {};

const run_desc = stem_run.RunDescriptor("diag", TopoRunTile);

extern fn tkdiag_tile_scratch_footprint() usize;
extern fn tkdiag_tile_scratch_align() usize;
extern fn tk_topob_tickoni_tile_scratch_requirements(tile_name: [*:0]const u8, alignment_out: *usize, footprint_out: *usize) void;
extern fn tk_topob_tickoni_tile_scratch_footprint(tile_name: [*:0]const u8) usize;

pub fn scratchFootprint() usize {
    return tkdiag_tile_scratch_footprint();
}

pub fn scratchAlign() usize {
    return tkdiag_tile_scratch_align();
}

test "tkdiag identity — name is TILE_ID_TKDIAG" {
    try std.testing.expectEqualStrings("tkdiag", std.mem.sliceTo(run_desc.name(), 0));
    try std.testing.expect(run_desc.tile() != null);
}

test "tkdiag identity — run callback is non-null" {
    try std.testing.expect(run_desc.run() != null);
}

test "tkdiag identity — scratch callbacks are non-null" {
    try std.testing.expect(run_desc.scratchAlign() != null);
    try std.testing.expect(run_desc.scratchFootprint() != null);
}

test "tkdiag identity — init callbacks are non-null" {
    try std.testing.expect(run_desc.privilegedInit() != null);
    try std.testing.expect(run_desc.unprivilegedInit() != null);
}

test "tkdiag scratch — deterministic, aligned, and larger than one byte" {
    const footprint = scratchFootprint();
    const alignment = scratchAlign();
    try std.testing.expect(footprint > 1);
    try std.testing.expect(std.math.isPowerOfTwo(alignment));
    try std.testing.expectEqual(@as(usize, 0), footprint % alignment);
    try std.testing.expectEqual(footprint, scratchFootprint());
    try std.testing.expectEqual(alignment, scratchAlign());
}

test "tkdiag scratch — topob wrapper matches the direct call" {
    var alignment: usize = 0;
    var footprint: usize = 0;
    tk_topob_tickoni_tile_scratch_requirements("tkdiag", &alignment, &footprint);
    try std.testing.expectEqual(scratchAlign(), alignment);
    try std.testing.expectEqual(scratchFootprint(), footprint);
    try std.testing.expectEqual(scratchFootprint(), tk_topob_tickoni_tile_scratch_footprint("tkdiag"));
}

// ---------------------------------------------------------------------------
// Fragment layout (tk_diag_fragment.h)
// ---------------------------------------------------------------------------

const Frag = audit_mod.diag_fragment_t;
const Agg = audit_mod.tkdiag_agg_t;

test "diag fragment — exactly 128 bytes with the documented field offsets" {
    try std.testing.expectEqual(@as(usize, 128), @sizeOf(Frag));
    try std.testing.expectEqual(@as(usize, audit_mod.TK_DIAG_LINK_MTU), @sizeOf(Frag));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Frag, "tile_id"));
    try std.testing.expectEqual(@as(usize, 4), @offsetOf(Frag, "tile_type"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(Frag, "seq"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(Frag, "timestamp_ns"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(Frag, "events_processed"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(Frag, "errors"));
    try std.testing.expectEqual(@as(usize, 40), @offsetOf(Frag, "backpressure_waits"));
    try std.testing.expectEqual(@as(usize, 48), @offsetOf(Frag, "max_queue_depth"));
    try std.testing.expectEqual(@as(usize, 56), @offsetOf(Frag, "sandbox_failures"));
    try std.testing.expectEqual(@as(usize, 64), @offsetOf(Frag, "audit_records"));
    try std.testing.expectEqual(@as(usize, 72), @offsetOf(Frag, "crashed"));
    try std.testing.expectEqual(@as(usize, 76), @offsetOf(Frag, "replay_checked"));
    try std.testing.expectEqual(@as(usize, 80), @offsetOf(Frag, "replay_match"));
    try std.testing.expectEqual(@as(usize, 84), @offsetOf(Frag, "reserved"));
}

test "diag fragment — type codes: the spine in pipeline order, then the runtime tiles, append-only" {
    try std.testing.expectEqual(@as(u32, 1), audit_mod.TK_DIAG_TYPE_INGEST);
    try std.testing.expectEqual(@as(u32, 2), audit_mod.TK_DIAG_TYPE_NORMALIZE);
    try std.testing.expectEqual(@as(u32, 3), audit_mod.TK_DIAG_TYPE_DEDUPE);
    try std.testing.expectEqual(@as(u32, 4), audit_mod.TK_DIAG_TYPE_POLICY);
    try std.testing.expectEqual(@as(u32, 5), audit_mod.TK_DIAG_TYPE_AUDIT);
    try std.testing.expectEqual(@as(u32, 6), audit_mod.TK_DIAG_TYPE_GATE);
    try std.testing.expectEqual(@as(u32, 7), audit_mod.TK_DIAG_TYPE_CASE);
    try std.testing.expectEqual(@as(u32, 8), audit_mod.TK_DIAG_TYPE_DISPATCH);
    try std.testing.expectEqual(@as(u32, 9), audit_mod.TK_DIAG_TYPE_AGENT);
    try std.testing.expectEqual(@as(u32, 10), audit_mod.TK_DIAG_TYPE_MODEL);
    try std.testing.expectEqual(@as(u32, audit_mod.TK_DIAG_TYPE_MODEL), audit_mod.TK_DIAG_TYPE_LAST);
    // tkdiag can bind one input per producer type.
    try std.testing.expect(audit_mod.TKDIAG_MAX_INPUTS >= audit_mod.TK_DIAG_TYPE_LAST);
}

test "diag link — depth is a power of two" {
    try std.testing.expect(std.math.isPowerOfTwo(@as(usize, audit_mod.TK_DIAG_LINK_DEPTH)));
}

test "diag fragment — tile names map to their type code, anything else to zero" {
    const f = audit_mod.tk_diag_type_for_tile_name;
    try std.testing.expectEqual(@as(u32, audit_mod.TK_DIAG_TYPE_INGEST), f("tkings"));
    try std.testing.expectEqual(@as(u32, audit_mod.TK_DIAG_TYPE_NORMALIZE), f("tknorm"));
    try std.testing.expectEqual(@as(u32, audit_mod.TK_DIAG_TYPE_DEDUPE), f("tkdedu"));
    try std.testing.expectEqual(@as(u32, audit_mod.TK_DIAG_TYPE_POLICY), f("tkpoly"));
    try std.testing.expectEqual(@as(u32, audit_mod.TK_DIAG_TYPE_AUDIT), f("tkaudt"));
    try std.testing.expectEqual(@as(u32, audit_mod.TK_DIAG_TYPE_GATE), f("tkgate"));
    try std.testing.expectEqual(@as(u32, audit_mod.TK_DIAG_TYPE_CASE), f("tkcase"));
    try std.testing.expectEqual(@as(u32, audit_mod.TK_DIAG_TYPE_DISPATCH), f("tkdisp"));
    try std.testing.expectEqual(@as(u32, audit_mod.TK_DIAG_TYPE_AGENT), f("tkagnt"));
    try std.testing.expectEqual(@as(u32, audit_mod.TK_DIAG_TYPE_MODEL), f("tkmodl"));
    try std.testing.expectEqual(@as(u32, 0), f("tktool"));
    try std.testing.expectEqual(@as(u32, 0), f("tkadpt"));
    try std.testing.expectEqual(@as(u32, 0), f("tkrepl"));
    try std.testing.expectEqual(@as(u32, 0), f("metric"));
    try std.testing.expectEqual(@as(u32, 0), f("tkdiag"));
    try std.testing.expectEqual(@as(u32, 0), f(""));
}

// ---------------------------------------------------------------------------
// Aggregation (tkdiag_agg_*)
// ---------------------------------------------------------------------------

/// Five inputs bound as the payment process topology binds them: tkings,
/// tknorm, tkdedu, tkpoly, tkaudt, with Firedancer tile ids 0..4.
const bound_ids = [_]u32{ 0, 1, 2, 3, 4 };
const bound_types = [_]u32{
    audit_mod.TK_DIAG_TYPE_INGEST,
    audit_mod.TK_DIAG_TYPE_NORMALIZE,
    audit_mod.TK_DIAG_TYPE_DEDUPE,
    audit_mod.TK_DIAG_TYPE_POLICY,
    audit_mod.TK_DIAG_TYPE_AUDIT,
};

fn newAgg() !Agg {
    var agg: Agg = undefined;
    try std.testing.expectEqual(@as(c_int, 0), audit_mod.tkdiag_agg_init(&agg, bound_ids.len, &bound_ids, &bound_types));
    return agg;
}

/// A well-formed fragment from input `in_idx` (its bound tile) with `seq`.
fn fragFor(in_idx: usize, seq: u64) Frag {
    var f = std.mem.zeroes(Frag);
    f.tile_id = bound_ids[in_idx];
    f.tile_type = bound_types[in_idx];
    f.seq = seq;
    f.timestamp_ns = 1_000 + seq;
    f.events_processed = seq;
    return f;
}

test "tkdiag agg — starts empty" {
    const agg = try newAgg();
    try std.testing.expectEqual(@as(u64, 0), agg.accepted);
    try std.testing.expectEqual(@as(u64, 0), agg.rejected);
    try std.testing.expectEqual(@as(u64, 0), agg.tiles_reporting);
    try std.testing.expectEqual(@as(u64, 0), agg.crashed_tiles);
    try std.testing.expectEqual(@as(u64, 0), agg.sandbox_failures);
    try std.testing.expectEqual(@as(u64, 0), agg.total_errors);
    try std.testing.expectEqual(@as(u64, 0), agg.total_audit_records);
}

test "tkdiag agg — init rejects an input count outside 1..max and a missing binding" {
    var agg: Agg = undefined;
    try std.testing.expect(audit_mod.tkdiag_agg_init(&agg, 0, &bound_ids, &bound_types) != 0);
    try std.testing.expect(audit_mod.tkdiag_agg_init(&agg, audit_mod.TKDIAG_MAX_INPUTS + 1, &bound_ids, &bound_types) != 0);
    try std.testing.expect(audit_mod.tkdiag_agg_init(&agg, 5, null, &bound_types) != 0);
    try std.testing.expect(audit_mod.tkdiag_agg_init(&agg, 5, &bound_ids, null) != 0);
    // A binding to a tile type that is not a diagnostic producer is refused.
    const bad_types = [_]u32{ 1, 2, 3, 4, 0 };
    try std.testing.expect(audit_mod.tkdiag_agg_init(&agg, 5, &bound_ids, &bad_types) != 0);
}

test "tkdiag agg — binds one input per producer type, spine and runtime, and accepts a runtime tile's fragment" {
    var agg: Agg = undefined;
    var ids: [audit_mod.TK_DIAG_TYPE_LAST]u32 = undefined;
    var types: [audit_mod.TK_DIAG_TYPE_LAST]u32 = undefined;
    for (&ids, &types, 0..) |*id, *ty, k| {
        id.* = @intCast(k);
        ty.* = @intCast(k + 1);
    }
    try std.testing.expectEqual(@as(c_int, 0), audit_mod.tkdiag_agg_init(&agg, ids.len, &ids, &types));
    var f = std.mem.zeroes(Frag);
    f.tile_id = ids[ids.len - 1];
    f.tile_type = audit_mod.TK_DIAG_TYPE_MODEL;
    f.seq = 1;
    try std.testing.expectEqual(@as(c_int, 1), audit_mod.tkdiag_agg_accept(&agg, ids.len - 1, &f));
    try std.testing.expectEqual(@as(u64, 1), agg.tiles_reporting);
    // A code past the last producer type is not a producer's.
    types[0] = audit_mod.TK_DIAG_TYPE_LAST + 1;
    try std.testing.expect(audit_mod.tkdiag_agg_init(&agg, ids.len, &ids, &types) != 0);
}

test "tkdiag agg — init rejects two inputs bound to the same producer type" {
    var agg: Agg = undefined;
    const ids = [_]u32{ 0, 1, 2 };
    const dup_types = [_]u32{ audit_mod.TK_DIAG_TYPE_INGEST, audit_mod.TK_DIAG_TYPE_NORMALIZE, audit_mod.TK_DIAG_TYPE_NORMALIZE };
    try std.testing.expect(audit_mod.tkdiag_agg_init(&agg, 3, &ids, &dup_types) != 0);
    // A failed init leaves nothing bound, so nothing can be accepted afterwards.
    try std.testing.expectEqual(@as(u64, 0), agg.in_cnt);
    const f = fragFor(0, 1);
    try std.testing.expectEqual(@as(c_int, 0), audit_mod.tkdiag_agg_accept(&agg, 0, &f));
}

test "tkdiag agg — accepts a valid fragment and counts the tile as reporting" {
    var agg = try newAgg();
    const f = fragFor(1, 1);
    try std.testing.expectEqual(@as(c_int, 1), audit_mod.tkdiag_agg_accept(&agg, 1, &f));
    try std.testing.expectEqual(@as(u64, 1), agg.accepted);
    try std.testing.expectEqual(@as(u64, 0), agg.rejected);
    try std.testing.expectEqual(@as(u64, 1), agg.tiles_reporting);
    try std.testing.expectEqual(@as(u64, 1), agg.latest[1].seq);
}

test "tkdiag agg — a fragment from every input makes every tile report" {
    var agg = try newAgg();
    for (0..5) |i| {
        const f = fragFor(i, 1);
        try std.testing.expectEqual(@as(c_int, 1), audit_mod.tkdiag_agg_accept(&agg, i, &f));
    }
    try std.testing.expectEqual(@as(u64, 5), agg.tiles_reporting);
    try std.testing.expectEqual(@as(u64, 5), agg.accepted);
    // A second fragment from the same tile does not make it report twice.
    const again = fragFor(2, 2);
    try std.testing.expectEqual(@as(c_int, 1), audit_mod.tkdiag_agg_accept(&agg, 2, &again));
    try std.testing.expectEqual(@as(u64, 5), agg.tiles_reporting);
    try std.testing.expectEqual(@as(u64, 6), agg.accepted);
}

test "tkdiag agg — rejects a stale or duplicate sequence number and keeps the newer state" {
    var agg = try newAgg();
    var newer = fragFor(3, 5);
    newer.errors = 7;
    try std.testing.expectEqual(@as(c_int, 1), audit_mod.tkdiag_agg_accept(&agg, 3, &newer));

    var stale = fragFor(3, 4);
    stale.errors = 99;
    try std.testing.expectEqual(@as(c_int, 0), audit_mod.tkdiag_agg_accept(&agg, 3, &stale));
    var duplicate = fragFor(3, 5);
    duplicate.errors = 99;
    try std.testing.expectEqual(@as(c_int, 0), audit_mod.tkdiag_agg_accept(&agg, 3, &duplicate));

    try std.testing.expectEqual(@as(u64, 1), agg.accepted);
    try std.testing.expectEqual(@as(u64, 2), agg.rejected);
    try std.testing.expectEqual(@as(u64, 7), agg.latest[3].errors);
    try std.testing.expectEqual(@as(u64, 7), agg.total_errors);
}

test "tkdiag agg — sequence numbers are tracked per input, not globally" {
    var agg = try newAgg();
    const a = fragFor(1, 10);
    const b = fragFor(2, 1);
    try std.testing.expectEqual(@as(c_int, 1), audit_mod.tkdiag_agg_accept(&agg, 1, &a));
    try std.testing.expectEqual(@as(c_int, 1), audit_mod.tkdiag_agg_accept(&agg, 2, &b));
}

test "tkdiag agg — rejects a fragment whose identity disagrees with its input's producer" {
    var agg = try newAgg();
    // A fragment on input 1 (tknorm) claiming to be tkdedu, then claiming tkdedu's type only.
    var wrong_id = fragFor(1, 1);
    wrong_id.tile_id = bound_ids[2];
    var wrong_type = fragFor(1, 1);
    wrong_type.tile_type = bound_types[2];
    try std.testing.expectEqual(@as(c_int, 0), audit_mod.tkdiag_agg_accept(&agg, 1, &wrong_id));
    try std.testing.expectEqual(@as(c_int, 0), audit_mod.tkdiag_agg_accept(&agg, 1, &wrong_type));
    try std.testing.expectEqual(@as(u64, 2), agg.rejected);
    try std.testing.expectEqual(@as(u64, 0), agg.tiles_reporting);
}

test "tkdiag agg — rejects malformed fragments: zero seq, unknown type, bad flags, dirty reserved bytes" {
    var agg = try newAgg();
    var zero_seq = fragFor(0, 1);
    zero_seq.seq = 0;
    var bad_crashed = fragFor(0, 1);
    bad_crashed.crashed = 2;
    var bad_checked = fragFor(0, 1);
    bad_checked.replay_checked = -1;
    var bad_match = fragFor(0, 1);
    bad_match.replay_match = 7;
    var dirty = fragFor(0, 1);
    dirty.reserved[43] = 1;
    const all = [_]Frag{ zero_seq, bad_crashed, bad_checked, bad_match, dirty };
    for (all) |f| try std.testing.expectEqual(@as(c_int, 0), audit_mod.tkdiag_agg_accept(&agg, 0, &f));
    try std.testing.expectEqual(@as(u64, all.len), agg.rejected);
    try std.testing.expectEqual(@as(u64, 0), agg.accepted);
    try std.testing.expectEqual(@as(u64, 0), agg.tiles_reporting);
}

test "tkdiag agg — rejects an input index beyond the bound inputs" {
    var agg = try newAgg();
    const f = fragFor(0, 1);
    try std.testing.expectEqual(@as(c_int, 0), audit_mod.tkdiag_agg_accept(&agg, 5, &f));
    try std.testing.expectEqual(@as(c_int, 0), audit_mod.tkdiag_agg_accept(&agg, 1_000_000, &f));
    try std.testing.expectEqual(@as(u64, 2), agg.rejected);
}

test "tkdiag agg — totals derive from the latest fragment per tile and never double-count" {
    var agg = try newAgg();
    // tknorm reports 3 errors, then (cumulatively) 5. The total is 5, not 8.
    var n1 = fragFor(1, 1);
    n1.errors = 3;
    var n2 = fragFor(1, 2);
    n2.errors = 5;
    var d1 = fragFor(2, 1);
    d1.errors = 2;
    try std.testing.expectEqual(@as(c_int, 1), audit_mod.tkdiag_agg_accept(&agg, 1, &n1));
    try std.testing.expectEqual(@as(c_int, 1), audit_mod.tkdiag_agg_accept(&agg, 2, &d1));
    try std.testing.expectEqual(@as(u64, 5), agg.total_errors);
    try std.testing.expectEqual(@as(c_int, 1), audit_mod.tkdiag_agg_accept(&agg, 1, &n2));
    try std.testing.expectEqual(@as(u64, 7), agg.total_errors);
}

test "tkdiag agg — total audit records is the largest any tile reports" {
    var agg = try newAgg();
    var a = fragFor(4, 1);
    a.audit_records = 40;
    var b = fragFor(3, 1);
    b.audit_records = 25;
    try std.testing.expectEqual(@as(c_int, 1), audit_mod.tkdiag_agg_accept(&agg, 4, &a));
    try std.testing.expectEqual(@as(c_int, 1), audit_mod.tkdiag_agg_accept(&agg, 3, &b));
    try std.testing.expectEqual(@as(u64, 40), agg.total_audit_records);
}

test "tkdiag agg — a tile that reports a fault is counted, and clears when it reports healthy again" {
    var agg = try newAgg();
    var faulty = fragFor(1, 1);
    faulty.crashed = 1;
    faulty.sandbox_failures = 2;
    try std.testing.expectEqual(@as(c_int, 1), audit_mod.tkdiag_agg_accept(&agg, 1, &faulty));
    try std.testing.expectEqual(@as(u64, 1), agg.crashed_tiles);
    try std.testing.expectEqual(@as(u64, 2), agg.sandbox_failures);

    const healthy = fragFor(1, 2);
    try std.testing.expectEqual(@as(c_int, 1), audit_mod.tkdiag_agg_accept(&agg, 1, &healthy));
    try std.testing.expectEqual(@as(u64, 0), agg.crashed_tiles);
    try std.testing.expectEqual(@as(u64, 0), agg.sandbox_failures);
}

test "tkdiag agg — a rejected fragment never changes the aggregate" {
    var agg = try newAgg();
    var good = fragFor(1, 1);
    good.errors = 4;
    try std.testing.expectEqual(@as(c_int, 1), audit_mod.tkdiag_agg_accept(&agg, 1, &good));
    var bad = fragFor(1, 2);
    bad.errors = 1000;
    bad.reserved[0] = 9;
    try std.testing.expectEqual(@as(c_int, 0), audit_mod.tkdiag_agg_accept(&agg, 1, &bad));
    try std.testing.expectEqual(@as(u64, 4), agg.total_errors);
    try std.testing.expectEqual(@as(u64, 1), agg.latest[1].seq);
}

// ---------------------------------------------------------------------------
// Tile liveness observation: Firedancer's diag-tile rule (a tile whose process
// is gone while its TILE_STATUS gauge is not "shutdown" died abnormally)
// ---------------------------------------------------------------------------

const Obs = audit_mod.tkdiag_tile_obs_t;

fn newObs() Obs {
    return std.mem.zeroes(Obs);
}

test "tkdiag obs — a tile whose process is alive is never dead, whatever its status" {
    var o = newObs();
    for ([_]u64{ audit_mod.TKDIAG_STATUS_BOOT, audit_mod.TKDIAG_STATUS_RUN, audit_mod.TKDIAG_STATUS_SHUTDOWN }) |status| {
        try std.testing.expectEqual(@as(c_int, 0), audit_mod.tkdiag_obs_update(&o, 1, status));
    }
    try std.testing.expectEqual(@as(u8, 0), o.dead);
}

test "tkdiag obs — a gone process that finished a clean shutdown is not a crash" {
    var o = newObs();
    try std.testing.expectEqual(@as(c_int, 0), audit_mod.tkdiag_obs_update(&o, 0, audit_mod.TKDIAG_STATUS_SHUTDOWN));
    try std.testing.expectEqual(@as(u8, 0), o.dead);
    try std.testing.expectEqual(@as(u8, 0), o.never_ran);
}

test "tkdiag obs — a gone process that was running is a crash, reported exactly once" {
    var o = newObs();
    try std.testing.expectEqual(@as(c_int, 1), audit_mod.tkdiag_obs_update(&o, 0, audit_mod.TKDIAG_STATUS_RUN));
    try std.testing.expectEqual(@as(u8, 1), o.dead);
    try std.testing.expectEqual(@as(u8, 0), o.never_ran);
    try std.testing.expectEqual(@as(c_int, 0), audit_mod.tkdiag_obs_update(&o, 0, audit_mod.TKDIAG_STATUS_RUN));
}

test "tkdiag obs — a gone process that never left boot died booting or entering its sandbox" {
    var o = newObs();
    try std.testing.expectEqual(@as(c_int, 1), audit_mod.tkdiag_obs_update(&o, 0, audit_mod.TKDIAG_STATUS_BOOT));
    try std.testing.expectEqual(@as(u8, 1), o.dead);
    try std.testing.expectEqual(@as(u8, 1), o.never_ran);
}

test "tkdiag obs — death is sticky: a later observation never clears it" {
    var o = newObs();
    _ = audit_mod.tkdiag_obs_update(&o, 0, audit_mod.TKDIAG_STATUS_RUN);
    try std.testing.expectEqual(@as(c_int, 0), audit_mod.tkdiag_obs_update(&o, 1, audit_mod.TKDIAG_STATUS_RUN));
    try std.testing.expectEqual(@as(c_int, 0), audit_mod.tkdiag_obs_update(&o, 0, audit_mod.TKDIAG_STATUS_SHUTDOWN));
    try std.testing.expectEqual(@as(u8, 1), o.dead);
}

test "tkdiag obs — an unknown status value is not a clean shutdown" {
    var o = newObs();
    try std.testing.expectEqual(@as(c_int, 1), audit_mod.tkdiag_obs_update(&o, 0, 7));
    try std.testing.expectEqual(@as(u8, 1), o.dead);
}

test "tkdiag crashed total — dead tiles and fragment-reported faults, each tile once" {
    var agg = try newAgg();
    var obs = std.mem.zeroes([8]Obs);

    try std.testing.expectEqual(@as(u64, 0), audit_mod.tkdiag_crashed_total(&agg, &obs, obs.len));

    // tile 2 (tkdedu) is observed dead.
    obs[2].dead = 1;
    try std.testing.expectEqual(@as(u64, 1), audit_mod.tkdiag_crashed_total(&agg, &obs, obs.len));

    // tkdedu's own final fragment also reports the fault: still one tile.
    var own = fragFor(2, 1);
    own.crashed = 1;
    try std.testing.expectEqual(@as(c_int, 1), audit_mod.tkdiag_agg_accept(&agg, 2, &own));
    try std.testing.expectEqual(@as(u64, 1), audit_mod.tkdiag_crashed_total(&agg, &obs, obs.len));

    // another tile reports a fault but is not observed dead: two tiles.
    var other = fragFor(3, 1);
    other.crashed = 1;
    try std.testing.expectEqual(@as(c_int, 1), audit_mod.tkdiag_agg_accept(&agg, 3, &other));
    try std.testing.expectEqual(@as(u64, 2), audit_mod.tkdiag_crashed_total(&agg, &obs, obs.len));
}

test "tkdiag crashed total — a fragment fault is cleared by a later healthy fragment, a death is not" {
    var agg = try newAgg();
    var obs = std.mem.zeroes([8]Obs);
    var bad = fragFor(1, 1);
    bad.crashed = 1;
    _ = audit_mod.tkdiag_agg_accept(&agg, 1, &bad);
    try std.testing.expectEqual(@as(u64, 1), audit_mod.tkdiag_crashed_total(&agg, &obs, obs.len));
    const good = fragFor(1, 2);
    _ = audit_mod.tkdiag_agg_accept(&agg, 1, &good);
    try std.testing.expectEqual(@as(u64, 0), audit_mod.tkdiag_crashed_total(&agg, &obs, obs.len));
    obs[1].dead = 1;
    try std.testing.expectEqual(@as(u64, 1), audit_mod.tkdiag_crashed_total(&agg, &obs, obs.len));
    _ = audit_mod.tkdiag_agg_accept(&agg, 1, &fragFor(1, 3));
    try std.testing.expectEqual(@as(u64, 1), audit_mod.tkdiag_crashed_total(&agg, &obs, obs.len));
}

test "tkdiag crashed total — only tiles within the observed range count as dead" {
    const agg = try newAgg();
    var obs = std.mem.zeroes([8]Obs);
    obs[6].dead = 1;
    obs[7].dead = 1;
    // Only the first 6 entries are tiles of this topology.
    try std.testing.expectEqual(@as(u64, 0), audit_mod.tkdiag_crashed_total(&agg, &obs, 6));
    try std.testing.expectEqual(@as(u64, 2), audit_mod.tkdiag_crashed_total(&agg, &obs, 8));
}

test "tkdiag boot failures — counts tiles that died before running" {
    var agg = try newAgg();
    var obs = std.mem.zeroes([4]Obs);
    try std.testing.expectEqual(@as(u64, 0), audit_mod.tkdiag_boot_failures(&obs, obs.len));
    _ = audit_mod.tkdiag_obs_update(&obs[0], 0, audit_mod.TKDIAG_STATUS_BOOT);
    _ = audit_mod.tkdiag_obs_update(&obs[1], 0, audit_mod.TKDIAG_STATUS_RUN);
    _ = audit_mod.tkdiag_obs_update(&obs[2], 0, audit_mod.TKDIAG_STATUS_BOOT);
    try std.testing.expectEqual(@as(u64, 2), audit_mod.tkdiag_boot_failures(&obs, obs.len));
    try std.testing.expectEqual(@as(u64, 3), audit_mod.tkdiag_crashed_total(&agg, &obs, obs.len));
}

// ---------------------------------------------------------------------------
// Backpressure and backlog fields
// ---------------------------------------------------------------------------

test "tkdiag agg — total backpressure waits is a sum over the latest fragments, max queue depth a maximum" {
    var agg = try newAgg();
    var a = fragFor(0, 1);
    a.backpressure_waits = 10;
    a.max_queue_depth = 3;
    var b = fragFor(1, 1);
    b.backpressure_waits = 5;
    b.max_queue_depth = 40;
    try std.testing.expectEqual(@as(c_int, 1), audit_mod.tkdiag_agg_accept(&agg, 0, &a));
    try std.testing.expectEqual(@as(c_int, 1), audit_mod.tkdiag_agg_accept(&agg, 1, &b));
    try std.testing.expectEqual(@as(u64, 15), agg.total_backpressure_waits);
    try std.testing.expectEqual(@as(u64, 40), agg.max_queue_depth);

    // Cumulative counters replace, never add: tile 0 now reports 12 waits.
    var a2 = fragFor(0, 2);
    a2.backpressure_waits = 12;
    a2.max_queue_depth = 3;
    try std.testing.expectEqual(@as(c_int, 1), audit_mod.tkdiag_agg_accept(&agg, 0, &a2));
    try std.testing.expectEqual(@as(u64, 17), agg.total_backpressure_waits);
}

test "tkdiag backlog — fragments published beyond the one just processed" {
    // The producer has published sequence numbers up to 9 (next is 10); the tile
    // just processed 4, so 5 (5..9) are waiting.
    try std.testing.expectEqual(@as(u64, 5), audit_mod.tkdiag_backlog(10, 4));
    // Nothing waits when the tile is caught up, or when the producer's published
    // sequence lags the tile (it publishes its sequence only periodically).
    try std.testing.expectEqual(@as(u64, 0), audit_mod.tkdiag_backlog(5, 4));
    try std.testing.expectEqual(@as(u64, 0), audit_mod.tkdiag_backlog(3, 4));
    try std.testing.expectEqual(@as(u64, 0), audit_mod.tkdiag_backlog(0, 0));
}

test "tkdiag backlog — correct across the 64-bit sequence wrap" {
    const max = std.math.maxInt(u64);
    // Producer is 3 past the wrap, tile is 2 before it: sequence numbers
    // max-1, max, 0, 1, 2 lie between, after the one just processed (max-2).
    try std.testing.expectEqual(@as(u64, 5), audit_mod.tkdiag_backlog(3, max - 2));
}
