/// v2.14.S1 CPU placement policy: exclusive/shared/floating, validated
/// against this host's live CPU set. Tickoni-owned policy layered on top
/// of Firedancer substrate, not a Firedancer validator auto-layout concept
/// (see doc/knowledge/tile-topology.md's "Process And Core Placement
/// Boundary"). Combines util.cpu's live-host affinity primitive with
/// topology.zig's static schema; neither of those two depends on the
/// other or on this file.
///
/// Topology.validate() (topology.zig) already covers the static,
/// host-independent structural checks: two tiles claiming the same
/// exclusive id, or claiming the same id where either side does not
/// declare `shared`. This module adds the check that needs live host
/// information — whether a declared CPU id actually exists in this
/// process's affinity mask — and reports the resulting layout shape for
/// supervisor/diagnostics visibility (v2.14.S1.T14: shared-core placement
/// must stay explicit, not an implicit auto-layout).
const std = @import("std");

/// Matches util.cpu.CpuSet's layout so supervisor code can pass a live
/// affinity mask without this module depending on the util build module.
pub const cpu_set_bytes: usize = 128;
pub const CpuSet = [cpu_set_bytes]u8;

/// CPU placement policy for a tile process. Tickoni-owned; not a Firedancer
/// validator auto-layout field. `exclusive`/`shared` carry the pinned CPU id.
/// `shared` is the only mode where two tiles may declare the same CPU id.
pub const CpuPlacement = union(enum) {
    exclusive: u16,
    shared: u16,
    floating,
};

/// Per-tile placement counts and whether the layout uses shared-core
/// placement, for supervisor/CLI/diagnostics visibility.
pub const PlacementReport = struct {
    exclusive_count: usize = 0,
    shared_count: usize = 0,
    floating_count: usize = 0,
    /// True when at least two tiles declare `shared` on the same CPU id.
    /// Exclusive collisions can never reach here — topo.validate()
    /// already rejects those before this field is computed.
    shared_core: bool = false,
};

/// Fail-closed CPU placement validation: static structural checks via
/// topo.validate(), then every exclusive/shared tile's CPU id must be set
/// in `available_cpus` (this process's own affinity mask — the practical
/// stand-in for "exists on this host" without requiring root or a
/// separate host-topology query). Returns a PlacementReport once
/// validation passes; spawns nothing itself.
pub fn validate(topo: anytype, available_cpus: *const CpuSet) !PlacementReport {
    try topo.validate();

    var report = PlacementReport{};
    for (topo.tiles) |t| {
        switch (t.cpu_placement) {
            .exclusive => |c| {
                report.exclusive_count += 1;
                try requireAvailable(available_cpus, c);
            },
            .shared => |c| {
                report.shared_count += 1;
                try requireAvailable(available_cpus, c);
            },
            .floating => report.floating_count += 1,
        }
    }

    for (topo.tiles, 0..) |a, i| {
        const a_cpu = switch (a.cpu_placement) {
            .shared => |c| c,
            else => continue,
        };
        for (topo.tiles[i + 1 ..]) |b| {
            const b_cpu = switch (b.cpu_placement) {
                .shared => |c| c,
                else => continue,
            };
            if (a_cpu == b_cpu) {
                report.shared_core = true;
                break;
            }
        }
        if (report.shared_core) break;
    }

    return report;
}

/// Rejects two tiles pinned to the same CPU id unless both declare `shared`.
/// Available-CPU-id and oversubscription-against-the-live-host checks belong
/// to validate(), which has runtime CPU-set information.
pub fn validateStatic(tiles: anytype) !void {
    for (tiles, 0..) |a, i| {
        const a_cpu = switch (a.cpu_placement) {
            .exclusive => |cpu_id| cpu_id,
            .shared => |cpu_id| cpu_id,
            .floating => continue,
        };
        const a_shared = a.cpu_placement == .shared;
        for (tiles[i + 1 ..]) |b| {
            const b_cpu = switch (b.cpu_placement) {
                .exclusive => |cpu_id| cpu_id,
                .shared => |cpu_id| cpu_id,
                .floating => continue,
            };
            if (a_cpu != b_cpu) continue;
            const b_shared = b.cpu_placement == .shared;
            if (!a_shared or !b_shared) return error.CpuPlacementConflict;
        }
    }
}

/// cpu.isSet() asserts its cpu argument is in range — appropriate for call
/// sites that already validated the value themselves, but a declared tile
/// CPU id is external/config data (a plain u16 from topology.zig's
/// CpuPlacement union), not an internal invariant. This is the
/// fail-closed boundary check CLAUDE.md's Hard Constraints require ("CPU
/// placement fails closed for malformed or unavailable CPU ids"):
/// out-of-range ids are malformed, in-range-but-absent ids are
/// unavailable, and neither should reach an `unreachable`-backed assert.
fn requireAvailable(available_cpus: *const CpuSet, cpu_id: u16) !void {
    if (cpu_id >= cpu_set_bytes * 8) return error.CpuIdMalformed;
    if (!isSet(available_cpus, cpu_id)) return error.CpuUnavailable;
}

fn zero(cpu_set: *CpuSet) void {
    @memset(cpu_set, 0);
}

fn set(cpu_set: *CpuSet, cpu_id: usize) void {
    std.debug.assert(cpu_id < cpu_set_bytes * 8);
    cpu_set[cpu_id / 8] |= @as(u8, 1) << @intCast(cpu_id % 8);
}

fn isSet(cpu_set: *const CpuSet, cpu_id: usize) bool {
    std.debug.assert(cpu_id < cpu_set_bytes * 8);
    return (cpu_set[cpu_id / 8] & (@as(u8, 1) << @intCast(cpu_id % 8))) != 0;
}

// ---------------------------------------------------------------------------
// Tests — pure logic against synthetic CpuSet values; no real host
// affinity queried (matches util/cpu.zig's own test style).
// ---------------------------------------------------------------------------

const tile_mod = @import("tile.zig");
const TileId = tile_mod.TileId;

const TestTopology = struct {
    tiles: []const tile_mod.TileDescriptor,

    pub fn validate(self: @This()) !void {
        try validateStatic(self.tiles);
    }
};

/// Builds a minimal TileDescriptor for placement-validation tests below.
fn tile(idx: usize, name: []const u8, placement: CpuPlacement) tile_mod.TileDescriptor {
    return .{ .id = idx, .name = TileId.parse(name) catch unreachable, .cpu_placement = placement };
}

test "validate rejects an out-of-range exclusive cpu id as malformed, not an assert" {
    var cpus: CpuSet = undefined;
    zero(&cpus);
    set(&cpus, 0);

    const topo = TestTopology{
        .tiles = &.{tile(0, "tkfoo", .{ .exclusive = 65000 })},
    };
    try std.testing.expectError(error.CpuIdMalformed, validate(topo, &cpus));
}

test "validate rejects an exclusive cpu id not in available_cpus" {
    var cpus: CpuSet = undefined;
    zero(&cpus);
    set(&cpus, 0);

    const topo = TestTopology{
        .tiles = &.{tile(0, "tkfoo", .{ .exclusive = 1 })},
    };
    try std.testing.expectError(error.CpuUnavailable, validate(topo, &cpus));
}

test "validate rejects a shared cpu id not in available_cpus" {
    var cpus: CpuSet = undefined;
    zero(&cpus);
    set(&cpus, 0);

    const topo = TestTopology{
        .tiles = &.{tile(0, "tkfoo", .{ .shared = 5 })},
    };
    try std.testing.expectError(error.CpuUnavailable, validate(topo, &cpus));
}

test "validate propagates topo.validate()'s structural checks (duplicate exclusive)" {
    var cpus: CpuSet = undefined;
    zero(&cpus);
    set(&cpus, 0);

    const topo = TestTopology{
        .tiles = &.{
            tile(0, "tkfoo", .{ .exclusive = 0 }),
            tile(1, "tkbar", .{ .exclusive = 0 }),
        },
    };
    try std.testing.expectError(error.CpuPlacementConflict, validate(topo, &cpus));
}

test "validate reports floating-only topology with shared_core false" {
    var cpus: CpuSet = undefined;
    zero(&cpus);
    set(&cpus, 0);

    const topo = TestTopology{
        .tiles = &.{ tile(0, "tkfoo", .floating), tile(1, "tkbar", .floating) },
    };
    const report = try validate(topo, &cpus);
    try std.testing.expectEqual(@as(usize, 0), report.exclusive_count);
    try std.testing.expectEqual(@as(usize, 0), report.shared_count);
    try std.testing.expectEqual(@as(usize, 2), report.floating_count);
    try std.testing.expect(!report.shared_core);
}

test "validate reports shared_core true when two tiles share a cpu id" {
    var cpus: CpuSet = undefined;
    zero(&cpus);
    set(&cpus, 0);

    const topo = TestTopology{
        .tiles = &.{
            tile(0, "tkfoo", .{ .shared = 0 }),
            tile(1, "tkbar", .{ .shared = 0 }),
            tile(2, "tkbaz", .floating),
        },
    };
    const report = try validate(topo, &cpus);
    try std.testing.expectEqual(@as(usize, 2), report.shared_count);
    try std.testing.expectEqual(@as(usize, 1), report.floating_count);
    try std.testing.expect(report.shared_core);
}

test "validate reports shared_core false for distinct exclusive cpu ids" {
    var cpus: CpuSet = undefined;
    zero(&cpus);
    set(&cpus, 0);
    set(&cpus, 1);

    const topo = TestTopology{
        .tiles = &.{
            tile(0, "tkfoo", .{ .exclusive = 0 }),
            tile(1, "tkbar", .{ .exclusive = 1 }),
        },
    };
    const report = try validate(topo, &cpus);
    try std.testing.expectEqual(@as(usize, 2), report.exclusive_count);
    try std.testing.expect(!report.shared_core);
}
