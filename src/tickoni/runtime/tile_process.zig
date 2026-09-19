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
///
/// fd_stem migration (v2.22.S5): On Linux, g_ctx.stem_* callbacks are
/// populated by tile_registry.zig's setupStemCallbacks() BEFORE run()
/// calls runTileSimple(). The C bridge (tk_stem.c) reads those callbacks
/// and registers them into tk_stem_ctx_t in workspace, so fd_stem's run
/// loop dispatches into Zig during its control flow. On macOS, the old
/// g_ctx.work() loop continues to work (platform fallback).
const std = @import("std");
const c = std.c;
const c_abi = @import("c_abi");
const util = @import("util");
const launch_spec = @import("launch_spec.zig");
const topology_spec = @import("topology_spec.zig");
const topo_build = @import("topo_build.zig");
const tile_mod = @import("tile.zig");
const link_mod = @import("link.zig");
const boot = @import("boot.zig");
const logger = @import("logger");
const tile_runtime = @import("../tiles/payment_pipeline/runtime.zig");
const payment_process = @import("../tiles/payment_pipeline/process.zig");

pub const WorkFn = *const fn (
    io: std.Io,
    wksp: *c_abi.wksp.Wksp,
    spec: *const launch_spec.LaunchSpec,
    cnc: *c_abi.cnc.Cnc,
    allocator: std.mem.Allocator,
) anyerror!void;

/// Re-export LaunchSpec so tile_main.zig can read it before calling run().
pub const LaunchSpec = launch_spec.LaunchSpec;

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
    /// Set during privileged_init before the stem loop starts; used
    /// by the fd_stem callbacks to find this tile's wksp for dcache
    /// chunk→laddr conversion.
    wksp_ptr: ?*c_abi.wksp.Wksp = null,
    /// Stem callback function pointers — set via setupStemCallbacks()
    /// before run() calls runTileSimple(). On macOS these are ignored
    /// and the old g_ctx.work() loop is used directly.
    stem_before_credit: ?c_abi.stem.BeforeCreditFn = null,
    stem_during_frag: ?c_abi.stem.DuringFragFn = null,
    stem_after_credit: ?c_abi.stem.AfterCreditFn = null,
    stem_metrics_write: ?c_abi.stem.MetricsWriteFn = null,
    stem_should_shutdown: ?c_abi.stem.ShouldShutdownFn = null,
} = .{};

/// Resolves and joins this tile's cnc (not a Firedancer-standard link/tile
/// object, so fd_topo_fill_tile doesn't auto-join it — Tickoni's own
/// object, resolved the same way its "tile"/"cnc" object callbacks in
/// shim/topob.c do), then performs the same BOOT->RUN heartbeat+signal
/// transition tile_process.zig always has. Also registers tile-specific
/// stem callbacks via `stemRegisterCtx` so fd_stem's run loop dispatches
/// into Zig during its control flow.
export fn tk_tile_privileged_init(topo: *anyopaque, tile: *anyopaque) callconv(.c) void {
    _ = topo;
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

    // Register stem callbacks: dispatches from fd_stem run loop into Zig.
    // Tile-specific callback implementations are set before run() calls
    // runTileSimple() via setupStemCallbacks(). On macOS these remain null
    // and the old g_ctx.work() loop is used directly.
    if (g_ctx.wksp_ptr != null) {
        c_abi.stem.stemRegisterCtx(
            topo,
            tile,
            &g_ctx,
            g_ctx.wksp_ptr,
            g_ctx.stem_before_credit,
            g_ctx.stem_during_frag,
            g_ctx.stem_after_credit,
            g_ctx.stem_metrics_write,
            g_ctx.stem_should_shutdown,
        );
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

// ---------------------------------------------------------------------------
// C-compatible callback wrappers.
//
// These are the functions passed to tk_stem_register_ctx().  Each wrapper
// reads the tile-specific callback from g_ctx and dispatches it.
// They are exported with callconv(.c) so the C shim can call them directly.
// ---------------------------------------------------------------------------

export fn tk_stem_before_credit(zig_state: *anyopaque, stem: *anyopaque, charge_busy: *c_int) callconv(.c) void {
    const ctx: *g_ctx.type = @ptrCast(zig_state);
    if (ctx.stem_before_credit) {
        ctx.stem_before_credit(zig_state, stem, charge_busy);
    } else {
        charge_busy.* = 0;
    }
}

export fn tk_stem_during_frag(zig_state: *anyopaque, idx: c_uint, seq: c_ulong, sig: c_uint, chunk: c_ulong, sz: c_uint, ctl: c_uint) callconv(.c) void {
    const ctx: *g_ctx.type = @ptrCast(zig_state);
    if (ctx.stem_during_frag) {
        ctx.stem_during_frag(zig_state, idx, seq, sig, chunk, sz, ctl);
    }
}

export fn tk_stem_after_credit(zig_state: *anyopaque, stem: *anyopaque, poll_in: *c_int, charge_busy: *c_int) callconv(.c) void {
    const ctx: *g_ctx.type = @ptrCast(zig_state);
    if (ctx.stem_after_credit) {
        ctx.stem_after_credit(zig_state, stem, poll_in, charge_busy);
    } else {
        poll_in.* = 1;
        charge_busy.* = 0;
    }
}

export fn tk_stem_metrics_write(zig_state: *anyopaque) callconv(.c) void {
    const ctx: *g_ctx.type = @ptrCast(zig_state);
    if (ctx.stem_metrics_write) {
        ctx.stem_metrics_write(zig_state);
    }
}

export fn tk_stem_should_shutdown(zig_state: *anyopaque) callconv(.c) c_int {
    const ctx: *g_ctx.type = @ptrCast(zig_state);
    if (ctx.stem_should_shutdown) {
        return ctx.stem_should_shutdown(zig_state);
    }
    return 0;
}

/// Registers fd_stem callback function pointers into g_ctx so that
/// privileged_init() can pick them up via stemRegisterCtx() during
/// runTileSimple(). Must be called BEFORE runTileSimple() is invoked.
///
/// On macOS, this is a no-op — the old g_ctx.work() loop is used directly.
/// On Linux, this populates g_ctx.stem_* so fd_stem dispatches into Zig.
pub fn registerStemCallbacks(
    before_credit: ?c_abi.stem.BeforeCreditFn,
    during_frag: ?c_abi.stem.DuringFragFn,
    after_credit: ?c_abi.stem.AfterCreditFn,
    metrics_write: ?c_abi.stem.MetricsWriteFn,
    should_shutdown: ?c_abi.stem.ShouldShutdownFn,
) void {
    g_ctx.stem_before_credit = before_credit;
    g_ctx.stem_during_frag = during_frag;
    g_ctx.stem_after_credit = after_credit;
    g_ctx.stem_metrics_write = metrics_write;
    g_ctx.stem_should_shutdown = should_shutdown;
}

/// Overload: accepts the StemCallbacks struct from tile_registry.zig.
pub fn registerStemCallbacksStruct(cb: struct {
    before_credit: ?c_abi.stem.BeforeCreditFn,
    during_frag: ?c_abi.stem.DuringFragFn,
    after_credit: ?c_abi.stem.AfterCreditFn,
    metrics_write: ?c_abi.stem.MetricsWriteFn,
    should_shutdown: ?c_abi.stem.ShouldShutdownFn,
}) void {
    registerStemCallbacks(cb.before_credit, cb.during_frag, cb.after_credit, cb.metrics_write, cb.should_shutdown);
}

/// Runs one process-mode tile to completion. `work` performs the caller's
/// tile-specific behavior (which links to join, which decision logic to
/// run) after this tile has joined its cnc and signalled RUN, and before
/// the heartbeat/halt-wait loop — both now driven through
/// fd_topo_run_tile via the two callbacks above. Returns 1 (with a
/// diagnostic on stderr) if setup before the harness call fails; a clean
/// RUN -> HALT -> BOOT transition returns 0. Failures inside the harness
/// call itself exit the process directly (see tk_tile_run's doc comment).
pub fn run(io: std.Io, allocator: std.mem.Allocator, spec_path: []const u8, work: WorkFn) u8 {
    const spec = launch_spec.LaunchSpec.readFromFile(io, std.Io.Dir.cwd(), spec_path) catch |err| {
        std.debug.print("tile_process: failed to read launch spec {s}: {t}\n", .{ spec_path, err });
        return 1;
    };

    boot.bootWithSyntheticArgv(spec.shmemPath()) catch |err| {
        std.debug.print("tile_process: bootWithSyntheticArgv failed for tile {d}: {t}\n", .{ spec.tile_idx, err });
        return 1;
    };
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
    const topo_spec = topology_spec.TopologySpec.readFromFile(io, std.Io.Dir.cwd(), topology_spec_path) catch |err| {
        std.debug.print("tile_process: failed to read topology spec for tile {d}: {t}\n", .{ spec.tile_idx, err });
        return 1;
    };
    var tiles_buf: [topology_spec.max_tiles]tile_mod.TileDescriptor = undefined;
    var channels_buf: [topology_spec.max_channels]link_mod.Channel = undefined;
    const topo_desc = topo_spec.toTopology(&tiles_buf, &channels_buf);

    const built = topo_build.build(allocator, topo_desc, spec.workspace_name.slice()) catch |err| {
        std.debug.print("tile_process: failed to rebuild topology for tile {d}: {t}\n", .{ spec.tile_idx, err });
        return 1;
    };
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

    // Populate wksp_ptr now so privileged_init can use it for stem callback
    // registration (tk_stem_zig_ctx needs wksp for dcache chunk→laddr).
    g_ctx.wksp_ptr = c_abi.topob.topoWkspPtr(built.topo, built.wksp_idx) orelse {
        std.debug.print("tile_process: workspace {d} not found for tile {d}\n", .{ built.wksp_idx, spec.tile_idx });
        return 1;
    };

    c_abi.topo_run.runTileSimple(built.topo, c_abi.topob.topoTilePtr(built.topo, tile_idx));
    return 0;
}
