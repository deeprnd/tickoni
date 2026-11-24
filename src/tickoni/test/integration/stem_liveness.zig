/// Shared CNC-liveness assertions for fd_stem tiles in process-mode runs.
///
/// A stem tile joins the supervisor's staleness model only if its
/// `STEM_CALLBACK_DURING_HOUSEKEEPING` calls `stk_cnc_liveness`
/// (shim/stem_helpers.h), which advances the CNC heartbeat and moves the CNC
/// `BOOT -> RUN` on the first loop iteration; see
/// doc/knowledge/tile-orchestration.md, "Health And Lifecycle". A tile that
/// omits it stays `.running` forever, however wedged, so a `.running` state
/// is not evidence of progress. These helpers assert the evidence directly:
///
///   * every stem tile of a run (chosen from tile_registry.zig by launch mode,
///     plus the metric tile; not a hand-kept list) is at CNC `RUN` and its
///     heartbeat advances while it is idle;
///   * a stem tile frozen with SIGSTOP is classified `.stale` by
///     `refreshProcessHealth`, and one frozen tile does not make its siblings
///     stale.
///
/// The helper is a module shared by several integration test roots; each root
/// starts its own topology (with `event_count = 0`, which disables the event
/// gates so every stem tile idles until HALT) and passes the running
/// supervisor in.
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const supervisor_mod = @import("supervisor");
const util = @import("util");

const Supervisor = supervisor_mod.Supervisor;
const tile_registry = supervisor_mod.tile_registry;

/// Stale threshold every liveness run configures. It is far above a stem
/// loop's worst housekeeping gap (about 40 ms) so a healthy tile is never
/// classified stale by scheduler jitter, and short enough that a frozen tile
/// is classified within a couple of seconds.
pub const stale_after_ns: u64 = 1 * std.time.ns_per_s;

const poll_ns: u64 = 5 * std.time.ns_per_ms;
/// 10 s: a child boots its topology and joins its workspaces before RUN.
const boot_polls: u32 = 2000;
/// 2 s: several heartbeat periods of an idle stem tile.
const advance_polls: u32 = 400;
/// 6 s: the stale threshold plus ample slack.
const stale_polls: u32 = 1200;

/// Whether the tile at topology index `idx` runs an fd_stem loop. That is every
/// registry `.stem` tile, plus the metric tile: it runs `fd_metric_tile.c`'s
/// stem loop but is launched under `__tile-run`, so its registry launch mode is
/// `.tile` and does not identify it.
pub fn isStem(idx: usize, sup: *const Supervisor) bool {
    const id = sup.topo.tiles[idx].name;
    if (id.eql(rt.tile_ids.metric)) return true;
    const entry = tile_registry.findById(id) orelse return false;
    return entry.launch_mode == .stem;
}

/// Index of the tile with this id (instance 0) in the supervisor's topology.
pub fn indexOf(sup: *const Supervisor, id: rt.tile.TileId) usize {
    for (sup.topo.tiles, 0..) |tile, i| {
        if (tile.name.eql(id)) return i;
    }
    unreachable; // The caller names a tile its own topology configures.
}

/// The CNC the tile at topology index `idx` itself signals and heartbeats.
/// `ProcessState.cncs` is indexed by Firedancer tile index, which differs from
/// the topology (descriptor) index when `topo_build` moves the metric tile to
/// the end (metric and tkdiag swap), so the tile is looked up by identity.
fn cncOf(sup: *Supervisor, idx: usize) !*c_abi.cnc.Cnc {
    const state = sup.process_state orelse return error.NoProcessState;
    const topo = sup.getTopo() orelse return error.NoProcessState;
    const tile = sup.topo.tiles[idx];
    var name_buf: [8]u8 = undefined;
    const fd_idx = c_abi.topob.topoFindTile(topo, util.toZ(&name_buf, tile.name.slice()), tile.kind_id);
    if (fd_idx == c_abi.topob.not_found) return error.TileNotFound;
    return state.cncs[fd_idx] orelse error.NoCnc;
}

fn nameOf(sup: *const Supervisor, idx: usize) []const u8 {
    return sup.topo.tiles[idx].name.slice();
}

fn childId(sup: *const Supervisor, idx: usize) !std.process.Child.Id {
    return sup.monitor()[idx].pid orelse error.NoChildPid;
}

fn expectControlled(failure: ?util.process_api.ProcessError) !void {
    if (failure) |f| {
        std.debug.print("stem_liveness: process control failed: {s} (native {d})\n", .{ @tagName(f.category), f.native_code });
        return error.ProcessControlFailed;
    }
}

/// Freezes the tile's process without ending it (the tile stays alive and
/// reapable). Cross-platform: the OS mechanism lives behind the C shim.
pub fn freezeTile(sup: *const Supervisor, idx: usize) !void {
    try expectControlled(util.process_api.suspendProcess(try childId(sup, idx)));
}

/// Thaws a tile frozen by `freezeTile`.
pub fn thawTile(sup: *const Supervisor, idx: usize) !void {
    try expectControlled(util.process_api.resumeProcess(try childId(sup, idx)));
}

/// Hard-kills the tile's process: no clean shutdown, no final fragment. The
/// supervisor is not told, so it observes this as a crash, not a stop it asked
/// for.
pub fn killTile(sup: *const Supervisor, idx: usize) !void {
    switch (util.process_api.forceTerminate(try childId(sup, idx))) {
        .accepted => {},
        .failed => |f| try expectControlled(f),
    }
}

/// Every stem tile reaches CNC `RUN`, then its heartbeat moves. Fails with the
/// tile's name on the first one that does not, and on a run with no stem tile
/// at all (which would make the check vacuous).
pub fn expectStemTilesAlive(sup: *Supervisor) !void {
    var stem_cnt: usize = 0;
    for (sup.topo.tiles, 0..) |_, idx| {
        if (!isStem(idx, sup)) continue;
        stem_cnt += 1;
        const cnc = try cncOf(sup, idx);

        var polls: u32 = 0;
        while (polls < boot_polls and c_abi.cnc.signalQuery(cnc) != c_abi.cnc.signal_run) : (polls += 1) {
            sup.reapExitedChildrenNoHang();
            if (sup.monitor()[idx].state == .crashed) break;
            util.process.sleepNanos(poll_ns);
        }
        if (c_abi.cnc.signalQuery(cnc) != c_abi.cnc.signal_run) {
            std.debug.print("stem_liveness: {s} never reached CNC RUN (signal={d}, state={s})\n", .{
                nameOf(sup, idx), c_abi.cnc.signalQuery(cnc), @tagName(sup.monitor()[idx].state),
            });
            return error.StemTileNotRunning;
        }

        const first = c_abi.cnc.heartbeatQuery(cnc);
        polls = 0;
        while (polls < advance_polls and c_abi.cnc.heartbeatQuery(cnc) == first) : (polls += 1) {
            util.process.sleepNanos(poll_ns);
        }
        if (c_abi.cnc.heartbeatQuery(cnc) == first) {
            std.debug.print("stem_liveness: {s} reached RUN but its heartbeat stayed at {d} ms\n", .{
                nameOf(sup, idx), first,
            });
            return error.StemHeartbeatNotAdvancing;
        }
    }
    try std.testing.expect(stem_cnt > 0);
}

/// No stem tile is `.stale` after a health refresh.
pub fn expectNoStemTileStale(sup: *Supervisor) !void {
    sup.refreshProcessHealth();
    for (sup.monitor(), 0..) |h, idx| {
        if (!isStem(idx, sup)) continue;
        if (h.state == .stale) {
            std.debug.print("stem_liveness: {s} is stale although nothing froze it\n", .{nameOf(sup, idx)});
            return error.HealthyStemTileStale;
        }
    }
}

fn waitStale(sup: *Supervisor, idx: usize) !void {
    var polls: u32 = 0;
    while (polls < stale_polls) : (polls += 1) {
        sup.refreshProcessHealth();
        if (sup.monitor()[idx].state == .stale) break;
        util.process.sleepNanos(poll_ns);
    }
    if (sup.monitor()[idx].state != .stale) {
        std.debug.print("stem_liveness: frozen {s} was never classified stale (state={s})\n", .{
            nameOf(sup, idx), @tagName(sup.monitor()[idx].state),
        });
        return error.FrozenStemTileNotStale;
    }
    try std.testing.expectEqual(rt.tile.CrashReason.stale, sup.monitor()[idx].crashed_because);
    // Stale, not dead: the process is still there, only its loop stopped.
    try std.testing.expect(sup.monitor()[idx].isAlive());
}

/// Freezes one stem tile and expects it, and only it among the
/// stem tiles, to be classified stale. The tile is resumed before returning.
pub fn expectFrozenTileGoesStaleAlone(sup: *Supervisor, frozen_idx: usize) !void {
    try std.testing.expect(isStem(frozen_idx, sup));
    try freezeTile(sup, frozen_idx);
    defer thawTile(sup, frozen_idx) catch {};

    try waitStale(sup, frozen_idx);
    for (sup.monitor(), 0..) |h, idx| {
        if (idx == frozen_idx or !isStem(idx, sup)) continue;
        if (h.state == .stale) {
            std.debug.print("stem_liveness: freezing {s} made {s} stale\n", .{
                nameOf(sup, frozen_idx), nameOf(sup, idx),
            });
            return error.SiblingStemTileStale;
        }
    }
}

fn resumeAllStem(sup: *const Supervisor) void {
    for (sup.monitor(), 0..) |_, idx| {
        if (isStem(idx, sup)) thawTile(sup, idx) catch {};
    }
}

/// Freezes every stem tile that is not stale yet and expects each to be
/// classified stale: no stem tile is exempt from the staleness model. All are
/// resumed before returning.
pub fn expectEveryFrozenStemTileGoesStale(sup: *Supervisor) !void {
    var frozen_cnt: usize = 0;
    defer resumeAllStem(sup);
    for (sup.monitor(), 0..) |h, idx| {
        if (!isStem(idx, sup) or h.state == .stale) continue;
        try freezeTile(sup, idx);
        frozen_cnt += 1;
    }
    try std.testing.expect(frozen_cnt > 0);
    for (sup.monitor(), 0..) |_, idx| {
        if (isStem(idx, sup)) try waitStale(sup, idx);
    }
}
