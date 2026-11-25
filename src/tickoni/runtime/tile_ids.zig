/// Canonical TileId registry for all Tickoni tiles.
/// Eliminates scattered "tknorm" / "tkdedu" / "tkpoly" / etc. string
/// literals and [6]u8 constants across the codebase.
///
/// Naming convention: TileId.bytes is [6]u8. If the human-readable name
/// exceeds 6 characters, it is truncated (not padded). The 6-byte form is
/// the ground truth for wire/format purposes. For example:
///   • "tkgate" (6 chars) → "tkgate" (exactly fits)
///   • "tkbrok" (6 chars) → "tkbrok" (exactly fits)
///   • "tkbrokr" (7 chars) → "tkbrok" (truncated to 6)
/// Documentation may reference the human-readable form (e.g. "tkbrokr"),
/// but the TileId constant always uses the 6-byte form.
const std = @import("std");
const tile = @import("tile.zig");

/// Re-exported from tile.zig so callers use tile_ids.TileId everywhere.
pub const TileId = tile.TileId;

/// Ingress tile — receives raw financial events from external streams.
pub const tkings: tile.TileId = .{ .bytes = "tkings".* };
/// Normalization tile — canonicalizes source-specific payloads.
pub const tknorm: tile.TileId = .{ .bytes = "tknorm".* };
/// Deduplication tile — removes duplicates via idempotency keys.
pub const tkdedu: tile.TileId = .{ .bytes = "tkdedu".* };
/// Policy tile — checks capability envelopes against policy.
pub const tkpoly: tile.TileId = .{ .bytes = "tkpoly".* };
/// Audit tile — records append-only, hash-chained audit events.
pub const tkaudt: tile.TileId = .{ .bytes = "tkaudt".* };
/// Replay tile — replays from captured inputs with external effects disabled.
pub const tkrepl: tile.TileId = .{ .bytes = "tkrepl".* };
/// Case routing tile — creates deterministic case state.
pub const tkcase: tile.TileId = .{ .bytes = "tkcase".* };
/// Dispatch tile — schedules bounded agent runs.
pub const tkdisp: tile.TileId = .{ .bytes = "tkdisp".* };
/// Agent tile — runs bounded agents after event/case state is auditable.
pub const tkagnt: tile.TileId = .{ .bytes = "tkagnt".* };
/// Model access tile — governs LLM server and model-provider access.
pub const tkmodl: tile.TileId = .{ .bytes = "tkmodl".* };
/// Tool broker tile — normalizes model-native function calls.
pub const tktool: tile.TileId = .{ .bytes = "tktool".* };
/// Adapter tile — finance-native adapter reads and proposals.
pub const tkadpt: tile.TileId = .{ .bytes = "tkadpt".* };
/// Approved execution tile — privileged mutation paths.
pub const tkexec: tile.TileId = .{ .bytes = "tkexec".* };
/// Broker bridge tile — routes broker requests (place, cancel, query) to
/// per-account broker implementations (IBKR, Schwab, SnapTrade, …).
pub const tkbrok: tile.TileId = .{ .bytes = "tkbrok".* };
/// CaseOps gate tile — HTTP/WebSocket API for CaseOps.
pub const tkgate: tile.TileId = .{ .bytes = "tkgate".* };
/// Metrics tile — collects and exposes runtime metrics.
pub const metric: tile.TileId = .{ .bytes = "metric".* };
/// Diagnostics tile — runtime diagnostics and health checks.
pub const tkdiag: tile.TileId = .{ .bytes = "tkdiag".* };

/// All known tile IDs, ordered by Firedancer tile index.
pub const all: [17]tile.TileId = .{
    tkings, tknorm, tkdedu, tkpoly, tkaudt, tkrepl, tkcase, tkdisp,
    tkagnt, tkmodl, tktool, tkadpt, tkexec, tkbrok, tkgate, metric,
    tkdiag,
};

/// Lookup: returns the TileId for a name string, or null.
pub fn lookup(name: []const u8) ?tile.TileId {
    for (all) |id| {
        if (std.mem.eql(u8, id.slice(), name)) return id;
    }
    return null;
}

test "all tile IDs resolve from lookup" {
    for (all) |id| {
        const found = lookup(id.slice()) orelse unreachable;
        try std.testing.expect(found.eql(id));
    }
}

test "lookup returns null for unknown name" {
    try std.testing.expect(lookup("unknown") == null);
    try std.testing.expect(lookup("") == null);
}

test "lookup matches known tile names" {
    try std.testing.expect(lookup("tkings") != null);
    try std.testing.expect(lookup("tknorm") != null);
    try std.testing.expect(lookup("tkdedu") != null);
    try std.testing.expect(lookup("tkpoly") != null);
    try std.testing.expect(lookup("tkaudt") != null);
    try std.testing.expect(lookup("tkrepl") != null);
    try std.testing.expect(lookup("tkgate") != null);
    try std.testing.expect(lookup("metric") != null);
}
