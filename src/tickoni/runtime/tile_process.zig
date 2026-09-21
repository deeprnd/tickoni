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
///
/// Link joining (v2.22.S5): Before runTileSimple() starts the stem loop,
/// this file joins the tile's input/output links (mcache, dcache, fseq)
/// and populates g_ctx's link handles + config so the fd_stem callbacks
/// can do real dcache work.
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

/// Per-process tile state — one instance per tile process. Named type so
/// the C callback wrappers can cast from *anyopaque back to it.
pub const GCtx = struct {
    spec: *const launch_spec.LaunchSpec = undefined,
    wksp_idx: usize = 0,
    cnc_obj_id: usize = 0,
    cnc: *c_abi.cnc.Cnc = undefined,
    work: WorkFn = undefined,
    io: std.Io = undefined,
    allocator: std.mem.Allocator = undefined,
    heartbeats: u32 = 0,
    /// topo_ptr + tile_idx passed from run() to privileged_init() so
    /// privileged_init can do workspace join + link joining AFTER
    /// fd_topo_join_workspace runs (inside runTileSimple).
    topo_ptr: ?*c_abi.topob.Topo = null,
    tile_idx: u32 = 0,
    /// Set during privileged_init after workspace is joined; used
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

    // ------------------------------------------------------------------
    // fd_stem link handles + config + state. Set before the stem loop
    // starts (here in run(), before runTileSimple()); accessed by the
    // fd_stem callbacks (tile_registry.zig). On macOS these are unused
    // — the old g_ctx.work() loop uses rt.link.Consumer/Producer instead.
    // ------------------------------------------------------------------

    /// Output link handles — populated for producer tiles (tkings) and
    /// 1-out tiles (tknorm, tkdedu, tkpoly).
    out_mcache: ?[*]c_abi.queue.FragMeta = null,
    out_dcache_base: ?[*]u8 = null,
    out_fseq: ?[*]volatile u64 = null,
    out_depth: usize = 0,
    out_mtu: usize = 0,
    out_next_seq: u64 = 0,

    /// Input link handles — populated for consumer tiles (tkaudt) and
    /// 1-in tiles (tknorm, tkdedu, tkpoly).
    in_mcache: ?[*]c_abi.queue.FragMeta = null,
    in_fseq: ?[*]volatile u64 = null,
    in_depth: usize = 0,
    in_mtu: usize = 0,
    in_next_seq: u64 = 0,

    /// Process-mode config (shared by all tiles in the run).
    event_count: u64 = 0,
    policy_limit_cents: i64 = 0,
    inject_duplicate: bool = false,
    inject_malformed: bool = false,

    /// Atomic stop flag — checked by callbacks before each iteration.
    stop_flag: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    /// Counters — written to cnc app-region by the wrapper after the
    /// stem loop completes (so fd_stem can drive the loop).
    produced: u64 = 0,
    normalized: u64 = 0,
    invalid: u64 = 0,
    duplicates: u64 = 0,
    allowed: u64 = 0,
    denied: u64 = 0,
    audited: u64 = 0,

    /// Dedup state — only used by tkdedu.
    seen_keys: []u64 = undefined,
    seen_hashes: []u64 = undefined,
    seen_count: usize = 0,
    seen_keys_owned: bool = false,
    seen_hashes_owned: bool = false,

    /// Audit log — only used by tkaudt.
    audit_log: ?*anyopaque = null, // *audit_sink.AuditLog
};

/// Set once per process, at the bottom of run(), immediately before
/// calling into the harness; read only by the two exported callbacks
/// below. See this file's module doc for why a global is the right
/// pattern here (fd_topo_run_tile_t's fixed callback signature, one tile
/// per process).
var g_ctx: GCtx = .{};

pub const WorkFn = *const fn (
    io: std.Io,
    wksp: *c_abi.wksp.Wksp,
    spec: *const launch_spec.LaunchSpec,
    cnc: *c_abi.cnc.Cnc,
    allocator: std.mem.Allocator,
) anyerror!void;

pub const LaunchSpec = launch_spec.LaunchSpec;

/// Resolves and joins this tile's cnc (not a Firedancer-standard link/tile
/// object, so fd_topo_fill_tile doesn't auto-join it — Tickoni's own
/// object, resolved the same way its "tile"/"cnc" object callbacks in
/// shim/topob.c do), then performs the same BOOT->RUN heartbeat+signal
/// transition tile_process.zig always has. Also registers tile-specific
/// stem callbacks via `stemRegisterCtx` on Linux so fd_stem's run loop
/// dispatches into Zig during its control flow.
///
/// Firedancer joins workspaces BEFORE calling privileged_init
/// (fd_topo_run.c line 78 → line 80), so the wksp ptr IS available here.
export fn tk_tile_privileged_init(_topo: *anyopaque, _tile: *anyopaque) callconv(.c) void {
    const topo_typed: *c_abi.topob.Topo = @ptrCast(_topo);
    const tile_ptr = @as(*c_abi.topob.TopoTile, @ptrCast(_tile));

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

    // Register stem callbacks for Linux: Firedancer already joined workspaces
    // (fd_topo_join_tile_workspaces runs before privileged_init on line 78),
    // so wksp_ptr is valid. On Linux, fd_stem calls tk_stem_run() directly
    // (not tk_tile_run), so callbacks must be registered here. On non-Linux,
    // tk_tile_run() is used and registration happens there.
    if (g_ctx.stem_before_credit != null or
        g_ctx.stem_during_frag != null or
        g_ctx.stem_after_credit != null or
        g_ctx.stem_metrics_write != null or
        g_ctx.stem_should_shutdown != null)
    {
        const wksp = c_abi.topob.topoWkspPtr(topo_typed, g_ctx.wksp_idx) orelse {
            const log = logger.get();
            log.err("tile_process", "tk_tile_privileged_init", "workspace not joined for stem registration") catch {};
            std.process.exit(1);
        };
        c_abi.stem.stemRegisterCtx(
            _topo,
            _tile,
            &g_ctx,
            wksp,
            g_ctx.stem_before_credit,
            g_ctx.stem_during_frag,
            g_ctx.stem_after_credit,
            g_ctx.stem_metrics_write,
            g_ctx.stem_should_shutdown,
        );
    }
    _ = tile_ptr;
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
    const topo_typed: *c_abi.topob.Topo = @ptrCast(topo);
    const wksp = c_abi.topob.topoWkspPtr(topo_typed, g_ctx.wksp_idx) orelse {
        const log = logger.get();
        log.err("tile_process", "tk_tile_run", "workspace not joined") catch {};
        std.process.exit(1);
    };

    // Register stem callbacks: workspace is now joined (after privileged_init),
    // so wksp_ptr is valid. Must happen before g_ctx.work() runs so stem loop
    // can find the context when it starts after work() returns.
    if (g_ctx.stem_before_credit != null or
        g_ctx.stem_during_frag != null or
        g_ctx.stem_after_credit != null or
        g_ctx.stem_metrics_write != null or
        g_ctx.stem_should_shutdown != null)
    {
        c_abi.stem.stemRegisterCtx(
            topo,
            tile,
            &g_ctx,
            wksp,
            g_ctx.stem_before_credit,
            g_ctx.stem_during_frag,
            g_ctx.stem_after_credit,
            g_ctx.stem_metrics_write,
            g_ctx.stem_should_shutdown,
        );
    }

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
    const ctx: *const GCtx = @ptrCast(@alignCast(zig_state));
    if (ctx.stem_before_credit) |cb| cb(zig_state, stem, charge_busy) else charge_busy.* = 0;
}

export fn tk_stem_during_frag(zig_state: *anyopaque, idx: c_uint, seq: c_ulong, sig: c_uint, chunk: c_ulong, sz: c_uint, ctl: c_uint) callconv(.c) void {
    const ctx: *const GCtx = @ptrCast(@alignCast(zig_state));
    if (ctx.stem_during_frag) |cb| cb(zig_state, idx, seq, sig, chunk, sz, ctl);
}

export fn tk_stem_after_credit(zig_state: *anyopaque, stem: *anyopaque, poll_in: *c_int, charge_busy: *c_int) callconv(.c) void {
    const ctx: *const GCtx = @ptrCast(@alignCast(zig_state));
    if (ctx.stem_after_credit) |cb| cb(zig_state, stem, poll_in, charge_busy) else {
        poll_in.* = 1;
        charge_busy.* = 0;
    }
}

export fn tk_stem_metrics_write(zig_state: *anyopaque) callconv(.c) void {
    const ctx: *const GCtx = @ptrCast(@alignCast(zig_state));
    if (ctx.stem_metrics_write) |cb| cb(zig_state);
}

export fn tk_stem_should_shutdown(zig_state: *anyopaque) callconv(.c) c_int {
    const ctx: *const GCtx = @ptrCast(@alignCast(zig_state));
    if (ctx.stem_should_shutdown) |cb| return cb(zig_state);
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
    std.debug.print("tile_process.run: START tile={s} spec={s}\n", .{ "UNKNOWN", spec_path });
    const spec = launch_spec.LaunchSpec.readFromFile(io, std.Io.Dir.cwd(), spec_path) catch |err| {
        std.debug.print("tile_process: failed to read launch spec {s}: {t}\n", .{ spec_path, err });
        return 1;
    };
    std.debug.print("tile_process.run: spec loaded tile_idx={d} workspace={s}\n", .{ spec.tile_idx, spec.workspace_name.slice() });

    boot.bootWithSyntheticArgv(spec.shmemPath()) catch |err| {
        std.debug.print("tile_process: bootWithSyntheticArgv failed for tile {d}: {t}\n", .{ spec.tile_idx, err });
        return 1;
    };
    var built_opt: ?topo_build.BuiltTopo = null;
    defer {
        c_abi.boot.haltForTileProcess();
        if (built_opt) |*built| built.deinit(allocator);
        if (g_ctx.seen_keys_owned) allocator.free(g_ctx.seen_keys);
        if (g_ctx.seen_hashes_owned) allocator.free(g_ctx.seen_hashes);
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

    // Join the workspace: the supervisor created it via wkspNewNamed
    // (normal-page) before launching tiles. We must attach to it (not
    // fd_topo_join_workspace which tries the huge-page path) so that
    // topoWkspPtr returns non-null and link joining works.
    var wksp_name_z_buf: [topo_build.concrete_workspace_name_cap]u8 = undefined;
    const wksp_name_z = topo_build.concreteWorkspaceName(
        &wksp_name_z_buf,
        spec.workspace_name.slice(),
    ) catch |err| {
        std.debug.print("tile_process: failed to build workspace name for tile {d}: {t}\n", .{ spec.tile_idx, err });
        return 1;
    };
    const wksp = c_abi.wksp.wkspAttach(wksp_name_z) orelse {
        std.debug.print("tile_process: wkspAttach failed for tile {d}\n", .{spec.tile_idx});
        return 1;
    };
    errdefer _ = c_abi.wksp.wkspDetach(wksp);

    // Also attach to the "metric_in" workspace so fd_topo_fill_tile can
    // populate TILE->metrics_ptr (FD_MGAUGE_SET will segfault on NULL).
    var metrics_wksp_name_buf: [topo_build.concrete_workspace_name_cap]u8 = undefined;
    const metrics_wksp_name_z = topo_build.concreteWorkspaceName(
        &metrics_wksp_name_buf,
        "metric_in",
    ) catch |err| {
        std.debug.print("tile_process: failed to build metrics wksp name for tile {d}: {t}\n", .{ spec.tile_idx, err });
        return 1;
    };
    const metrics_wksp = c_abi.wksp.wkspAttach(metrics_wksp_name_z) orelse {
        std.debug.print("tile_process: wkspAttach failed for metrics tile {d}\n", .{spec.tile_idx});
        return 1;
    };
    errdefer _ = c_abi.wksp.wkspDetach(metrics_wksp);

    // Register wksp in topology. The supervisor already called
    // topoWkspNew before launching tiles; tiles must NOT call it again
    // because that re-instantiates workspace objects and corrupts the
    // shared region. Also set the metrics workspace pointer so
    // fd_topo_run_tile's fd_topo_join_tile_workspaces doesn't try to
    // re-join it (which would fail since the region is already joined).
    const metrics_wksp_idx = c_abi.topob.topoFindWksp(built.topo, "metric_in");
    if (metrics_wksp_idx != c_abi.topob.not_found) {
        c_abi.topob.topoWkspSetPtr(built.topo, metrics_wksp_idx, metrics_wksp);
    }
    c_abi.topob.topoWkspSetPtr(built.topo, built.wksp_idx, wksp);

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

    // Load payment-pipeline config.  The supervisor writes ProcessConfigFile
    // (ProcessConfigFile{magic, version, cfg: ProcessRuntimeConfig{
    //   pipeline: PaymentPipelineConfig{event_count, queue_depth,
    //   policy_limit_cents, inject_duplicate, inject_malformed, sandbox_fail_at},
    //   stuck_tile: ?StuckTileHook{tile_idx, after_messages, sleep_ns}
    // }}).
    // This local layout MUST match the binary layout written by
    // tiles_mod.process.writeProcessConfig exactly.
    const process_config_magic: u32 = 0x544b5043; // "TKPC"
    const process_config_version: u16 = 1;
    const ProcessConfigFile = struct {
        magic_field: u32 = process_config_magic,
        version_field: u16 = process_config_version,
        // 2 bytes padding to align cfg (ProcessRuntimeConfig) to 8-byte boundary
        padding: [2]u8 = .{ 0, 0 },
        cfg: struct {
            pipeline: struct {
                event_count: u64 = 0,
                queue_depth: usize = 0,
                policy_limit_cents: i64 = 0,
                inject_duplicate: bool = false,
                inject_malformed: bool = false,
                // 6 bytes padding to align sandbox_fail_at to 8 bytes
                padding: [6]u8 = .{ 0, 0, 0, 0, 0, 0 },
                sandbox_fail_at: ?u64 = null,
            } = .{},
            // StuckTileHook: tile_idx(u32) + 4 padding + after_messages(u64) + sleep_ns(u64) = 24 bytes
            // ?StuckTileHook = discriminant(u1) + 7 padding + StuckTileHook(24) = 32 bytes
            stuck_tile: struct {
                discriminant: u1 = 0,
                padding: [7]u8 = .{ 0, 0, 0, 0, 0, 0, 0 },
                tile_idx: u32 = 0,
                after_messages: u64 = 0,
                sleep_ns: u64 = 0,
            } = .{},
        } = .{},
    };

    // The supervisor writes the config to cwd()/shmemPath()/payment_pipeline.config
    // so the tile opens the same shmem dir and reads "payment_pipeline.config" from it.
    const shmem_dir = std.Io.Dir.cwd().openDir(io, spec.shmemPath(), .{}) catch |err| {
        std.debug.print("tile_process: failed to open shmem dir for tile {d}: {t}\n", .{ spec.tile_idx, err });
        return 1;
    };
    defer shmem_dir.close(io);
    var pc_file: ProcessConfigFile = undefined;
    var file = shmem_dir.openFile(io, "payment_pipeline.config", .{}) catch |err| {
        std.debug.print("tile_process: failed to open config for tile {d}: {t}\n", .{ spec.tile_idx, err });
        return 1;
    };
    defer file.close(io);
    const buf = std.mem.asBytes(&pc_file);
    const n = file.readPositionalAll(io, buf, 0) catch |err| {
        std.debug.print("tile_process: failed to read config for tile {d}: {t}\n", .{ spec.tile_idx, err });
        return 1;
    };
    if (n != @sizeOf(ProcessConfigFile)) {
        std.debug.print("tile_process: config truncated\n", .{});
        return 1;
    }
    if (pc_file.magic_field != process_config_magic) {
        std.debug.print("tile_process: config bad magic 0x{x}\n", .{pc_file.magic_field});
        return 1;
    }
    if (pc_file.version_field != process_config_version) {
        std.debug.print("tile_process: config unsupported version {d}\n", .{pc_file.version_field});
        return 1;
    }

    g_ctx.event_count = pc_file.cfg.pipeline.event_count;
    g_ctx.policy_limit_cents = pc_file.cfg.pipeline.policy_limit_cents;
    g_ctx.inject_duplicate = pc_file.cfg.pipeline.inject_duplicate;
    g_ctx.inject_malformed = pc_file.cfg.pipeline.inject_malformed;

    // Join output link handles (for producer tiles and 1-out tiles).
    if (spec.out_cnt > 0 and spec.outLinks().len > 0) {
        const out_link = spec.outLinks()[0];
        const out_mcache_laddr = c_abi.wksp.wkspLaddr(wksp, out_link.mcache_gaddr) orelse {
            std.debug.print("tile_process: out mcache laddr failed\n", .{});
            return 1;
        };
        const out_dcache_laddr = c_abi.wksp.wkspLaddr(wksp, out_link.dcache_gaddr) orelse {
            std.debug.print("tile_process: out dcache laddr failed\n", .{});
            return 1;
        };
        const out_fseq_laddr = c_abi.wksp.wkspLaddr(wksp, out_link.fseq_gaddr) orelse {
            std.debug.print("tile_process: out fseq laddr failed\n", .{});
            return 1;
        };
        g_ctx.out_mcache = c_abi.queue.mcacheJoin(out_mcache_laddr) orelse {
            std.debug.print("tile_process: out mcache join failed\n", .{});
            return 1;
        };
        g_ctx.out_dcache_base = c_abi.dcache.dcacheJoin(out_dcache_laddr) orelse {
            std.debug.print("tile_process: out dcache join failed\n", .{});
            return 1;
        };
        g_ctx.out_fseq = c_abi.fseq.fseqJoin(out_fseq_laddr) orelse {
            std.debug.print("tile_process: out fseq join failed\n", .{});
            return 1;
        };
        g_ctx.out_depth = out_link.depth;
        g_ctx.out_mtu = out_link.mtu;
    }

    // Join input link handles (for consumer tiles and 1-in tiles).
    if (spec.in_cnt > 0 and spec.inLinks().len > 0) {
        const in_link = spec.inLinks()[0];
        const in_mcache_laddr = c_abi.wksp.wkspLaddr(wksp, in_link.mcache_gaddr) orelse {
            std.debug.print("tile_process: in mcache laddr failed\n", .{});
            return 1;
        };
        const in_fseq_laddr = c_abi.wksp.wkspLaddr(wksp, in_link.fseq_gaddr) orelse {
            std.debug.print("tile_process: in fseq laddr failed\n", .{});
            return 1;
        };
        g_ctx.in_mcache = c_abi.queue.mcacheJoin(in_mcache_laddr) orelse {
            std.debug.print("tile_process: in mcache join failed\n", .{});
            return 1;
        };
        g_ctx.in_fseq = c_abi.fseq.fseqJoin(in_fseq_laddr) orelse {
            std.debug.print("tile_process: in fseq join failed\n", .{});
            return 1;
        };
        g_ctx.in_depth = in_link.depth;
        g_ctx.in_mtu = in_link.mtu;
    }

    // Allocate dedup state for tkdedu (tile idx 2).
    if (std.mem.eql(u8, spec.tile_id.slice(), "tkdedu")) {
        const cap: usize = @intCast(g_ctx.event_count);
        g_ctx.seen_keys = allocator.alloc(u64, cap) catch |err| {
            std.debug.print("tile_process: alloc dedup keys failed: {t}\n", .{err});
            return 1;
        };
        g_ctx.seen_keys_owned = true;
        g_ctx.seen_hashes = allocator.alloc(u64, cap) catch |err| {
            std.debug.print("tile_process: alloc dedup hashes failed: {t}\n", .{err});
            return 1;
        };
        g_ctx.seen_hashes_owned = true;
    }

    // Leave input link handles before returning (consumer tiles will
    // join their input inside the work callback, not here).
    if (spec.in_cnt > 0 and spec.inLinks().len > 0) {
        _ = c_abi.queue.mcacheLeave(g_ctx.in_mcache.?);
        _ = c_abi.fseq.fseqLeave(@volatileCast(g_ctx.in_fseq.?));
    }

    c_abi.topo_run.runTileSimple(built.topo, c_abi.topob.topoTilePtr(built.topo, tile_idx));
    return 0;
}
