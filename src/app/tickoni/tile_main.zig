/// Entrypoint for the internal `__tile-run <spec-file>` subcommand that
/// src/app/tickoni/supervisor.zig's startPaymentPipelineProcess self-execs
/// into for every v2.14.S1 process-mode tile. Not part of the advertised
/// CLI surface (see main.zig's usage text) — this is a supervisor-to-child
/// handoff, matching the Firedancer convention of one binary re-execd per
/// tile rather than a family of small per-tile binaries.
///
/// The generic single-tile boot/heartbeat/halt lifecycle lives in
/// src/tickoni/runtime/tile_process.zig; this file only looks up this
/// tile's process-mode callback in tile_registry.zig (v2.14.S8.T1's single
/// source of truth for tile id -> behavior) and runs it.
///
/// stemRun: minimal boot path for stem tiles (tkaudt). Skips Zig callbacks
/// and heartbeat/halt loop — dispatches straight to the tile's own
/// fd_stem-based run loop via c_abi.topo_run.runTileSimple.
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const tile_registry = @import("tile_registry.zig");
const logger = @import("logger");

pub fn run(io: std.Io, allocator: std.mem.Allocator, spec_path: []const u8) u8 {
    const log = logger.get();
    log.enter("tile_main", "run");
    defer log.exit("tile_main", "run");

    log.debug("tile_main", "run", "loading spec from file");
    return rt.tile_process.run(io, allocator, spec_path, runPipelineStage);
}

/// Minimal boot path for stem tiles (tkaudt). Does NOT set up Zig callbacks
/// or a heartbeat loop — the tile's own fd_stem-based run loop (TK_AUDIT_RUN)
/// handles its full lifecycle via its own privileged_init and stem_run.
///
/// Returns 1 if setup fails before the harness call; 0 if the tile runs to
/// completion and the harness returns cleanly.
pub fn stemRun(io: std.Io, allocator: std.mem.Allocator, spec_path: []const u8) u8 {
    const log = logger.get();
    log.enter("tile_main", "stemRun");
    defer log.exit("tile_main", "stemRun");

    std.debug.print("[tile-main] stemRun: START\n", .{});

    const spec = rt.launch_spec.LaunchSpec.readFromFile(io, std.Io.Dir.cwd(), spec_path) catch |err| {
        std.debug.print("tile_main: failed to read launch spec {s}: {t}\n", .{ spec_path, err });
        return 1;
    };
    std.debug.print("[tile-main] stemRun: read launch spec ok\n", .{});

    // Build topology BEFORE boot. Firedancer's fd_boot() can interfere with
    // Zig's page_allocator; topology build only touches in-memory structures.
    var topology_spec_path_buf: [rt.launch_spec.shmem_path_cap + 32]u8 = undefined;
    const topology_spec_path = std.fmt.bufPrint(&topology_spec_path_buf, "{s}/topology.spec", .{spec.shmemPath()}) catch {
        std.debug.print("tile_main: shmem path too long for tile {d}\n", .{spec.tile_idx});
        return 1;
    };
    const topo_spec = rt.topology_spec.TopologySpec.readFromFile(io, std.Io.Dir.cwd(), topology_spec_path) catch |err| {
        std.debug.print("tile_main: failed to read topology spec for tile {d}: {t}\n", .{ spec.tile_idx, err });
        return 1;
    };
    var tiles_buf: [rt.topology_spec.max_tiles]rt.tile.TileDescriptor = undefined;
    var channels_buf: [rt.topology_spec.max_channels]rt.link.Channel = undefined;
    std.debug.print("[tile-main] stemRun: calling toTopology\n", .{});

    const topo_desc = topo_spec.toTopology(&tiles_buf, &channels_buf);
    std.debug.print("[tile-main] stemRun: toTopology ok\n", .{});

    std.debug.print("[tile-main] stemRun: calling topo_build.build\n", .{});
    const built = rt.topo_build.build(allocator, topo_desc, spec.workspace_name.slice(), topo_spec.metric_port) catch |err| {
        std.debug.print("tile_main: failed to rebuild topology for tile {d}: {t}\n", .{ spec.tile_idx, err });
        return 1;
    };
    std.debug.print("[tile-main] stemRun: topo_build.build ok\n", .{});
    var built_opt: ?rt.topo_build.BuiltTopo = built;
    errdefer c_abi.boot.haltForTileProcess();
    errdefer if (built_opt) |*b| b.deinit(allocator);

    // Boot Firedancer AFTER topology build (avoids allocator interference)
    rt.boot.bootWithSyntheticArgv(spec.shmemPath(), "") catch |err| {
        std.debug.print("tile_main: bootWithSyntheticArgv failed for tile {d}: {t}\n", .{ spec.tile_idx, err });
        return 1;
    };
    std.debug.print("[tile-main] stemRun: bootWithSyntheticArgv ok\n", .{});

    // Firedancer's fd_topo_run_tile (called via runTileSimple below) handles
    // workspace joining internally: it calls fd_topo_join_tile_workspaces
    // before privileged_init, scratch allocation, and tile_run->run. This
    // matches the tkings/__tile-run path and avoids a double-join that
    // corrupts workspace state (stemRun's explicit topoJoinWorkspaces +
    // topoWkspNewChild + Firedancer's internal join caused SIGSEGV in tkaudt).
    std.debug.print("[tile-main] stemRun: skipping explicit workspace join (fd_topo_run_tile handles it)\n", .{});

    var tile_id_buf: [7]u8 = undefined;
    const id_slice = spec.tile_id.slice();
    @memcpy(tile_id_buf[0..id_slice.len], id_slice);
    tile_id_buf[id_slice.len] = 0;
    const tile_id_z: [*:0]const u8 = @ptrCast(&tile_id_buf);

    std.debug.print("[tile-main] stemRun: calling topoFindTile\n", .{});
    const tile_idx = c_abi.topob.topoFindTile(built.topo, tile_id_z, 0);
    if (tile_idx == c_abi.topob.not_found) {
        std.debug.print("tile_main: tile {s} not found in rebuilt topology\n", .{id_slice});
        return 1;
    }
    std.debug.print("[tile-main] stemRun: topoFindTile ok, calling runTileSimple\n", .{});
    c_abi.topob.topoTileSetAllowShutdown(built.topo, tile_idx, true);

    c_abi.topo_run.runTileSimple(built.topo, c_abi.topob.topoTilePtr(built.topo, tile_idx));
    // This line is reached ONLY if runTileSimple returns cleanly.
    // If the tile crashes inside fd_topo_run_tile (before or inside tk_audit_run),
    // this line is never reached and the crash output comes from the C side.
    std.debug.print("[tile-main] stemRun: runTileSimple returned\n", .{});
    return 0;
}

/// Dispatches the deterministic payment pipeline stage for this tile's
/// role and runs it to completion (bounded by the shared payment-pipeline
/// config's event_count — see tile_registry.zig's loadProcessConfig). Runs
/// before the heartbeat/halt-wait loop above so the supervisor's stop
/// sequence (signal every cnc to halt, wait for exit) stays uniform
/// whether or not a tile has pipeline work.
///
/// tkrepl/metric/tkdiag have no process-mode pipeline role yet — see the
/// module doc comment in tiles/payment_pipeline/process.zig for the scope
/// boundary; their tile_registry entry has process_fn == null and is a
/// no-op here.
fn runPipelineStage(io: std.Io, wksp: *c_abi.wksp.Wksp, spec: *const rt.launch_spec.LaunchSpec, cnc: *c_abi.cnc.Cnc, allocator: std.mem.Allocator) !void {
    const log = logger.get();
    log.enter("tile_main", "runPipelineStage");
    defer log.exit("tile_main", "runPipelineStage");

    const entry = tile_registry.findById(spec.tile_id) orelse return error.UnregisteredTile;
    log.debug("tile_main", "runPipelineStage", "tile found in registry");
    const process_fn = entry.process_fn orelse return;
    try process_fn(io, wksp, spec, cnc, allocator);
}
