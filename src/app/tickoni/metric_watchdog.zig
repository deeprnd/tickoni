/// Periodic metric sampling and delta printing for the supervisor.
///
/// This file implements the "No Black Boxes" audit fix: tiles produce
/// counters visible every ~1 second during execution, not only at the end.
const std = @import("std");

pub const TileMetricSnapshot = struct {
    tile_id: [6]u8,
    produced: u64,
    normalized: u64,
    invalid: u64,
    duplicates: u64,
    allowed: u64,
    denied: u64,
    audited: u64,
};

/// Print per-tile metric deltas between two snapshots to an io.Writer.
/// Uses a fixed buffer to avoid heap allocation during the sampling loop.
pub fn printPerTileDeltas(
    writer: std.Io.Writer,
    prev: []const TileMetricSnapshot,
    curr: []const TileMetricSnapshot,
) !void {
    const count = @min(prev.len, curr.len);
    for (prev[0..count], 0..) |p, i| {
        const c = curr[i];
        const delta_prod = @as(i64, @intCast(c.produced)) - @as(i64, @intCast(p.produced));
        const delta_norm = @as(i64, @intCast(c.normalized)) - @as(i64, @intCast(p.normalized));
        const delta_inv = @as(i64, @intCast(c.invalid)) - @as(i64, @intCast(p.invalid));
        const delta_dup = @as(i64, @intCast(c.duplicates)) - @as(i64, @intCast(p.duplicates));
        const delta_allow = @as(i64, @intCast(c.allowed)) - @as(i64, @intCast(p.allowed));
        const delta_deny = @as(i64, @intCast(c.denied)) - @as(i64, @intCast(p.denied));
        const delta_audit = @as(i64, @intCast(c.audited)) - @as(i64, @intCast(p.audited));
        var buf: [256]u8 = undefined;
        const line = try std.fmt.bufPrint(
            &buf,
            "  tile={s}  dP={d} dN={d} dI={d} dD={d} dA={d} dR={d} dU={d}\n",
            .{ c.tile_id[0..], delta_prod, delta_norm, delta_inv, delta_dup, delta_allow, delta_deny, delta_audit },
        );
        try writer.writeAll(line);
    }
}
