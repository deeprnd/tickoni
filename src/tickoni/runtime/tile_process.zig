/// Generic single-tile process-mode lifecycle, reusable across any Tickoni
/// process-mode tile regardless of which pipeline it belongs to. Drives
/// Firedancer's real fd_topo_run_tile (src/disco/topo/fd_topo_run.c)
/// through the c_abi.topo_run/topob adapter (v2.14.S8.T3/T4) — a single
/// spawned process's own boot/attach/run/halt mechanics, with the
/// tile-specific work as a caller-supplied step — not the parent-side
/// orchestration loop that spawns and tracks every tile (that stays in
/// src/app/tickoni/supervisor.zig, matching Firedancer's own
/// src/app/shared/commands/run/run.c).
///
/// Lifecycle: read the launch spec and the shared topology spec -> rebuild
/// an identical topology (topo_build.build — see topo_build.zig's module
/// doc, "topology handoff" finding: every process rebuilds rather than
/// reattaching a serialized fd_topo_t) -> find this tile in it -> call the
/// simple launcher entrypoint in c_abi.topo_run. On Linux that entrypoint
/// dispatches straight to upstream fd_topo_run_tile; on non-Linux it falls
/// back to Tickoni's shim. That harness call drives three Tickoni-owned
/// and signals RUN, run calls `work` then heartbeats until HALT, checking
/// crash_after_heartbeats each iteration exactly like before this
/// migration). fd_topo_run_tile_t's callbacks have a fixed C signature
/// (fd_topo_t*, fd_topo_tile_t*) with no room for Zig closure state, so a
/// single per-process global (g_ctx) carries it instead — safe because
/// Tickoni runs exactly one tile per process. Never references
/// fd_topo_t/fd_topo_tile_t by name; callbacks take *anyopaque and cast
/// through c_abi.topob's opaque Topo/TopoTile only when they need to call
/// back into the adapter (e.g. to resolve this tile's cnc address).
const std = @import("std");
const c_abi = @import("c_abi");
const util = @import("util");
const launch_spec = @import("launch_spec.zig");
const topology_spec = @import("topology_spec.zig");
const topo_build = @import("topo_build.zig");
const tile_mod = @import("tile.zig");
const link_mod = @import("link.zig");
const boot = @import("boot.zig");
const logger = @import("logger");

pub const WorkFn = *const fn (
    io: std.Io,
    wksp: *c_abi.wksp.Wksp,
    spec: *const launch_spec.LaunchSpec,
    cnc: *c_abi.cnc.Cnc,
    allocator: std.mem.Allocator,
) anyerror!void;

/// Set once per process, at the bottom of run(), immediately before
/// calling into the harness; read only by the two exported callbacks
/// below. See this file's module doc for why a global is the right
/// pattern here (fd_topo_run_tile_t's fixed callback signature, one tile
/// per process).
var g_ctx: struct {
    spec: *const launch_spec.LaunchSpec = undefined,
    wksp_idx: usize = 0,
    cnc_obj_id: usize = 0,
    cnc: *c_abi.cnc.Cnc = undefined,
    work: WorkFn = undefined,
    io: std.Io = undefined,
    allocator: std.mem.Allocator = undefined,
    heartbeats: u32 = 0,
} = .{};

/// Resolves and joins this tile's cnc (not a Firedancer-standard link/tile
/// object, so fd_topo_fill_tile doesn't auto-join it — Tickoni's own
/// object, resolved the same way its "tile"/"cnc" object callbacks in
/// shim/topob.c do), then performs the same BOOT->RUN heartbeat+signal
/// transition tile_process.zig always has.
export fn tk_tile_privileged_init(topo: *anyopaque, tile: *anyopaque) callconv(.c) void {
    _ = tile;
    const topo_typed: *c_abi.topob.Topo = @ptrCast(topo);
    const laddr = c_abi.topob.topoObjLaddr(topo_typed, g_ctx.cnc_obj_id);
    g_ctx.cnc = c_abi.cnc.cncJoin(laddr) orelse {
        const log = logger.get();
        log.err("tile_process", "tk_tile_privileged_init", "fd_cnc_join failed") catch {};
        std.process.exit(1);
    };
    c_abi.cnc.heartbeat(g_ctx.cnc, util.process.monotonicNanos());
    // BOOT->RUN transition, but don't clobber an already-arrived HALT:
    // pre-T4, this write was unconditional (documented as "callers must
    // not request a stop before every tile has demonstrably reached
    // RUN"), because the old direct LaunchSpec.cnc_gaddr join was fast
    // enough that the race rarely mattered in practice. Rebuilding the
    // whole topology before a tile can even join its cnc (v2.14.S8.T4)
    // is much slower, especially for tiles with no pipeline work
    // (tkrepl/tkmetr/tkdiag) that the supervisor's poll-for-real-progress
    // callers have no reason to wait for — so a HALT sent while such a
    // tile is still booting is no longer a rare edge case. Checking first
    // costs nothing and makes the existing documented caveat fail safe
    // instead of hanging forever.
    if (c_abi.cnc.signalQuery(g_ctx.cnc) != c_abi.cnc.signal_halt) {
        c_abi.cnc.signal(g_ctx.cnc, c_abi.cnc.signal_run);
    }
}

/// Runs the tile-specific work, then heartbeats until the supervisor
/// signals HALT via the cnc — identical behavior to tile_process.zig's
/// pre-T4 flat run() loop, just now invoked as fd_topo_run_tile's `run`
/// callback instead of directly inside run() below. Exits the process
/// directly (no Zig defers) on any failure or the crash_after_heartbeats
/// test hook, since this callback has no way to propagate an error back
/// through fd_topo_run_tile's C call frames — matches the process-level
/// observable behavior (non-zero exit, cnc never reaches BOOT) the
/// crash-isolation tests (v2.14.S1.T12) check for.
export fn tk_tile_run(topo: *anyopaque, tile: *anyopaque) callconv(.c) void {
    _ = tile;
    const topo_typed: *c_abi.topob.Topo = @ptrCast(topo);
    const wksp = c_abi.topob.topoWkspPtr(topo_typed, g_ctx.wksp_idx) orelse {
        const log = logger.get();
        log.err("tile_process", "tk_tile_run", "workspace not joined") catch {};
        std.process.exit(1);
    };

    g_ctx.work(g_ctx.io, wksp, g_ctx.spec, g_ctx.cnc, g_ctx.allocator) catch |err| {
        const log = logger.get();
        var msg_buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "work failed for tile {d} ({s}): {t}", .{ g_ctx.spec.tile_idx, g_ctx.spec.tile_id.slice(), err }) catch "work failed";
        log.err("tile_process", "tk_tile_run", msg) catch {};
        std.process.exit(1);
    };

    while (true) {
        // Crash check before the halt check: privileged_init above may
        // have left an already-arrived HALT in place rather than
        // clobbering it (see that function's doc comment), so a tile
        // armed with crash_after_heartbeats must still get to evaluate
        // it on this first iteration instead of exiting via the halt
        // branch below without ever running its own crash hook — the
        // crash-isolation tests deliberately configure crash_after_heartbeats=1
        // specifically to fire on the very first iteration.
        g_ctx.heartbeats += 1;
        if (g_ctx.spec.crash_after_heartbeats > 0 and g_ctx.heartbeats >= g_ctx.spec.crash_after_heartbeats) {
            // Test-only crash-isolation hook (v2.14.S1.T12): exit without
            // a clean cnc transition, simulating an unexpected tile failure.
            std.process.exit(1);
        }

        const sig = c_abi.cnc.signalQuery(g_ctx.cnc);
        if (sig == c_abi.cnc.signal_halt) break;

        util.process.sleepNanos(g_ctx.spec.heartbeat_interval_ns);
        c_abi.cnc.heartbeat(g_ctx.cnc, util.process.monotonicNanos());
    }

    c_abi.cnc.signal(g_ctx.cnc, c_abi.cnc.signal_boot);
}

/// Read a file at an absolute path via the file_io helper.
fn readAbsoluteFile(io: std.Io, abs_path: []const u8) anyerror!launch_spec.LaunchSpec {
    const file = try @import("file_io.zig").openFile(io, std.Io.Dir.cwd(), abs_path);
    defer file.close(io);
    var spec: launch_spec.LaunchSpec = undefined;
    const buf = std.mem.asBytes(&spec);
    const n = try file.readPositionalAll(io, buf, 0);
    if (n != @sizeOf(launch_spec.LaunchSpec)) return error.LaunchSpecTruncated;
    if (spec.magic_field != launch_spec.magic) return error.LaunchSpecBadMagic;
    if (spec.version_field != launch_spec.version) return error.LaunchSpecUnsupportedVersion;
    if (spec.shmem_path_len > launch_spec.shmem_path_cap) return error.LaunchSpecMalformed;
    return spec;
}

/// Read a topology spec from an absolute path (see readAbsoluteFile).
fn readAbsoluteTopology(io: std.Io, abs_path: []const u8) anyerror!topology_spec.TopologySpec {
    const file = try @import("file_io.zig").openFile(io, std.Io.Dir.cwd(), abs_path);
    defer file.close(io);
    var spec: topology_spec.TopologySpec = undefined;
    const buf = std.mem.asBytes(&spec);
    const n = try file.readPositionalAll(io, buf, 0);
    if (n != @sizeOf(topology_spec.TopologySpec)) return error.TopologySpecTruncated;
    if (spec.magic_field != topology_spec.magic) return error.TopologySpecBadMagic;
    if (spec.version_field != topology_spec.version) return error.TopologySpecUnsupportedVersion;
    if (spec.tile_cnt > topology_spec.max_tiles or spec.channel_cnt > topology_spec.max_channels) return error.TopologySpecMalformed;
    return spec;
}

pub fn run(io: std.Io, allocator: std.mem.Allocator, spec_path: []const u8, work: WorkFn) u8 {
    const spec = readAbsoluteFile(io, spec_path) catch |err| {
        std.debug.print("tile_process: failed to read launch spec {s}: {t}\n", .{ spec_path, err });
        return 1;
    };

    std.debug.print("CHILD [tile {d} {s}]: shmem_path={s} workspace_name={s} crash_after_heartbeats={d}\n", .{
        spec.tile_idx,               spec.tile_id.slice(), spec.shmemPath(), spec.workspace_name.slice(),
        spec.crash_after_heartbeats,
    });

    // Per-tile log file: {shmemPath}/logs/tile_{idx}.log
    var log_path_buf: [256]u8 = undefined;
    const log_path = std.fmt.bufPrint(&log_path_buf, "{s}/logs/tile_{d}.log", .{ spec.shmemPath(), spec.tile_idx }) catch {
        std.debug.print("tile_process: log path too long for tile {d}\n", .{spec.tile_idx});
        return 1;
    };
    boot.bootWithSyntheticArgv(spec.shmemPath(), log_path) catch |err| {
        std.debug.print("tile_process: bootWithSyntheticArgv failed for tile {d}: {t}\n", .{ spec.tile_idx, err });
        return 1;
    };

    std.debug.print("CHILD [tile {d} {s}]: boot complete, shmem base={s}, workspace_name={s}\n", .{
        spec.tile_idx, spec.tile_id.slice(), spec.shmemPath(), spec.workspace_name.slice(),
    });

    // Workspace file is fsync'd by the supervisor after topoWkspNew completes
    // (supervisor.zig:syncWorkspace). Child processes can join immediately
    // without polling — the workspace data is guaranteed to be flushed.

    var built_opt: ?topo_build.BuiltTopo = null;
    defer {
        c_abi.boot.haltForTileProcess();
        if (built_opt) |*built| built.deinit(allocator);
    }

    var topology_spec_path_buf: [launch_spec.shmem_path_cap + 32]u8 = undefined;
    const topology_spec_path = std.fmt.bufPrint(&topology_spec_path_buf, "{s}/topology.spec", .{spec.shmemPath()}) catch {
        std.debug.print("tile_process: shmem path too long for tile {d}\n", .{spec.tile_idx});
        return 1;
    };
    const topo_spec = readAbsoluteTopology(io, topology_spec_path) catch |err| {
        std.debug.print("tile_process: failed to read topology spec for tile {d}: {t}\n", .{ spec.tile_idx, err });
        return 1;
    };
    std.debug.print("tile_process: DESERIALIZED TopologySpec tile_cnt={d} channel_cnt={d} workspace={s}\n", .{
        topo_spec.tile_cnt, topo_spec.channel_cnt, spec.workspace_name.slice(),
    });
    var tiles_buf: [topology_spec.max_tiles]tile_mod.TileDescriptor = undefined;
    var channels_buf: [topology_spec.max_channels]link_mod.Channel = undefined;
    const topo_desc = topo_spec.toTopology(&tiles_buf, &channels_buf);
    std.debug.print("tile_process: rebuilt Topology tiles={d} channels={d}\n", .{ topo_desc.tiles.len, topo_desc.channels.len });

    const built = topo_build.build(allocator, topo_desc, spec.workspace_name.slice()) catch |err| {
        std.debug.print("tile_process: failed to rebuild topology for tile {d}: {t}\n", .{ spec.tile_idx, err });
        return 1;
    };
    std.debug.print("tile_process: topo_build.build done wksp_idx={d}\\n", .{built.wksp_idx});
    built_opt = built;

    var tile_id_buf: [7]u8 = undefined;
    const id_slice = spec.tile_id.slice();
    @memcpy(tile_id_buf[0..id_slice.len], id_slice);
    tile_id_buf[id_slice.len] = 0;
    const tile_id_z: [*:0]const u8 = @ptrCast(&tile_id_buf);

    const tile_idx = c_abi.topob.topoFindTile(built.topo, tile_id_z, 0);
    if (tile_idx == c_abi.topob.not_found) {
        std.debug.print("tile_process: tile {s} not found in rebuilt topology\n", .{id_slice});
        return 1;
    }
    c_abi.topob.topoTileSetAllowShutdown(built.topo, tile_idx, true);

    g_ctx = .{
        .spec = &spec,
        .wksp_idx = built.wksp_idx,
        .cnc_obj_id = built.cnc_obj_id[tile_idx],
        .work = work,
        .io = io,
        .allocator = allocator,
    };

    std.debug.print("tile_process: g_ctx set tile={d} wksp_idx={d} cnc_obj_id={d} calling runTileSimple\n", .{
        spec.tile_idx, g_ctx.wksp_idx, g_ctx.cnc_obj_id,
    });

    c_abi.topo_run.runTileSimple(built.topo, c_abi.topob.topoTilePtr(built.topo, tile_idx));
    std.debug.print("tile_process: runTileSimple returned tile={d}\n", .{spec.tile_idx});
    return 0;
}
