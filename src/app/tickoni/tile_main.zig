/// Entrypoint for the internal `__tile-run <spec-file>` subcommand that
/// src/app/tickoni/supervisor.zig's startPaymentPipelineProcess self-execs
/// into for every v2.14.S1 process-mode tile. Not part of the advertised
/// CLI surface (see main.zig's usage text) — this is a supervisor-to-child
/// handoff, matching the Firedancer convention of one binary re-exec'd per
/// tile rather than a family of small per-tile binaries.
///
/// The generic single-tile boot/heartbeat/halt lifecycle lives in
/// src/tickoni/runtime/tile_process.zig; this file only looks up this
/// tile's process-mode callback in tile_registry.zig (v2.14.S8.T1's single
/// source of truth for tile id -> behavior) and runs it.
///
/// fd_stem migration (v2.22.S5): Before run() calls runTileSimple(),
/// this function reads the launch spec, looks up tile-specific stem
/// callbacks in tile_registry, and registers them so that
/// tile_process.zig's privileged_init() picks them up via stemRegisterCtx()
/// during fd_stem's setup. On macOS, the callbacks remain null and the
/// old g_ctx.work() loop is used directly.
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const tile_registry = @import("tile_registry.zig");
const logger = @import("logger");

pub fn run(io: std.Io, allocator: std.mem.Allocator, spec_path: []const u8) u8 {
    const log = logger.get();
    log.enter("tile_main", "run") catch {};
    defer log.exit("tile_main", "run") catch {};

    log.debug("tile_main", "run", "loading spec from file") catch {};

    // v2.22.S5.T3: Read the launch spec early so we can look up stem
    // callbacks for this tile BEFORE run() calls runTileSimple().
    const spec = rt.tile_process.LaunchSpec.readFromFile(io, std.Io.Dir.cwd(), spec_path) catch |err| {
        std.debug.print("tile_main: failed to read launch spec {s}: {t}\n", .{ spec_path, err });
        return 1;
    };

    // Register tile-specific fd_stem callbacks before the harness call.
    // On Linux these populate g_ctx.stem_* so fd_stem dispatches into Zig.
    // On macOS these are ignored (old g_ctx.work() loop used directly).
    const stem_cb = tile_registry.getStemCallbacks(spec.tile_id);
    rt.tile_process.registerStemCallbacks(stem_cb);

    return rt.tile_process.run(io, allocator, spec_path, runPipelineStage);
}

/// Dispatches the deterministic payment pipeline stage for this tile's
/// role and runs it to completion (bounded by the shared payment-pipeline
/// config's event_count — see tile_registry.zig's loadProcessConfig). Runs
/// before the heartbeat/halt-wait loop above so the supervisor's stop
/// sequence (signal every cnc to halt, wait for exit) stays uniform
/// whether or not a tile has pipeline work.
///
/// tkrepl/tkmetr/tkdiag have no process-mode pipeline role yet — see the
/// module doc comment in tiles/payment_pipeline/process.zig for the scope
/// boundary; their tile_registry entry has process_fn == null and is a
/// no-op here.
fn runPipelineStage(io: std.Io, wksp: *c_abi.wksp.Wksp, spec: *const rt.launch_spec.LaunchSpec, cnc: *c_abi.cnc.Cnc, allocator: std.mem.Allocator) !void {
    const log = logger.get();
    try log.enter("tile_main", "runPipelineStage");
    defer log.exit("tile_main", "runPipelineStage") catch {};

    const entry = tile_registry.findById(spec.tile_id) orelse return error.UnregisteredTile;
    log.debug("tile_main", "runPipelineStage", "tile found in registry") catch {};
    const process_fn = entry.process_fn orelse return;
    try process_fn(io, wksp, spec, cnc, allocator);
}
