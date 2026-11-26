/// Internal `__stem-run <spec-file>` child entry point. Rebuilds the topology
/// and dispatches to the tile's fd_stem-based run loop.
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const config = @import("tile_main_config.zig");
const model_instances = @import("model_instances.zig");
const logger = @import("logger");

/// The tile's own fd_stem loop handles its lifecycle.
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
    spec.checkAgainst(topo_desc) catch |err| {
        std.debug.print("tile_main: launch identity check failed for tile {d} ({s}#{d}): {t}\n", .{ spec.tile_idx, spec.tile_id.slice(), spec.tile_kind_id, err });
        return 1;
    };

    std.debug.print("[tile-main] stemRun: calling topo_build.build\n", .{});
    // tkcase's case-id seed (0: from the tick counter). Read in its privileged_init.
    c_abi.tkcase.setRngSeed(topo_spec.case_rng_seed);
    const built = rt.topo_build.build(allocator, topo_desc, spec.workspace_name.slice(), topo_spec.metric_port, topo_spec.event_count) catch |err| {
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
    // avoids a double-join that
    // corrupts workspace state (stemRun's explicit topoJoinWorkspaces +
    // topoWkspNewChild + Firedancer's internal join caused SIGSEGV in tkaudt).
    std.debug.print("[tile-main] stemRun: skipping explicit workspace join (fd_topo_run_tile handles it)\n", .{});

    var tile_id_buf: [7]u8 = undefined;
    const id_slice = spec.tile_id.slice();
    @memcpy(tile_id_buf[0..id_slice.len], id_slice);
    tile_id_buf[id_slice.len] = 0;
    const tile_id_z: [*:0]const u8 = @ptrCast(&tile_id_buf);

    std.debug.print("[tile-main] stemRun: calling topoFindTile\n", .{});
    const tile_idx = c_abi.topob.topoFindTile(built.topo, tile_id_z, spec.tile_kind_id);
    if (tile_idx == c_abi.topob.not_found) {
        std.debug.print("tile_main: tile {s}#{d} not found in rebuilt topology\n", .{ id_slice, spec.tile_kind_id });
        return 1;
    }
    // Test-build liveness faults apply to whichever stem tile the supervisor
    // selected, through the shared stem liveness path (stk_cnc_liveness).
    if (rt.test_build.enabled) c_abi.cnc.setLivenessFaults(spec.crash_after_heartbeats, spec.stuck_after_heartbeats);
    // tkpoly is the only stem tile with a behavior parameter outside
    // TopologySpec: the signed policy limit lives in payment_pipeline.config,
    // written by the supervisor beside topology.spec. Load it here, before
    // the C harness runs — neither privileged_init nor a fragment callback
    // may read a file. Fail closed: tk_policy_stem.c's privileged_init
    // rejects an unconfigured limit rather than falling back to a default.
    if (rt.tile_ids.tkpoly.eql(spec.tile_id)) {
        config.loadPolicyLimit(io, &spec, topo_spec.event_count, null) catch |err| {
            std.debug.print(
                "tile_main: tkpoly policy limit handoff failed for tile {d}: {t}\n",
                .{ spec.tile_idx, err },
            );
            return 1;
        };
    }

    // tkmodl's limits, allowlist and fixture table live in this instance's own
    // tkmodl.<kind_id>.config. Same fail-closed rule as the policy limit:
    // tk_model_stem.c's privileged_init rejects an unconfigured tile, and
    // loadModelConfig installs nothing from a missing, swapped, stale,
    // malformed or live-enabled file.
    if (rt.tile_ids.tkmodl.eql(spec.tile_id)) {
        _ = config.loadModelConfig(io, &spec, model_instances.instanceCount(topo_desc), null, allocator) catch |err| {
            std.debug.print(
                "tile_main: tkmodl config handoff failed for tile {d}: {t}\n",
                .{ spec.tile_idx, err },
            );
            return 1;
        };
    }

    // tkrepl: Zig owns the replay verdict. Register it before the C harness
    // runs; a tile with a capsule to replay refuses to start without it.
    if (rt.tile_ids.tkrepl.eql(spec.tile_id)) {
        config.loadReplaySetup() catch |err| {
            std.debug.print(
                "tile_main: tkrepl verdict hook setup failed for tile {d}: {t}\n",
                .{ spec.tile_idx, err },
            );
            return 1;
        };
    }

    // tkagnt: Zig owns its decisions. Register them and the tier-to-instance
    // routes before the C harness runs; the tile refuses to start without them.
    if (rt.tile_ids.tkagnt.eql(spec.tile_id)) {
        config.loadAgentSetup(io, topo_desc, spec.shmemPath(), null, allocator) catch |err| {
            std.debug.print(
                "tile_main: tkagnt setup failed for tile {d}: {t}\n",
                .{ spec.tile_idx, err },
            );
            return 1;
        };
    }

    // tkdisp sends the run's dispatch template for every payment event (an
    // agent-request event carries its own request); the template must be
    // installed before the C harness runs.
    if (rt.tile_ids.tkdisp.eql(spec.tile_id)) {
        config.loadDispatchTemplate(io, &spec, null, allocator) catch |err| {
            std.debug.print(
                "tile_main: tkdisp dispatch template handoff failed for tile {d}: {t}\n",
                .{ spec.tile_idx, err },
            );
            return 1;
        };
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

test {
    // Pull the config-handoff tests into the test-tile-main lane.
    _ = config;
}
