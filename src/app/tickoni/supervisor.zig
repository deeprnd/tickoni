/// Tickoni supervisor: owns tile handles for one topology, starts Phase 0
/// tiles as in-process threads (dev/test mode) or, for v2.14 process mode,
/// as supervisor-managed OS processes over Tango shared memory, and
/// provides start/stop/monitor for either mode.
const std = @import("std");
const rt = @import("runtime");
const tiles_mod = @import("tiles");
const c_abi = @import("c_abi");
const util = @import("util");
const topologies = @import("topologies");
const tile_registry = @import("tile_registry.zig");
const logger = @import("logger");

const Topology = rt.topology.Topology;
const TileHandle = rt.tile.TileHandle;
const TileState = rt.tile.TileState;
const CrashReason = rt.tile.CrashReason;
const PaymentPipelineConfig = tiles_mod.PaymentPipelineConfig;
const PaymentPipelineState = tiles_mod.PaymentPipelineState;

/// v2.14.S1 process-mode configuration for startPaymentPipelineProcess.
pub const ProcessPipelineConfig = struct {
    /// Directory used for per-tile launch-spec files and as FD_SHMEM_PATH
    /// for the shared Tango workspace. Caller-owned and required — no
    /// silent default, per the fail-closed environment-configuration rule.
    run_dir: []const u8,
    heartbeat_interval_ns: u64 = 20_000_000, // 20ms
    /// Supervisor classifies a tile as stale when its cnc heartbeat has
    /// not advanced for longer than this. 0 means derive a conservative
    /// default from heartbeat_interval_ns.
    heartbeat_stale_after_ns: u64 = 0,
    /// Test-only hook (v2.14.S1.T12 crash isolation): tile i self-exits(1)
    /// after this many heartbeats instead of waiting for a halt signal.
    /// 0 means run normally. Indexed by tile_idx.
    crash_after_heartbeats: [8]u32 = std.mem.zeroes([8]u32),
    /// Test-only hook (v2.14.S8.T6 stale-heartbeat proof): the selected
    /// tile blocks forever after stuck_after_messages loop iterations.
    stuck_tile_idx: ?u32 = null,
    stuck_after_messages: u64 = 0,
    /// Payment pipeline behavior, shared with thread-mode
    /// PaymentPipelineConfig so process-mode and thread-mode runs produce
    /// byte-identical decisions/metrics for the same input.
    event_count: u64 = 10_000,
    policy_limit_cents: i64 = 100_000,
    inject_duplicate: bool = true,
    inject_malformed: bool = false,
    /// Path to the tickoni-supervisor binary to self-exec per tile.
    /// Defaults to /proc/self/exe (correct when the running process IS
    /// tickoni-supervisor). Callers that are not that binary — such as
    /// `zig build integration-test`'s test runner — must set this
    /// explicitly, since /proc/self/exe would otherwise point at the
    /// test runner and every `__tile-run` re-exec would fail with
    /// "unrecognized command line argument".
    tile_exe_path: ?[]const u8 = null,
    /// When true, passes --verbose to child tile processes so their
    /// structured logger emits debug-level messages for troubleshooting.
    verbose: bool = false,
};

/// Supervisor-owned state for a running v2.14 process-mode pipeline.
const ProcessState = struct {
    wksp: *c_abi.wksp.Wksp,
    /// v2.14.S8.T12: the fd_topob-built topology backing this run's
    /// object layout (mcache/dcache/fseq/metrics/tile/cnc offsets).
    built_topo: rt.topo_build.BuiltTopo,
    workspace_name: []u8,
    run_dir: []u8,
    cnc_gaddrs: [8]usize,
    /// Parent-side cnc joins, used to send the halt signal during stop.
    cncs: [8]?*c_abi.cnc.Cnc,
    children: [8]?std.process.Child,
    heartbeat_stale_after_ns: u64,
    /// Grace period between requesting HALT and force-terminating tiles already
    /// classified stale. Lets slow but healthy children observe HALT and exit
    /// cleanly before stopProcess escalates to the platform kill path.
    stop_grace_ns: u64,
    /// v2.14.S1.T14 visibility: whether this run's layout is shared-core
    /// and how many tiles are exclusive/shared/floating.
    placement_report: rt.cpu_placement.PlacementReport,

    /// Kills any still-running children, leaves cnc joins, detaches the
    /// workspace, and frees owned buffers. Safe to call with a partially
    /// populated state (e.g. after a failed start).
    fn deinit(self: *ProcessState, io: std.Io, allocator: std.mem.Allocator) void {
        _ = io;
        for (&self.children) |*maybe_child| {
            if (maybe_child.*) |*child| {
                const pid = child.id orelse continue;
                util.process_api.forceTerminate(pid);
            }
        }
        for (&self.cncs) |*maybe_cnc| {
            if (maybe_cnc.*) |cnc| _ = c_abi.cnc.cncLeave(cnc);
        }
        self.built_topo.deinit(allocator);
        _ = c_abi.wksp.wkspDetach(self.wksp);
        c_abi.boot.halt();
        allocator.free(self.workspace_name);
        allocator.free(self.run_dir);
    }
};

fn resolvedHeartbeatStaleAfterNs(config: ProcessPipelineConfig) u64 {
    if (config.heartbeat_stale_after_ns != 0) return config.heartbeat_stale_after_ns;
    return resolvedHeartbeatIntervalNs(config, 5);
}

fn resolvedStopGraceNs(config: ProcessPipelineConfig) u64 {
    const from_heartbeat = resolvedHeartbeatIntervalNs(config, 5);
    return @min(@max(from_heartbeat, 500 * std.time.ns_per_ms), 2 * std.time.ns_per_s);
}

fn resolvedHeartbeatIntervalNs(config: ProcessPipelineConfig, multiplier: u64) u64 {
    return std.math.mul(u64, config.heartbeat_interval_ns, multiplier) catch std.math.maxInt(u64);
}

/// Bridges a tile_registry.RunFn resolved at runtime into std.Thread.spawn,
/// whose function argument must be comptime-known.
fn threadTrampoline(state: *PaymentPipelineState, run_fn: tile_registry.RunFn) void {
    run_fn(state);
}

pub const Supervisor = struct {
    allocator: std.mem.Allocator,
    topo: Topology,
    handles: []TileHandle,
    /// Heap-allocated so thread pointers remain stable across supervisor moves.
    pipeline: ?*PaymentPipelineState,
    /// Non-null while a v2.14 process-mode pipeline is running.
    process_state: ?*ProcessState = null,

    /// Runs topo.validate()'s structural checks (duplicate tile ids, channel
    /// depth/MTU shape, exclusive/shared CPU placement conflicts) once, at
    /// the one entrypoint every start path shares — so a caller cannot reach
    /// startPaymentPipeline (thread mode) without the check that
    /// startPaymentPipelineProcess already ran via cpu_placement.validate().
    /// Host-aware checks (is a declared CPU id actually available on this
    /// host) still belong to startPaymentPipelineProcess: thread mode never
    /// pins CPUs, so it has no live affinity mask to check against here.
    pub fn init(allocator: std.mem.Allocator, topo: Topology) !Supervisor {
        const log = logger.get();
        try log.enter("supervisor", "init");
        defer log.exit("supervisor", "init") catch {};
        try topo.validate();
        try tile_registry.validate(topo);
        const handles = try allocator.alloc(TileHandle, topo.tiles.len);
        for (handles, 0..) |*h, i| h.* = TileHandle.init(@intCast(i));
        return .{
            .allocator = allocator,
            .topo = topo,
            .handles = handles,
            .pipeline = null,
        };
    }

    /// Callers that used startPaymentPipelineProcess must call stopProcess
    /// before deinit; this assert makes a forgotten teardown loud instead of
    /// leaking child processes and shared memory.
    pub fn deinit(self: *Supervisor) void {
        const log = logger.get();
        log.enter("supervisor", "deinit") catch {};
        defer log.exit("supervisor", "deinit") catch {};
        std.debug.assert(self.process_state == null);
        self.stop();
        self.allocator.free(self.handles);
    }

    /// Start all Phase 0 tiles in thread mode.
    ///
    /// Requires topo to be exactly the paymentPipeline shape.
    pub fn startPaymentPipeline(self: *Supervisor, config: PaymentPipelineConfig) !void {
        const log = logger.get();
        try log.enter("supervisor", "startPaymentPipeline");
        defer log.exit("supervisor", "startPaymentPipeline") catch {};
        std.debug.assert(self.pipeline == null);
        std.debug.assert(self.topo.tiles.len == 8);

        const state = try self.allocator.create(PaymentPipelineState);
        var state_owned_by_pipeline = false;
        errdefer if (!state_owned_by_pipeline) self.allocator.destroy(state);

        state.* = try PaymentPipelineState.init(self.allocator, config);
        state_owned_by_pipeline = true;
        self.pipeline = state;
        errdefer self.stop();

        for (self.handles) |*h| h.state = .starting;

        // Dev/test lifecycle only.  The supervisor owns these thread starts;
        // tile modules must not spawn background execution owners themselves.
        // Looked up by tile id (not position) through the tile registry
        // (v2.14.S8.T1) — the single source of truth for tile id -> behavior.
        // std.Thread.spawn's function argument must be comptime-known, so
        // the runtime-resolved entry.run_fn is passed through a single
        // comptime-known trampoline rather than directly.
        for (self.handles, self.topo.tiles) |*h, tile| {
            const entry = tile_registry.findById(tile.id) orelse return error.UnregisteredTile;
            h.thread = try std.Thread.spawn(.{}, threadTrampoline, .{ state, entry.run_fn });
            h.state = .running;
        }
        var thread_count_buf: [16]u8 = undefined;
        const thread_count = std.fmt.bufPrint(&thread_count_buf, "{d}", .{self.handles.len}) catch "";
        log.debug("supervisor", "startPaymentPipeline", thread_count) catch {};
    }

    /// Start every tile in the topology as a separate OS process connected
    /// by Firedancer Tango shared memory (v2.14.S1). Requires
    /// topo.channels to be a tango_shm topology sharing exactly one
    /// workspace (paymentPipelineProcess() builds this shape).
    pub fn startPaymentPipelineProcess(self: *Supervisor, io: std.Io, config: ProcessPipelineConfig) !void {
        std.debug.assert(self.process_state == null);
        std.debug.assert(self.topo.tiles.len == 8);

        // Fail closed on any tile pinned to a CPU id this process cannot
        // actually use, before spawning anything — pinning more
        // exclusive/shared tiles than real cores exist (or above this
        // process's own affinity mask) has driven this host unresponsive
        // before. Also runs topo.validate()'s structural checks (duplicate
        // exclusive ids, channel/depth/MTU shape) and reports the
        // resulting layout for diagnostics visibility (v2.14.S1.T14).
        var available_cpus: util.cpu.CpuSet = undefined;
        try util.cpu.getAffinity(0, &available_cpus);
        const placement_report = try rt.cpu_placement.validate(self.topo, &available_cpus);

        try rt.boot.bootWithSyntheticArgv(config.run_dir);
        var boot_needs_halt = true;
        errdefer if (boot_needs_halt) c_abi.boot.halt();

        const workspace_name_slice = self.topo.channels[0].workspace_name.slice();
        if (workspace_name_slice.len == 0) return error.MissingWorkspaceName;
        for (self.topo.channels) |ch| {
            if (ch.backing != .tango_shm) return error.ProcessModeRequiresTangoShm;
            if (!std.mem.eql(u8, ch.workspace_name.slice(), workspace_name_slice)) return error.MultipleWorkspacesNotSupported;
        }

        // Ensure run_dir and its .normal FD_SHMEM_PATH subdirectory exist;
        // fd_wksp_new_named does not create either for us.
        var run_dir_handle = try std.Io.Dir.cwd().createDirPathOpen(io, config.run_dir, .{});
        run_dir_handle.close(io);
        const normal_dir = try std.fmt.allocPrint(self.allocator, "{s}/.normal", .{config.run_dir});
        defer self.allocator.free(normal_dir);
        var normal_dir_handle = try std.Io.Dir.cwd().createDirPathOpen(io, normal_dir, .{});
        normal_dir_handle.close(io);

        // v2.14.S8.T12: build the real Firedancer topology (object graph
        // and deterministic offsets) via fd_topob. Every self-exec'd
        // child rebuilds this same topology with identical inputs to get
        // byte-identical offsets — see topo_build.zig's module doc
        // ("topology handoff" finding). fd_topo_create_workspace/
        // fd_topo_join_workspace are deliberately not used here — they
        // hard-require huge/gigantic pages, which v2.14.S1 rejected for
        // Tickoni; see topob.zig's topoWkspSetPtr doc comment ("finding
        // 3") for the reused-layout-math/own-memory hybrid this drives.
        var built_topo = try rt.topo_build.build(self.allocator, self.topo, workspace_name_slice);
        var built_topo_owned_by_state = false;
        errdefer if (!built_topo_owned_by_state) built_topo.deinit(self.allocator);

        // v2.14.S8.T4: the actual shmem region name must match exactly
        // what fd_topo_join_workspace (called inside fd_topo_run_tile,
        // automatically, before any Tickoni callback runs) constructs and
        // looks up — Firedancer's own "%s_%s.wksp" app_name/wksp-name
        // convention (fd_topo.c's fd_topo_join_workspace) — even though
        // Tickoni creates it via its own normal-page wkspNewNamed rather
        // than fd_topo_create_workspace (finding 3). fd_wksp_new_named
        // passes this name straight to fd_shmem_create_multi/fd_shmem_join
        // with no prefix/suffix of its own, so both sides resolve to the
        // same named region as long as the string matches.
        var workspace_name_z_buf: [rt.topo_build.concrete_workspace_name_cap]u8 = undefined;
        const workspace_name_z = try rt.topo_build.concreteWorkspaceName(&workspace_name_z_buf, workspace_name_slice);
        // Best-effort cleanup of a stale workspace left behind by a prior
        // crashed or killed supervisor; fd_wksp_new_named uses O_EXCL and
        // would otherwise fail closed forever on the same run_dir/name.
        if (c_abi.wksp.wkspExistsNamed(workspace_name_z)) {
            _ = c_abi.wksp.wkspDeleteNamed(workspace_name_z);
        }

        // Size the real allocation off fd_topob_finish's computed
        // footprint/part_max instead of a hand-picked constant, plus a
        // little headroom.
        const footprint = c_abi.topob.topoWkspFootprint(built_topo.topo, built_topo.wksp_idx);
        const page_cnt = footprint / c_abi.wksp.shmem_normal_page_sz + 16;
        var sub_page_cnt = [_]usize{page_cnt};
        var sub_cpu_idx = [_]usize{0};
        const part_max = c_abi.topob.topoWkspPartMax(built_topo.topo, built_topo.wksp_idx);
        const rc = c_abi.wksp.wkspNewNamed(workspace_name_z, c_abi.wksp.shmem_normal_page_sz, 1, &sub_page_cnt, &sub_cpu_idx, 0o600, 1, part_max);
        if (rc != 0) return error.WkspCreateFailed;
        const wksp = c_abi.wksp.wkspAttach(workspace_name_z) orelse return error.WkspAttachFailed;
        errdefer _ = c_abi.wksp.wkspDetach(wksp);

        // Inject the attached workspace into the topology and instantiate
        // every object's content (mcache/dcache/fseq/metrics/cnc — "tile"
        // has no .new) via the same fd_topob callback array used to
        // compute the layout above.
        c_abi.topob.topoWkspSetPtr(built_topo.topo, built_topo.wksp_idx, wksp);
        c_abi.topob.topoWkspNew(built_topo.topo, built_topo.wksp_idx);

        const state = try self.allocator.create(ProcessState);
        state.* = .{
            .wksp = wksp,
            .built_topo = built_topo,
            .workspace_name = try self.allocator.dupe(u8, workspace_name_slice),
            .run_dir = try self.allocator.dupe(u8, config.run_dir),
            .cnc_gaddrs = std.mem.zeroes([8]usize),
            .cncs = std.mem.zeroes([8]?*c_abi.cnc.Cnc),
            .children = std.mem.zeroes([8]?std.process.Child),
            .heartbeat_stale_after_ns = resolvedHeartbeatStaleAfterNs(config),
            .stop_grace_ns = resolvedStopGraceNs(config),
            .placement_report = placement_report,
        };
        built_topo_owned_by_state = true;
        self.process_state = state;
        boot_needs_halt = false;
        errdefer {
            state.deinit(io, self.allocator);
            self.allocator.destroy(state);
            self.process_state = null;
        }

        // Resolve every tile's cnc content (created above by
        // topoWkspNew's cnc .new callback) into the gaddr-based form
        // LaunchSpec/tile_process.zig already consume, and join it
        // parent-side so stopProcess can signal halt. Only how these
        // objects get created changed (fd_topob instead of a hand-rolled
        // wkspAlloc); how children join them (LaunchSpec's gaddr fields)
        // is unchanged.
        for (self.topo.tiles, 0..) |_, i| {
            const laddr = c_abi.topob.topoObjLaddr(built_topo.topo, built_topo.cnc_obj_id[i]);
            state.cnc_gaddrs[i] = c_abi.wksp.wkspGaddr(wksp, laddr);
            state.cncs[i] = c_abi.cnc.cncJoin(laddr) orelse return error.CncJoinFailed;
        }

        // Resolve every channel's mcache/dcache/fseq (created above by
        // topoWkspNew's mcache/dcache/fseq .new callbacks) into the same
        // gaddr-based LinkHandles shape rt.link.create used to build by
        // hand.
        var link_handles_buf: [8]rt.link.LinkHandles = undefined;
        std.debug.assert(self.topo.channels.len <= link_handles_buf.len);
        const link_handles = link_handles_buf[0..self.topo.channels.len];
        for (self.topo.channels, 0..) |ch, i| {
            const ids = built_topo.link_obj_id[i];
            link_handles[i] = .{
                .mcache_gaddr = c_abi.wksp.wkspGaddr(wksp, c_abi.topob.topoObjLaddr(built_topo.topo, ids.mcache_obj_id)),
                .dcache_gaddr = c_abi.wksp.wkspGaddr(wksp, c_abi.topob.topoObjLaddr(built_topo.topo, ids.dcache_obj_id)),
                .fseq_gaddr = c_abi.wksp.wkspGaddr(wksp, c_abi.topob.topoObjLaddr(built_topo.topo, ids.fseq_obj_id)),
                .depth = ch.depth,
                .mtu = ch.mtu,
            };
        }

        var self_exe_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const self_exe_path = config.tile_exe_path orelse try util.process.selfExePath(&self_exe_path_buf);

        // Payment-pipeline test config is identical for every tile in the
        // run, so it's written once here rather than duplicated into each
        // tile's own LaunchSpec (v2.14.S8.T2: keeps that generic bootstrap
        // record free of payment-pipeline-specific fields). Tile processes
        // read it back via tile_registry.zig's loadProcessConfig, which
        // derives this same path from their LaunchSpec's shmemPath().
        const payment_config_path = try std.fmt.allocPrint(self.allocator, "{s}/payment_pipeline.config", .{config.run_dir});
        defer self.allocator.free(payment_config_path);
        try tiles_mod.process.writeProcessConfig(.{
            .pipeline = .{
                .event_count = config.event_count,
                .policy_limit_cents = config.policy_limit_cents,
                .inject_duplicate = config.inject_duplicate,
                .inject_malformed = config.inject_malformed,
            },
            .stuck_tile = if (config.stuck_tile_idx) |idx| .{
                .tile_idx = idx,
                .after_messages = config.stuck_after_messages,
            } else null,
        }, io, std.Io.Dir.cwd(), payment_config_path);

        // v2.14.S8.T4: every self-exec'd child rebuilds this same topology
        // (topo_build.build) to get a real fd_topo_t to hand to
        // fd_topo_run_tile — it needs the exact Topology value this run
        // used (e.g. a test's custom CPU placement), not a hardcoded
        // default, so it's written once here alongside the payment
        // config (see topology_spec.zig's module doc, "finding 5").
        const topology_spec_path = try std.fmt.allocPrint(self.allocator, "{s}/topology.spec", .{config.run_dir});
        defer self.allocator.free(topology_spec_path);
        const topology_spec = try rt.topology_spec.TopologySpec.fromTopology(self.topo);
        try topology_spec.writeToFile(io, std.Io.Dir.cwd(), topology_spec_path);

        for (self.handles, 0..) |*h, i| {
            const tile = self.topo.tiles[i];

            const spec = try rt.launch_spec.LaunchSpec.init(.{
                .tile_idx = @intCast(i),
                .tile_id = tile.id,
                .cpu_placement = tile.cpu_placement,
                .workspace_name = self.topo.channels[0].workspace_name,
                .cnc_gaddr = state.cnc_gaddrs[i],
                .shmem_path = config.run_dir,
                .heartbeat_interval_ns = config.heartbeat_interval_ns,
                .crash_after_heartbeats = config.crash_after_heartbeats[i],
                .channels = self.topo.channels,
                .link_handles = link_handles,
            });
            const spec_path = try std.fmt.allocPrint(self.allocator, "{s}/tile_{d}.spec", .{ config.run_dir, i });
            defer self.allocator.free(spec_path);
            try spec.writeToFile(io, std.Io.Dir.cwd(), spec_path);

            // Minimal explicit child environment: the tile reads its
            // shmem path from the launch spec via --shmem-path (see
            // runtime/boot.zig), not from an inherited environment,
            // matching the least-privilege posture used elsewhere in the
            // runtime (no inherited PATH, secrets, or parent env state).
            var env = std.process.Environ.Map.init(self.allocator);
            defer env.deinit();

            var argv_buf: [4][]const u8 = undefined;
            var argv_count: usize = 3;
            argv_buf[0] = self_exe_path;
            argv_buf[1] = "__tile-run";
            argv_buf[2] = spec_path;
            if (config.verbose) {
                argv_buf[3] = "--verbose";
                argv_count = 4;
            }
            const child = try std.process.spawn(io, .{
                .argv = argv_buf[0..argv_count],
                .environ_map = &env,
            });

            h.pid = child.id;
            h.cpu_placement = tile.cpu_placement;
            h.state = .running;
            state.children[i] = child;

            if (@import("builtin").os.tag == .linux) {
                switch (tile.cpu_placement) {
                    .exclusive, .shared => |cpu| {
                        var cpu_set: util.cpu.CpuSet = undefined;
                        util.cpu.zero(&cpu_set);
                        util.cpu.set(&cpu_set, cpu);
                        try util.cpu.setAffinity(@intCast(child.id.?), &cpu_set);
                    },
                    .floating => {},
                }
            }
        }
    }

    fn updateHandleForOutcome(self: *Supervisor, i: usize, outcome: util.process_api.ProcessOutcome) void {
        switch (outcome) {
            .exited_ok => {
                // A clean exit after stopProcess() should be treated as a
                // normal stop even if refreshProcessHealth() transiently
                // marked the tile stale before the halt/reap completed.
                self.handles[i].state = .stopped;
                self.handles[i].crashed_because = .none;
            },
            .exited_code => |code| {
                if (self.handles[i].state == .stale) {
                    self.handles[i].crashed_because = .stale;
                } else {
                    self.handles[i].state = .crashed;
                    self.handles[i].exit_code = code;
                    self.handles[i].crashed_because = .exit_code;
                }
            },
            .crashed, .force_terminated => {
                if (self.handles[i].state == .stale) {
                    self.handles[i].crashed_because = .stale;
                } else {
                    self.handles[i].state = .crashed;
                    self.handles[i].crashed_because = .signal;
                }
            },
            .stopped, .unknown => {
                if (self.handles[i].state == .stale) {
                    self.handles[i].crashed_because = .stale;
                } else {
                    self.handles[i].state = .crashed;
                    self.handles[i].crashed_because = .exit_code;
                }
            },
        }
    }

    fn reapExitedChildrenNoHang(self: *Supervisor) void {
        const state = self.process_state orelse return;
        for (&state.children, 0..) |*maybe_child, i| {
            var child = maybe_child.* orelse continue;
            switch (util.process_api.tryReapNoHang(&child)) {
                .running => {},
                .reaped => |term| {
                    self.updateHandleForOutcome(i, util.process_api.outcomeFromTerm(term, false));
                    maybe_child.* = null;
                },
                .detached => {
                    maybe_child.* = null;
                },
                .failed => {},
            }
        }
    }

    pub fn waitProcess(self: *Supervisor, io: std.Io, forced_termination: ?[]const bool) void {
        _ = io;
        const log = logger.get();
        log.enter("supervisor", "waitProcess") catch {};
        defer log.exit("supervisor", "waitProcess") catch {};
        const state = self.process_state orelse return;

        // Bounded wait loop: tryReapNoHang with a timeout so a stuck child
        // never blocks indefinitely.  If a tile has already been SIGKILL'd
        // the kernel may need a moment to reap the zombie; if it never exits
        // we escalate to SIGKILL ourselves.
        const deadline = util.process.monotonicNanos() + @as(i64, @intCast(state.stop_grace_ns));
        while (util.process.monotonicNanos() < deadline) {
            var any_remaining = false;
            for (&state.children, 0..) |*maybe_child, i| {
                var child = maybe_child.* orelse continue;
                switch (util.process_api.tryReapNoHang(&child)) {
                    .running => {
                        any_remaining = true;
                    },
                    .reaped => |term| {
                        const was_forced = if (forced_termination) |f| f[i] else false;
                        self.updateHandleForOutcome(i, util.process_api.outcomeFromTerm(term, was_forced));
                        maybe_child.* = null;
                    },
                    .detached => {
                        maybe_child.* = null;
                    },
                    .failed => {},
                }
            }
            if (!any_remaining) break;
            util.process.sleepNanos(5 * std.time.ns_per_ms);
        }

        // Force-kill any children that still have not exited after the grace
        // period, then reap them (they should exit instantly).
        {
            var still_forced: [8]bool = undefined;
            var fi: usize = 0;
            while (fi < still_forced.len) : (fi += 1) still_forced[fi] = false;
            for (&state.children, 0..) |*maybe_child, i| {
                if (maybe_child.* == null) continue;
                const child = maybe_child.*.?;
                util.process_api.forceTerminate(child.id.?);
                still_forced[i] = true;
            }
            // Give the kernel a moment to reap the force-killed zombies.
            util.process.sleepNanos(5 * std.time.ns_per_ms);
            for (&state.children, 0..) |*maybe_child, i| {
                var child = maybe_child.* orelse continue;
                switch (util.process_api.tryReapNoHang(&child)) {
                    .reaped => |term| {
                        self.updateHandleForOutcome(i, util.process_api.outcomeFromTerm(term, true));
                        maybe_child.* = null;
                    },
                    .detached => {
                        maybe_child.* = null;
                    },
                    .running => {},
                    .failed => {},
                }
            }
        }
    }

    pub fn refreshProcessHealth(self: *Supervisor) void {
        const log = logger.get();
        log.enter("supervisor", "refreshProcessHealth") catch {};
        defer log.exit("supervisor", "refreshProcessHealth") catch {};
        const state = self.process_state orelse return;
        const now = util.process.monotonicNanos();
        if (now <= 0) return;
        const now_ns: u64 = @intCast(now);
        for (state.cncs, 0..) |maybe_cnc, i| {
            const h = &self.handles[i];
            if (h.state != .starting and h.state != .running) continue;
            const cnc = maybe_cnc orelse continue;
            const heartbeat = c_abi.cnc.heartbeatQuery(cnc);
            if (heartbeat <= 0) continue;
            const heartbeat_ns: u64 = @intCast(heartbeat);
            if (now_ns > heartbeat_ns and now_ns - heartbeat_ns > state.heartbeat_stale_after_ns) {
                h.state = .stale;
                h.crashed_because = .stale;
            }
        }
    }

    /// Process-mode equivalent of tiles_mod.MetricSnapshot: every tile
    /// publishes its own local counters into its cnc app-region (see
    /// runtime/cnc_counters.zig's appCounter{Read,Write} and
    /// src/tickoni/tiles/payment_pipeline/process.zig's per-tile counter
    /// layout); this reads them back across the process boundary. Must be called
    /// before stopProcess, which leaves every cnc join and detaches the
    /// workspace.
    pub const ProcessMetricSnapshot = struct {
        produced: u64 = 0,
        normalized: u64 = 0,
        invalid: u64 = 0,
        duplicates: u64 = 0,
        allowed: u64 = 0,
        denied: u64 = 0,
        audited: u64 = 0,
    };

    /// v2.14.S1.T14 visibility: the CPU placement layout validated at
    /// start time (exclusive/shared/floating counts and whether the
    /// layout is shared-core). Null when no process-mode pipeline has
    /// been started.
    pub fn processPlacementReport(self: *const Supervisor) ?rt.cpu_placement.PlacementReport {
        const state = self.process_state orelse return null;
        return state.placement_report;
    }

    pub fn snapshotProcessMetrics(self: *const Supervisor) ProcessMetricSnapshot {
        const state = self.process_state orelse return .{};
        var snap = ProcessMetricSnapshot{};
        for (self.topo.tiles, 0..) |tile, i| {
            const cnc = state.cncs[i] orelse continue;
            const entry = tile_registry.findById(tile.id) orelse continue;
            for (entry.counters) |c| {
                const v = rt.cnc_counters.appCounterRead(cnc, c.idx);
                switch (c.field) {
                    .produced => snap.produced = v,
                    .normalized => snap.normalized = v,
                    .invalid => snap.invalid = v,
                    .duplicates => snap.duplicates = v,
                    .allowed => snap.allowed = v,
                    .denied => snap.denied = v,
                    .audited => snap.audited = v,
                }
            }
        }
        return snap;
    }

    /// Signals every tile to halt via its cnc (crash-only shutdown, not a
    /// POSIX signal — matches fd_cnc's own command/control model), waits
    /// for exit, and fully tears down the shared workspace. Sibling tiles
    /// are not touched by one tile's crash; this only requests a clean
    /// stop of tiles that are still running.
    pub fn stopProcess(self: *Supervisor, io: std.Io) void {
        const log = logger.get();
        log.enter("supervisor", "stopProcess") catch {};
        defer log.exit("supervisor", "stopProcess") catch {};
        const state = self.process_state orelse return;
        self.refreshProcessHealth();
        const stale_before_stop = blk: {
            var snapshot: [8]bool = std.mem.zeroes([8]bool);
            for (self.handles, 0..) |h, i| snapshot[i] = h.state == .stale;
            break :blk snapshot;
        };
        const had_stale_before_stop = for (stale_before_stop) |was_stale| {
            if (was_stale) break true;
        } else false;
        for (state.cncs) |maybe_cnc| {
            if (maybe_cnc) |cnc| c_abi.cnc.signal(cnc, c_abi.cnc.signal_halt);
        }

        if (had_stale_before_stop) {
            const grace_deadline = util.process.monotonicNanos() + @as(i64, @intCast(state.stop_grace_ns));
            while (util.process.monotonicNanos() < grace_deadline) {
                self.reapExitedChildrenNoHang();
                util.process.sleepNanos(5 * std.time.ns_per_ms);
            }
            self.reapExitedChildrenNoHang();
        }

        var forced_termination: [8]bool = undefined;
        var ci: usize = 0;
        while (ci < forced_termination.len) : (ci += 1) forced_termination[ci] = false;
        for (stale_before_stop, 0..) |was_stale, i| {
            if (!was_stale) continue;
            const maybe_child = &state.children[i];
            const child = maybe_child.* orelse continue;
            const pid = child.id orelse continue;
            util.process_api.forceTerminate(pid);
            forced_termination[i] = true;
        }

        self.waitProcess(io, &forced_termination);
        state.deinit(io, self.allocator);
        self.allocator.destroy(state);
        self.process_state = null;
    }

    /// Join all tile threads without requesting early shutdown.  The Phase 0
    /// pipeline closes links as producers finish, so this waits for a complete
    /// deterministic run unless a tile has already requested stop.
    pub fn wait(self: *Supervisor) void {
        self.joinThreads();
    }

    /// Signal all tiles to stop and join their threads.
    pub fn stop(self: *Supervisor) void {
        if (self.pipeline) |state| {
            state.requestStop();
        }
        self.joinThreads();
        if (self.pipeline) |state| {
            state.deinit();
            self.allocator.destroy(state);
            self.pipeline = null;
        }
    }

    fn joinThreads(self: *Supervisor) void {
        for (self.handles) |*h| {
            if (h.thread) |thread| {
                thread.join();
                h.thread = null;
                // Read after join so the release-store in the tile thread is visible.
                const crashed_tile = if (self.pipeline) |state| state.crashed_tile.load(.acquire) else -1;
                if (crashed_tile >= 0 and @as(i32, @intCast(h.tile_idx)) == crashed_tile) {
                    h.state = .crashed;
                    h.exit_code = 1;
                    h.crashed_because = .exit_code;
                } else {
                    h.state = .stopped;
                }
            }
        }
    }

    /// Returns the current handle slice — a read-only snapshot of tile states.
    pub fn monitor(self: *const Supervisor) []const TileHandle {
        return self.handles;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "Supervisor initialises all handles as stopped" {
    const topo = topologies.paymentPipeline();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    for (sup.monitor()) |h| {
        try std.testing.expectEqual(TileState.stopped, h.state);
    }
}

test "Supervisor init fails closed on a structural CPU placement conflict, even in thread mode" {
    const base = topologies.paymentPipeline();
    var conflicting_tiles: [8]rt.topology.TileDescriptor = base.tiles[0..8].*;
    conflicting_tiles[0].cpu_placement = .{ .exclusive = 0 };
    conflicting_tiles[1].cpu_placement = .{ .exclusive = 0 };
    const topo = rt.topology.Topology{ .tiles = &conflicting_tiles, .channels = base.channels };

    try std.testing.expectError(error.CpuPlacementConflict, Supervisor.init(std.testing.allocator, topo));
}

test "Supervisor starts and stops Phase 0 pipeline without crashes" {
    const topo = topologies.paymentPipeline();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    try sup.startPaymentPipeline(.{ .event_count = 16, .queue_depth = 4 });
    sup.wait();

    const state = sup.pipeline.?;
    const metrics = state.snapshotMetrics();
    try std.testing.expectEqual(@as(u64, 16), metrics.produced);
    try std.testing.expectEqual(@as(u64, 16), metrics.audited);
    try std.testing.expectEqual(@as(u64, 1), metrics.duplicates);
    try std.testing.expectEqual(@as(u64, 1), metrics.denied);
    try std.testing.expect(metrics.max_queue_depth <= 4);
    try std.testing.expectEqual(@as(u64, 5), metrics.max_latency_hops);
    try std.testing.expect(state.replay_checked.load(.seq_cst));
    try std.testing.expect(state.replay_match.load(.seq_cst));
    try std.testing.expect(state.external_effects_disabled.load(.seq_cst));

    sup.stop();

    for (sup.monitor()) |h| {
        try std.testing.expectEqual(TileState.stopped, h.state);
        try std.testing.expect(!h.isAlive());
    }
}

test "Supervisor monitor returns correct tile count" {
    const topo = topologies.paymentPipeline();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    try std.testing.expectEqual(topo.tiles.len, sup.monitor().len);
}

test "Supervisor pipeline state is nil after stop" {
    const topo = topologies.paymentPipeline();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    try sup.startPaymentPipeline(.{ .event_count = 50, .queue_depth = 8 });
    sup.wait();
    sup.stop();
    try std.testing.expect(sup.pipeline == null);
}

test "Supervisor marks tkings crashed on sandbox failure" {
    const topo = topologies.paymentPipeline();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    try sup.startPaymentPipeline(.{ .event_count = 20, .queue_depth = 4, .sandbox_fail_at = 2 });
    sup.wait();
    sup.stop();
    try std.testing.expectEqual(TileState.crashed, sup.monitor()[0].state);
    try std.testing.expectEqual(@as(u8, 1), sup.monitor()[0].exit_code);
    try std.testing.expectEqual(CrashReason.exit_code, sup.monitor()[0].crashed_because);
}
