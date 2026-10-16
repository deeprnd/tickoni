/// Tickoni supervisor: owns tile handles for one topology, starts all Phase 0
/// tiles as supervisor-managed OS processes over Tango shared memory (v2.14),
/// and provides start/stop/monitor.
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
    /// Explicit workspace name override for the Tango shared region.
    /// When null, the supervisor derives a PID-suffixed workspace name
    /// from the topology's channels (default).  Tests that need a
    /// predictable workspace name pass an override here.
    workspace_name: ?[]const u8 = null,
    /// UDP port on which the metric tile listens for HTTP/JSON metric
    /// queries.  Tests call util.nextMetricPort() so parallel runs don't
    /// collide; in production it defaults to the compiled-in default.
    metric_port: u16 = 0,
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
                _ = util.process_api.forceTerminate(pid);
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

pub const Supervisor = struct {
    allocator: std.mem.Allocator,
    topo: Topology,
    handles: []TileHandle,
    /// Non-null while a v2.14 process-mode pipeline is running.
    process_state: ?*ProcessState = null,

    /// Runs topo.validate()'s structural checks (duplicate tile ids, channel
    /// depth/MTU shape, exclusive/shared CPU placement conflicts) once, at the
    /// one entrypoint — so a caller cannot reach startPaymentPipelineProcess
    /// without the check that cpu_placement.validate() already ran.
    /// Host-aware checks (is a declared CPU id actually available on this
    /// host) still belong to startPaymentPipelineProcess: process mode pins
    /// CPUs, so it needs an affinity mask to check against.
    pub fn init(allocator: std.mem.Allocator, topo: Topology) !Supervisor {
        const log = logger.get();
        log.enter("supervisor", "init");
        defer log.exit("supervisor", "init");
        try topo.validate();
        try tile_registry.validate(topo);
        const handles = try allocator.alloc(TileHandle, topo.tiles.len);
        for (handles, 0..) |*h, i| h.* = TileHandle.init(@intCast(i));
        return .{
            .allocator = allocator,
            .topo = topo,
            .handles = handles,
        };
    }

    /// Callers that used startPaymentPipelineProcess must call stopProcess
    /// before deinit; this assert makes a forgotten teardown loud instead of
    /// leaking child processes and shared memory.
    pub fn deinit(self: *Supervisor) void {
        const log = logger.get();
        log.enter("supervisor", "deinit");
        defer log.exit("supervisor", "deinit");
        std.debug.assert(self.process_state == null);
        self.allocator.free(self.handles);
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

        try rt.boot.bootWithSyntheticArgv(config.run_dir, "");
        var boot_needs_halt = true;
        errdefer if (boot_needs_halt) c_abi.boot.halt();

        // Generate a PID-suffixed workspace name so parallel test runs
        // (each forked as a separate OS process) do not collide on the
        // same Tango shared-memory region.  Linux PIDs fit in 6 digits;
        // macOS uses 32-bit PIDs but in practice stay under 6 digits.
        // The suffix is appended as a dash-delimited token so the base
        // name is still human-readable when debugging.
        // When the caller overrides workspace_name (tests that need a
        // predictable name), skip the PID suffix derivation.
        const base_workspace_name = if (config.workspace_name) |wn| wn else blk: {
            const raw = self.topo.channels[0].workspace_name.slice();
            if (raw.len == 0) return error.MissingWorkspaceName;
            for (self.topo.channels) |ch| {
                if (ch.backing != .tango_shm) return error.ProcessModeRequiresTangoShm;
                if (!std.mem.eql(u8, ch.workspace_name.slice(), raw)) return error.MultipleWorkspacesNotSupported;
            }
            break :blk raw;
        };

        // Create a copy of the channels array with PID-suffixed workspace
        // names.  Child tiles read topology.spec and tile_N.spec; they must
        // see the same workspace name that the parent uses to create the
        // shared region, otherwise the child would join a different region
        // (or collide with another test's region).
        const my_pid = c_abi.sandbox.getpid();
        var pid_buf: [8]u8 = undefined;
        const pid_str = std.fmt.bufPrint(&pid_buf, "{d}", .{my_pid}) catch "0";
        var full_wname_buf: [64]u8 = undefined;
        const full_workspace_name = if (config.workspace_name) |_| base_workspace_name else try std.fmt.bufPrint(&full_wname_buf, "{s}-{s}", .{ base_workspace_name, pid_str });

        // Copy channels and update workspace_name for every tango_shm link.
        const channels_copy = try self.allocator.alloc(rt.link.Channel, self.topo.channels.len);
        defer self.allocator.free(channels_copy);
        for (self.topo.channels, 0..) |ch, i| {
            var copy = ch;
            if (ch.backing == .tango_shm) {
                copy.workspace_name = try rt.link.WorkspaceName.parse(full_workspace_name);
            }
            channels_copy[i] = copy;
        }

        const modified_topo = Topology{
            .tiles = self.topo.tiles,
            .channels = channels_copy,
        };

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
        var built_topo = try rt.topo_build.build(self.allocator, modified_topo, full_workspace_name);
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
        const workspace_name_z = try rt.topo_build.concreteWorkspaceName(&workspace_name_z_buf, full_workspace_name);
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
            .workspace_name = try self.allocator.dupe(u8, full_workspace_name),
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
        const topology_spec = try rt.topology_spec.TopologySpec.fromTopology(modified_topo, 0);
        try topology_spec.writeToFile(io, std.Io.Dir.cwd(), topology_spec_path);

        for (self.handles, 0..) |*h, i| {
            const tile = self.topo.tiles[i];

            const spec = try rt.launch_spec.LaunchSpec.init(.{
                .tile_idx = @intCast(i),
                .tile_id = tile.id,
                .cpu_placement = tile.cpu_placement,
                .workspace_name = channels_copy[0].workspace_name,
                .cnc_gaddr = state.cnc_gaddrs[i],
                .shmem_path = config.run_dir,
                .heartbeat_interval_ns = config.heartbeat_interval_ns,
                .crash_after_heartbeats = config.crash_after_heartbeats[i],
                .channels = channels_copy,
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
            .clean_stop => {
                // A clean exit after stopProcess() should be treated as a
                // normal stop even if refreshProcessHealth() transiently
                // marked the tile stale before the halt/reap completed.
                self.handles[i].state = .stopped;
                self.handles[i].crashed_because = .none;
            },
            .intentional_termination => {
                if (self.handles[i].state == .stale) {
                    self.handles[i].crashed_because = .stale;
                } else {
                    self.handles[i].state = .stopped;
                    self.handles[i].crashed_because = .none;
                }
            },
            .crash_exit => |code| {
                if (self.handles[i].state == .stale) {
                    self.handles[i].crashed_because = .stale;
                } else {
                    self.handles[i].state = .crashed;
                    self.handles[i].exit_code = code;
                    self.handles[i].crashed_because = .exit_code;
                }
            },
            .crash_signal => |signal| {
                if (self.handles[i].state == .stale) {
                    // Tile was stale when stopProcess() began — force termination
                    // is a consequence of the shutdown sequence, not a real crash.
                    _ = signal;
                    self.handles[i].state = .stopped;
                    self.handles[i].crashed_because = .none;
                } else {
                    self.handles[i].state = .crashed;
                    self.handles[i].crashed_because = .signal;
                }
            },
            .nonterminal_stop => |signal| {
                if (self.handles[i].state == .stale) {
                    self.handles[i].crashed_because = .stale;
                } else {
                    self.handles[i].state = .crashed;
                    self.handles[i].exit_code = signal;
                    self.handles[i].crashed_because = .exit_code;
                }
            },
        }
    }

pub fn reapExitedChildrenNoHang(self: *Supervisor) void {
        const state = self.process_state orelse return;
        for (&state.children, 0..) |*maybe_child, i| {
            var child = maybe_child.* orelse continue;
            switch (util.process_api.tryReapNoHang(&child)) {
                .running => {},
                .observation => |obs| {
                    self.updateHandleForOutcome(i, util.process_api.classify(obs, null));
                    maybe_child.* = null;
                },
                .no_child => {
                    // Child already reaped or never existed — treat as clean stop.
                    self.handles[i].state = .stopped;
                    self.handles[i].crashed_because = .none;
                    maybe_child.* = null;
                },
                .failed => {},
            }
        }
    }

    pub fn waitProcess(self: *Supervisor, io: std.Io, forced_termination: ?[]const bool) void {
        _ = io;
        const log = logger.get();
        log.enter("supervisor", "waitProcess");
        defer log.exit("supervisor", "waitProcess");
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
                    .observation => |obs| {
                        const was_forced = if (forced_termination) |f| f[i] else false;
                        self.updateHandleForOutcome(i, util.process_api.classify(obs, if (was_forced) .{ .signal = 9 } else null));
                        maybe_child.* = null;
                    },
                    .no_child => {
                        // Child already reaped — treat as clean stop.
                        self.handles[i].state = .stopped;
                        self.handles[i].crashed_because = .none;
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
                _ = util.process_api.forceTerminate(child.id.?);
                still_forced[i] = true;
            }
            // Give the kernel a moment to reap the force-killed zombies.
            util.process.sleepNanos(5 * std.time.ns_per_ms);
            for (&state.children, 0..) |*maybe_child, i| {
                var child = maybe_child.* orelse continue;
                switch (util.process_api.tryReapNoHang(&child)) {
                    .observation => |obs| {
                        self.updateHandleForOutcome(i, util.process_api.classify(obs, .{ .signal = 9 }));
                        maybe_child.* = null;
                    },
                    .no_child => {
                        // Child already reaped — treat as intentionally terminated.
                        self.handles[i].state = .stopped;
                        self.handles[i].crashed_because = .none;
                        maybe_child.* = null;
                    },
                    .running => {},
                    .failed => {},
                }
            }
        }

        // Any handle still in .running after force-kill (process survived or
        // reap didn't fire) must be marked stopped so teardown doesn't leave
        // zombies in the handle table.
        for (self.handles) |*h| {
            if (h.state == .running) {
                h.state = .stopped;
                h.crashed_because = .none;
            }
        }
    }

    pub fn refreshProcessHealth(self: *Supervisor) void {
        const log = logger.get();
        log.enter("supervisor", "refreshProcessHealth");
        defer log.exit("supervisor", "refreshProcessHealth");
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

    /// Returns true when any tile has been classified as crashed during
    /// a running process-mode pipeline. Useful for early crash detection
    /// before calling stopProcess.
    pub fn hasCrashed(self: *const Supervisor) bool {
        for (self.handles) |h| {
            if (h.state == .crashed) return true;
        }
        return false;
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
        replay_checked: u64 = 0,
        replay_match: u64 = 0,
        metric_snapshots: u64 = 0,
        metric_backpressure_waits: u64 = 0,
        diag_crashed_tile: u64 = 0,
        diag_sandbox_failures: u64 = 0,
        metric_boot_timestamp: u64 = 0,
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
                    .replay_checked => snap.replay_checked = v,
                    .replay_match => snap.replay_match = v,
                    .metric_snapshots => snap.metric_snapshots = v,
                    .metric_backpressure_waits => snap.metric_backpressure_waits = v,
                    .diag_crashed_tile => snap.diag_crashed_tile = v,
                    .diag_sandbox_failures => snap.diag_sandbox_failures = v,
                    .metric_boot_timestamp => snap.metric_boot_timestamp = v,
                }
            }
        }
        return snap;
    }

    /// Read metrics for a single tile in process-mode.
    pub fn snapshotProcessMetricsForTile(self: *const Supervisor, tile_idx: usize) !ProcessMetricSnapshot {
        const state = self.process_state orelse return error.NoProcessState;
        const cnc = state.cncs[tile_idx] orelse return error.CncNotFound;
        const tile = self.topo.tiles[tile_idx];
        const entry = tile_registry.findById(tile.id) orelse return error.TileNotFound;
        var snap = ProcessMetricSnapshot{};
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
                .replay_checked => snap.replay_checked = v,
                .replay_match => snap.replay_match = v,
                .metric_snapshots => snap.metric_snapshots = v,
                .metric_backpressure_waits => snap.metric_backpressure_waits = v,
                .diag_crashed_tile => snap.diag_crashed_tile = v,
                .diag_sandbox_failures => snap.diag_sandbox_failures = v,
                .metric_boot_timestamp => snap.metric_boot_timestamp = v,
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
        log.enter("supervisor", "stopProcess");
        defer log.exit("supervisor", "stopProcess");
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
            _ = util.process_api.forceTerminate(pid);
            forced_termination[i] = true;
        }

        self.waitProcess(io, &forced_termination);
        // Treat non-crashed tiles as stopped after stopProcess — the shutdown
        // sequence is intentional, so downstream failures (e.g. a blocked
        // upstream causing a SIGSEGV in a consumer) are a consequence of the
        // shutdown, not a real crash.  Tiles that already transitioned to
        // .crashed before stopProcess ran retain their crash attribution.
        for (self.handles) |*h| {
            if (h.state != .crashed) {
                h.state = .stopped;
                h.crashed_because = .none;
            }
        }
        state.deinit(io, self.allocator);
        self.allocator.destroy(state);
        self.process_state = null;
    }

    /// Join all tile processes. Called during teardown when process mode was
    /// never started (e.g. deinit after failed init). No-op in practice since
    /// process state is the only execution mode.
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

test "Supervisor init fails closed on a structural CPU placement conflict" {
    const base = topologies.paymentPipeline();
    var conflicting_tiles: [8]rt.topology.TileDescriptor = base.tiles[0..8].*;
    conflicting_tiles[0].cpu_placement = .{ .exclusive = 0 };
    conflicting_tiles[1].cpu_placement = .{ .exclusive = 0 };
    const topo = rt.topology.Topology{ .tiles = &conflicting_tiles, .channels = base.channels };

    try std.testing.expectError(error.CpuPlacementConflict, Supervisor.init(std.testing.allocator, topo));
}

test "Supervisor monitor returns correct tile count" {
    const topo = topologies.paymentPipeline();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    try std.testing.expectEqual(topo.tiles.len, sup.monitor().len);
}

test "Supervisor starts and stops Phase 0 pipeline without crashes (process mode)" {
    const topo = topologies.paymentPipelineProcess();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    const run_dir = "/tmp/tickoni-test-supervisor";
    const event_count: u64 = 16;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    });

    // Poll for completion instead of fixed sleep: process-mode tiles keep
    // heartbeating after finishing their bounded work until asked to halt.
    const max_polls: u32 = 400; // 2s bound at 5ms per poll
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }

    const metrics = sup.snapshotProcessMetrics();
    try std.testing.expectEqual(@as(u64, 16), metrics.produced);
    try std.testing.expectEqual(@as(u64, 16), metrics.normalized);
    try std.testing.expectEqual(@as(u64, 0), metrics.invalid);
    try std.testing.expectEqual(@as(u64, 1), metrics.duplicates);
    try std.testing.expectEqual(@as(u64, 1), metrics.denied);
    try std.testing.expectEqual(@as(u64, 15), metrics.allowed);
    try std.testing.expectEqual(@as(u64, 16), metrics.audited);

    sup.stopProcess(std.testing.io);

    for (sup.monitor()) |h| {
        try std.testing.expectEqual(TileState.stopped, h.state);
    }
}

test "Supervisor process_state is nil after stop (process mode)" {
    const topo = topologies.paymentPipelineProcess();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    const run_dir = "/tmp/tickoni-test-supervisor-nil";
    const event_count: u64 = 50;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    });

    const max_polls: u32 = 400;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }

    sup.stopProcess(std.testing.io);
    try std.testing.expect(sup.process_state == null);
}

test "Supervisor marks tkings crashed on tile failure (process mode)" {
    const topo = topologies.paymentPipelineProcess();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    const run_dir = "/tmp/tickoni-test-supervisor-crash";
    const event_count: u64 = 20;
    var crash_after: [8]u32 = std.mem.zeroes([8]u32);
    crash_after[0] = 1; // tkings crashes after 1 heartbeat
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .crash_after_heartbeats = crash_after,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    });

    // Wait for crash detection.
    const max_polls: u32 = 400;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.hasCrashed()) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }

    try std.testing.expectEqual(TileState.crashed, sup.monitor()[0].state);
    try std.testing.expectEqual(@as(u8, 1), sup.monitor()[0].exit_code);
    try std.testing.expectEqual(CrashReason.exit_code, sup.monitor()[0].crashed_because);

    sup.stopProcess(std.testing.io);
}
