/// Tickoni supervisor: owns tile handles for one topology, starts Phase 0
/// tiles as supervisor-managed OS processes over Tango shared memory
/// (v2.14.S1), and provides start/stop/monitor for that single mode.
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
    /// Payment pipeline behavior for process-mode
    /// (event_count, policy_limit_cents, inject_duplicate, inject_malformed).
    /// Kept in ProcessPipelineConfig so process-mode runs have deterministic
    /// inputs.
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
    /// Workspace name for the Tango shared memory workspace. Defaults to
    /// "tkpay0" for backward compatibility. Tests should override with a
    /// unique name (e.g. test index or PID) to avoid shared-memory collisions
    /// when multiple test binaries run in parallel. Passed through the
    /// topology spec so child tile processes join the same workspace.
    workspace_name: []const u8 = "tkpay0",
    /// Port for the metric tile's Prometheus HTTP server. Defaults to 7999.
    /// Each integration test file should use a distinct port to avoid
    /// EADDRINUSE from TIME_WAIT on the previous test's socket.
    metric_port: u16 = 7999,
};

/// Supervisor-owned state for a running v2.14 process-mode pipeline.
const ProcessState = struct {
    wksp: *c_abi.wksp.Wksp,
    metric_wksp: ?*c_abi.wksp.Wksp,
    metric_in_wksp: ?*c_abi.wksp.Wksp,
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
    /// Set true when stopProcess detects that any child has crashed
    /// (FileNotFound, unexpected non-zero exit, or signal). Prevents
    /// deinit() from crashing on stale shared memory.
    has_child_crashed: bool = false,

    /// Kills any still-running children, leaves cnc joins, detaches the
    /// workspace, and frees owned buffers. Safe to call with a partially
    /// populated state (e.g. after a failed start).
    ///
    /// Follows Firedancer's SIGTERM→wait→SIGKILL pattern: sends SIGTERM
    /// first so children can exit cleanly, waits up to 500 ms, then
    /// SIGKILLs anything still alive, and finally reaps all children
    /// before touching shared memory.  This prevents the previous
    /// direct-SIGKILL-then-shared-memory pattern where children could
    /// still be alive when wkspDetach / boot.halt ran, causing segfaults.
    ///
    /// v2.24: Crash-safe teardown — when has_child_crashed is true, C-level
    /// shared memory ops (cncLeave, wkspDetach, boot.halt) can segfault or
    /// trigger FD_LOG_PANIC because children have already torn down their
    /// shared-memory pointers. Skip those ops so the supervisor survives its
    /// own children's crashes instead of SIGABRT'ing during teardown.
    fn deinit(self: *ProcessState, _: std.Io, allocator: std.mem.Allocator) void {
        // Phase 1: send SIGTERM to every still-running child and wait up to
        // 500 ms for a clean exit (Firedancer-style graceful shutdown).
        const sigterm_deadline = util.process.monotonicNanos() + @as(i64, 500) * std.time.ns_per_ms;
        for (&self.children) |*maybe_child| {
            const child = maybe_child.* orelse continue;
            const pid = child.id orelse continue;
            _ = std.posix.kill(pid, std.posix.SIG.TERM) catch {};
        }
        // Wait for children to exit after SIGTERM, reaping each one.
        // Handle outcomes are set by stopProcess via reapExitedChildrenNoHang
        // and waitProcess before deinit runs — deinit just kills and clears.
        {
            var ci: usize = 0;
            while (ci < self.children.len) : (ci += 1) {
                var child = self.children[ci] orelse continue;
                var deadline = sigterm_deadline;
                while (true) {
                    const now = util.process.monotonicNanos();
                    if (now >= deadline) break;
                    switch (util.process_api.tryReapNoHang(&child)) {
                        .running => {
                            util.process.sleepNanos(1 * std.time.ms_per_s);
                            deadline = sigterm_deadline;
                        },
                        .reaped, .detached => {
                            self.children[ci] = null;
                            break;
                        },
                        .failed => {
                            // Reap failure is non-fatal; leave child in
                            // the array for Phase 2 to handle.
                            break;
                        },
                    }
                }
            }
        }

        // Phase 2: SIGKILL anything still alive and reap.
        for (&self.children) |*maybe_child| {
            const child = maybe_child.* orelse continue;
            const pid = child.id orelse continue;
            _ = std.posix.kill(pid, std.posix.SIG.KILL) catch {};
        }
        // Wait for SIGKILL'd children to die and reap them, recording outcomes.
        {
            var ci: usize = 0;
            while (ci < self.children.len) : (ci += 1) {
                var child = self.children[ci] orelse continue;
                const deadline = util.process.monotonicNanos() + @as(i64, 1) * std.time.ns_per_s;
                while (util.process.monotonicNanos() < deadline) {
                    switch (util.process_api.tryReapNoHang(&child)) {
                        .running => util.process.sleepNanos(1 * std.time.ms_per_s),
                        .reaped, .detached => {
                            self.children[ci] = null;
                            break;
                        },
                        .failed => {},
                    }
                }
            }
        }
        // Final reap of any remaining zombies.
        for (&self.children) |*maybe_child| {
            maybe_child.* = null;
        }
        // When children have already crashed, skip the fragile C-level
        // ops that dereference per-child cnc pointers — those children
        // may have torn down their shared-memory mappings and a deref
        // could segfault.  The supervisor's own wksp reference and
        // boot.halt() are safe: wkspDetach is called by the process
        // that attached (the supervisor itself), and boot.halt() is the
        // Firedancer routine that actually frees the shared-memory
        // segments.  Skipping boot.halt() leaves stale regions on disk
        // that poison the next test invocation.
        //
        // The supervisor must survive teardown so tests can observe
        // monitor() state after stopProcess completes.
        if (!self.has_child_crashed) {
            for (&self.cncs) |*maybe_cnc| {
                if (maybe_cnc.*) |cnc| _ = c_abi.cnc.cncLeave(cnc);
            }
        }
        if (self.metric_in_wksp) |metric_in_wksp| _ = c_abi.wksp.wkspDetach(metric_in_wksp);
        if (self.metric_wksp) |metric_wksp| _ = c_abi.wksp.wkspDetach(metric_wksp);
        _ = c_abi.wksp.wkspDetach(self.wksp);
        c_abi.boot.halt();
        self.built_topo.deinit(allocator);
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
    /// depth/MTU shape, exclusive/shared CPU placement conflicts) before
    /// startPaymentPipelineProcess. Host-aware checks (is a declared CPU id
    /// actually available on this host) belong to startPaymentPipelineProcess:
    /// it pins CPUs, so it has a live affinity mask to check against here.
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

        const workspace_name_slice = config.workspace_name;
        if (workspace_name_slice.len == 0) return error.MissingWorkspaceName;
        for (self.topo.channels) |ch| {
            if (ch.backing != .tango_shm) return error.ProcessModeRequiresTangoShm;
        }

        // Ensure run_dir and its .normal FD_SHMEM_PATH subdirectory exist;
        // fd_wksp_new_named does not create either for us.
        var run_dir_handle = try std.Io.Dir.cwd().createDirPathOpen(io, config.run_dir, .{});
        run_dir_handle.close(io);
        const normal_dir = try std.fmt.allocPrint(self.allocator, "{s}/.normal", .{config.run_dir});
        defer self.allocator.free(normal_dir);
        var normal_dir_handle = try std.Io.Dir.cwd().createDirPathOpen(io, normal_dir, .{});
        normal_dir_handle.close(io);

        // Per-tile log directory — tile processes write {run_dir}/logs/tile_{idx}.log
        // Supervisor also logs here; must exist before boot() so fd_log can open() it.
        const logs_dir = try std.fmt.allocPrint(self.allocator, "{s}/logs", .{config.run_dir});
        defer self.allocator.free(logs_dir);
        var logs_dir_handle = try std.Io.Dir.cwd().createDirPathOpen(io, logs_dir, .{});
        logs_dir_handle.close(io);

        // Supervisor log file: {run_dir}/logs/supervisor.log
        var supervisor_log_path: [256]u8 = undefined;
        const supervisor_log = std.fmt.bufPrint(&supervisor_log_path, "{s}/logs/supervisor.log", .{config.run_dir}) catch "";

        try rt.boot.bootWithSyntheticArgv(config.run_dir, supervisor_log);
        var boot_needs_halt = true;
        errdefer if (boot_needs_halt) c_abi.boot.halt();

        // v2.14.S8.T12: build the real Firedancer topology (object graph
        // and deterministic offsets) via fd_topob. Every self-exec'd
        // child rebuilds this same topology with identical inputs to get
        // byte-identical offsets — see topo_build.zig's module doc
        // ("topology handoff" finding). fd_topo_create_workspace/
        // fd_topo_join_workspace are deliberately not used here — they
        // hard-require huge/gigantic pages, which v2.14.S1 rejected for
        // Tickoni; see topob.zig's topoWkspSetPtr doc comment ("finding
        // 3") for the reused-layout-math/own-memory hybrid this drives.
        var built_topo = try rt.topo_build.build(self.allocator, self.topo, workspace_name_slice, config.metric_port);
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
        // Also clean up any stale metric/metric_in workspaces from a prior
        // run so wkspNewNamed's O_EXCL doesn't fail closed on the second
        // test invocation.
        {
            var stale_name: [64]u8 = undefined;
            const printed = std.fmt.bufPrint(&stale_name, "{s}_{s}.wksp", .{ rt.topo_build.app_name, "metric" }) catch &stale_name;
            stale_name[printed.len] = 0;
            if (c_abi.wksp.wkspExistsNamed(@ptrCast(&stale_name))) {
                _ = c_abi.wksp.wkspDeleteNamed(@ptrCast(&stale_name));
            }
        }
        {
            var stale_name: [64]u8 = undefined;
            const printed = std.fmt.bufPrint(&stale_name, "{s}_{s}.wksp", .{ rt.topo_build.app_name, "metric_in" }) catch &stale_name;
            stale_name[printed.len] = 0;
            if (c_abi.wksp.wkspExistsNamed(@ptrCast(&stale_name))) {
                _ = c_abi.wksp.wkspDeleteNamed(@ptrCast(&stale_name));
            }
        }

        // Size the real allocation off fd_topob_finish's computed
        // footprint/part_max instead of a hand-picked constant, plus a
        // little headroom.
        const footprint = c_abi.topob.topoWkspFootprint(built_topo.topo, built_topo.wksp_idx);
        const page_cnt = footprint / c_abi.wksp.shmem_normal_page_sz + 16;
        var sub_page_cnt = [_]usize{page_cnt};
        var sub_cpu_idx = [_]usize{0};
        const part_max = c_abi.topob.topoWkspPartMax(built_topo.topo, built_topo.wksp_idx);

        // Create the main workspace.
        const rc = c_abi.wksp.wkspNewNamed(workspace_name_z, c_abi.wksp.shmem_normal_page_sz, 1, &sub_page_cnt, &sub_cpu_idx, 0o600, 1, part_max);
        if (rc != 0) return error.WkspCreateFailed;
        const wksp = c_abi.wksp.wkspAttach(workspace_name_z) orelse return error.WkspAttachFailed;

        errdefer _ = c_abi.wksp.wkspDetach(wksp);

        // v2.22.S4 Task 0: Create ALL workspaces and initialize content
        // so topoWkspNew populates every workspace's objects (mcache/dcache/
        // fseq/metrics/tile/cnc).  Child-side fd_topo_run_tile calls
        // topoJoinWorkspaces which joins every workspace in the topology;
        // the parent must create and populate all of them, not just the
        // main one.
        const metric_wksp_idx = built_topo.metric_wksp_idx;
        const metric_in_wksp_idx = built_topo.metric_in_wksp_idx;

        // Helper: create and attach a named workspace, storing ptr in a
        // caller-provided slot.
        var metric_wksp_ptr: ?*c_abi.wksp.Wksp = null;
        var metric_in_wksp_ptr: ?*c_abi.wksp.Wksp = null;
        var auxiliary_workspaces_owned_by_state = false;
        errdefer if (!auxiliary_workspaces_owned_by_state) {
            if (metric_in_wksp_ptr) |metric_in_wksp| _ = c_abi.wksp.wkspDetach(metric_in_wksp);
            if (metric_wksp_ptr) |metric_wksp| _ = c_abi.wksp.wkspDetach(metric_wksp);
        };

        if (metric_wksp_idx != c_abi.topob.not_found) {
            const metric_footprint = c_abi.topob.topoWkspFootprint(built_topo.topo, metric_wksp_idx);
            const metric_part_max = c_abi.topob.topoWkspPartMax(built_topo.topo, metric_wksp_idx);
            const metric_page_cnt = metric_footprint / c_abi.wksp.shmem_normal_page_sz + 16;
            var metric_sub_page_cnt: [1]usize = .{metric_page_cnt};
            var metric_sub_cpu_idx: [1]usize = .{0};
            var metric_name_buf: [64]u8 = undefined;
            const metric_name_z = try std.fmt.bufPrint(&metric_name_buf, "tickoni_metric.wksp", .{});
            metric_name_buf[metric_name_z.len] = 0;
            if (c_abi.wksp.wkspNewNamed(@ptrCast(&metric_name_buf), c_abi.wksp.shmem_normal_page_sz, 1, &metric_sub_page_cnt, &metric_sub_cpu_idx, 0o600, 1, metric_part_max) == 0) {
                metric_wksp_ptr = c_abi.wksp.wkspAttach(@ptrCast(&metric_name_buf));

            }
        }
        if (metric_in_wksp_idx != c_abi.topob.not_found) {
            const metric_in_footprint = c_abi.topob.topoWkspFootprint(built_topo.topo, metric_in_wksp_idx);
            const metric_in_part_max = c_abi.topob.topoWkspPartMax(built_topo.topo, metric_in_wksp_idx);
            const metric_in_page_cnt = metric_in_footprint / c_abi.wksp.shmem_normal_page_sz + 16;
            var metric_in_sub_page_cnt: [1]usize = .{metric_in_page_cnt};
            var metric_in_sub_cpu_idx: [1]usize = .{0};
            var metric_in_name_buf: [64]u8 = undefined;
            const metric_in_name_z = try std.fmt.bufPrint(&metric_in_name_buf, "tickoni_metric_in.wksp", .{});
            metric_in_name_buf[metric_in_name_z.len] = 0;
            if (c_abi.wksp.wkspNewNamed(@ptrCast(&metric_in_name_buf), c_abi.wksp.shmem_normal_page_sz, 1, &metric_in_sub_page_cnt, &metric_in_sub_cpu_idx, 0o600, 1, metric_in_part_max) == 0) {
                metric_in_wksp_ptr = c_abi.wksp.wkspAttach(@ptrCast(&metric_in_name_buf));

            }
        }

        // v2.22.S4 Task 0: Set wksp ptr + create objects for metric/metric_in
        // so parent-side topoObjLaddr/gaddr resolves valid content.
        if (metric_wksp_ptr) |metric_wksp| {
            if (metric_wksp_idx == c_abi.topob.not_found) return error.MissingMetricWorkspaceIdx;
            c_abi.topob.topoWkspSetPtr(built_topo.topo, metric_wksp_idx, metric_wksp);
            c_abi.topob.topoWkspNew(built_topo.topo, metric_wksp_idx);
        }
        if (metric_in_wksp_ptr) |metric_in_wksp| {
            if (metric_in_wksp_idx == c_abi.topob.not_found) return error.MissingMetricInWorkspaceIdx;
            c_abi.topob.topoWkspSetPtr(built_topo.topo, metric_in_wksp_idx, metric_in_wksp);
            c_abi.topob.topoWkspNew(built_topo.topo, metric_in_wksp_idx);
        }

        // Inject the attached workspace into the topology and instantiate
        // every object's content (mcache/dcache/fseq/metrics/cnc — "tile"
        // has no .new) via the same fd_topob callback array used to
        // compute the layout above.
        c_abi.topob.topoWkspSetPtr(built_topo.topo, built_topo.wksp_idx, wksp);
        c_abi.topob.topoWkspNew(built_topo.topo, built_topo.wksp_idx);

        const state = try self.allocator.create(ProcessState);
        state.* = .{
            .wksp = wksp,
            .metric_wksp = metric_wksp_ptr,
            .metric_in_wksp = metric_in_wksp_ptr,
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
        auxiliary_workspaces_owned_by_state = true;
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
        var topology_spec = try rt.topology_spec.TopologySpec.fromTopology(self.topo, config.metric_port);
        // Override workspace_name with the runtime config value so
        // child tiles look for the readiness marker at the right path
        // (tests set a unique workspace_name like "test0"; the topology
        // source has it hardcoded to "tkpay0").
        topology_spec.workspace_name = try rt.link.WorkspaceName.parse(workspace_name_slice);
        try topology_spec.writeToFile(io, std.Io.Dir.cwd(), topology_spec_path);

        for (self.handles, 0..) |*h, i| {
            const tile = self.topo.tiles[i];

            const spec = try rt.launch_spec.LaunchSpec.init(.{
                .tile_idx = @intCast(i),
                .tile_id = tile.id,
                .cpu_placement = tile.cpu_placement,
                .workspace_name = try rt.link.WorkspaceName.parse(workspace_name_slice),
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
        // Preserve a real crash: once the supervisor has classified a tile as
        // crashed, subsequent reaps (e.g. during stopProcess teardown) must not
        // overwrite it.  The stale-recovery paths below are only valid for tiles
        // that were *currently* stale at the moment stopProcess started; a tile
        // that already crossed into .crashed is a genuine failure regardless of
        // what the shutdown sequence does to its process.
        if (self.handles[i].state == .crashed) return;
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
            .force_terminated => {
                // stopProcess intentionally force-terminates children that did
                // not observe CNC HALT within the bounded grace period. The
                // outcome is part of requested shutdown, not a tile crash.
                self.handles[i].state = .stopped;
                self.handles[i].crashed_because = .none;
            },
            .crashed => {
                if (self.handles[i].state == .stale) {
                    // Tile was stale when stopProcess() began — the crash is a
                    // consequence of the shutdown sequence (tile stopped
                    // heartbeating while waiting for the halt signal), not a
                    // real crash. Treat it as a clean stop, matching the
                    // .exited_ok path's intent.
                    self.handles[i].state = .stopped;
                    self.handles[i].crashed_because = .none;
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

    pub fn reapExitedChildrenNoHang(self: *Supervisor) void {
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

    /// Maximum time to wait for a child to exit after HALT + force-termination.
    /// Tiles that don't exit within this window are assumed stuck and left
    /// orphaned rather than blocking the test runner forever.
    const wait_process_max_ms: u32 = 5_000;

    pub fn waitProcess(self: *Supervisor, io: std.Io, forced_termination: ?[]const bool) void {
        _ = io;
        const log = logger.get();
        log.enter("supervisor", "waitProcess") catch {};
        defer log.exit("supervisor", "waitProcess") catch {};
        const state = self.process_state orelse return;
        const deadline = util.process.monotonicNanos() + @as(i64, @intCast(wait_process_max_ms * std.time.ms_per_s));
        for (&state.children, 0..) |*maybe_child, i| {
            var child = maybe_child.* orelse continue;
            const term = blk: {
                const start = util.process.monotonicNanos();
                if (start >= deadline) break :blk null;
                while (util.process.monotonicNanos() < deadline) {
                    switch (util.process_api.tryReapNoHang(&child)) {
                        .running => {
                            util.process.sleepNanos(1 * std.time.ms_per_s);
                        },
                        .reaped => |t| break :blk t,
                        .detached => break :blk null,
                        .failed => break :blk null,
                    }
                }
                var msg_buf: [64]u8 = undefined;
                const msg = std.fmt.bufPrint(&msg_buf, "timeout waiting for child tile {d}", .{i}) catch "timeout";
                log.debug("supervisor", "waitProcess", msg) catch {};
                break :blk null;
            };
            if (term) |t| {
                const was_forced = if (forced_termination) |forced| forced[i] else false;
                self.updateHandleForOutcome(i, util.process_api.outcomeFromTerm(t, was_forced));
                maybe_child.* = null;
            } else {
                // Timeout: do a final non-blocking reap so we capture any
                // exit code or crash evidence from children that exited
                // during the wait. Without this, FileNotFound and unexpected
                // exit codes are silently lost and tests report "passed"
                // because the handle is marked .stopped with .none.
                const outcome = blk2: {
                    switch (util.process_api.tryReapNoHang(&child)) {
                        .running, .detached, .failed => break :blk2 .exited_ok,
                        .reaped => |t| break :blk2 util.process_api.outcomeFromTerm(t, false),
                    }
                };
                self.updateHandleForOutcome(i, outcome);
                maybe_child.* = null;
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
        // Reap any exited children FIRST so we detect crashes before
        // reading cnc heartbeats.  A crashed tile's cnc is corrupted and
        // reading it can SIGSEGV/SIGABRT the supervisor; by reaping first
        // the handle is already marked .crashed and we skip it below.
        var crashed_mask: [8]bool = std.mem.zeroes([8]bool);
        for (state.children, 0..) |maybe_child, i| {
            if (maybe_child == null) continue;
            switch (util.process_api.tryReapNoHang(&state.children[i].?)) {
                .running => {},
                .reaped => |term| {
                    var exit_code: i32 = 0;
                    var reason: CrashReason = .exit_code;
                    switch (term) {
                        .signal => reason = .signal,
                        .exited => |code| {
                            exit_code = code;
                            reason = .exit_code;
                        },
                        .stopped => reason = .signal,
                        .unknown => reason = .exit_code,
                    }
                    if (exit_code == 0) continue;
                    const h = &self.handles[i];
                    if (h.state == .starting or h.state == .running) {
                        h.state = .crashed;
                        h.crashed_because = reason;
                        h.exit_code = @intCast(exit_code);
                    }
                    state.has_child_crashed = true;
                    crashed_mask[i] = true;
                },
                .detached => {
                    state.has_child_crashed = true;
                    crashed_mask[i] = true;
                },
                .failed => {},
            }
        }
        // Read heartbeats from surviving tiles only — skip any tile whose
        // child has been reaped (crashed or stopped) so we never dereference
        // a stale cnc pointer into a dead child's address space.
        for (state.cncs, 0..) |maybe_cnc, i| {
            const h = &self.handles[i];
            if (h.state != .starting and h.state != .running) continue;
            if (crashed_mask[i]) continue;
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

    /// v2.14.S1.T14: a snapshot of all tile cnc counters read in process
    /// mode (see snapshotProcessMetrics below). Pipeline tiles (tkings →
    /// tkrnorm → tkdedu → tkpoly → tkaudt) write event-flow counters;
    /// observer tiles (tkrepl, tkmetr, tkdiag) write diagnostic counters.
    /// The supervisor publishes its own local counters into its cnc
    /// app-region (see runtime/cnc_counters.zig's appCounter{Read,Write} and
    /// src/tickoni/tiles/payment_pipeline/process.zig's per-tile counter
    /// layout); this reads them back across the process boundary. Must be called
    /// before stopProcess, which leaves every cnc join and detaches the
    /// workspace.
    pub const ProcessMetricSnapshot = struct {
        // Pipeline counters (tkings → tkrnorm → tkdedu → tkpoly → tkaudt)
        produced: u64 = 0,
        normalized: u64 = 0,
        invalid: u64 = 0,
        duplicates: u64 = 0,
        allowed: u64 = 0,
        denied: u64 = 0,
        audited: u64 = 0,
        // Observer counters (tkrepl, tkmetr, tkdiag)
        replay_checked: u64 = 0,
        replay_match: u64 = 0,
        metric_snapshots: u64 = 0,
        metric_backpressure_waits: u64 = 0,
        diag_crash_count: u64 = 0,
        diag_sandbox_count: u64 = 0,
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
                    .diag_crashed_tile => snap.diag_crash_count = v,
                    .diag_sandbox_failures => snap.diag_sandbox_count = v,
                }
            }
        }
        return snap;
    }

    /// Timestamped process-mode metric snapshot for per-tile visibility during execution.
    /// Fixes V2.22.S4 "No black boxes" audit FAIL #1.
    pub const ProcessMetricSnapshotWithTime = struct {
        epoch_ns: u64,
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
        diag_crash_count: u64 = 0,
        diag_sandbox_count: u64 = 0,
    };

    /// Convert a plain ProcessMetricSnapshot into a timestamped version.
    fn processSnapToWithTime(snap: ProcessMetricSnapshot, epoch: u64) ProcessMetricSnapshotWithTime {
        return .{
            .epoch_ns = epoch,
            .produced = snap.produced,
            .normalized = snap.normalized,
            .invalid = snap.invalid,
            .duplicates = snap.duplicates,
            .allowed = snap.allowed,
            .denied = snap.denied,
            .audited = snap.audited,
            .replay_checked = snap.replay_checked,
            .replay_match = snap.replay_match,
            .metric_snapshots = snap.metric_snapshots,
            .metric_backpressure_waits = snap.metric_backpressure_waits,
            .diag_crash_count = snap.diag_crash_count,
            .diag_sandbox_count = snap.diag_sandbox_count,
        };
    }

    /// Read process metrics, annotate with current time.
    pub fn snapshotProcessMetricsWithTime(self: *const Supervisor) ProcessMetricSnapshotWithTime {
        const snap = self.snapshotProcessMetrics();
        return processSnapToWithTime(snap, @intCast(util.process.monotonicNanos()));
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
                .diag_crashed_tile => snap.diag_crash_count = v,
                .diag_sandbox_failures => snap.diag_sandbox_count = v,
            }
        }
        return snap;
    }

    /// Signals every tile to halt via its cnc (crash-only shutdown, not a
    /// POSIX signal — matches fd_cnc's own command/control model), waits
    /// for exit, and fully tears down the shared workspace. Sibling tiles
    /// are not touched by one tile's crash; this only requests a clean
    /// stop of tiles that are still running.
    /// StopProcess: send HALT, reap, deinit shared memory — used for
    /// process-mode tests that use startPaymentPipelineProcess.
    ///
    /// IMPORTANT: the pipeline thread must be stopped before stopProcess()
    /// runs, because stopProcess() does NOT touch self.pipeline and
    /// deinit() will see a live pipeline and call joinThreads() again,
    /// which hangs when the tile threads are already gone.
    pub fn stopProcess(self: *Supervisor, io: std.Io) void {
        const log = logger.get();
        log.enter("supervisor", "stopProcess") catch {};
        defer log.exit("supervisor", "stopProcess") catch {};
        const state = self.process_state orelse return;
        // Reap any already-dead children before refreshProcessHealth().
        // Otherwise refreshProcessHealth() sees a dead heartbeat, marks the
        // tile stale, and updateHandleForOutcome's stale-recovery path wrongly
        // classifies a real crash as a clean stop.
        self.reapExitedChildrenNoHang();
        self.refreshProcessHealth();
        for (state.cncs) |maybe_cnc| {
            if (maybe_cnc) |cnc| c_abi.cnc.signal(cnc, c_abi.cnc.signal_halt);
        }

        const grace_deadline = util.process.monotonicNanos() + @as(i64, @intCast(state.stop_grace_ns));
        while (util.process.monotonicNanos() < grace_deadline) {
            self.reapExitedChildrenNoHang();
            const has_running_child = for (state.children) |maybe_child| {
                if (maybe_child != null) break true;
            } else false;
            if (!has_running_child) break;
            util.process.sleepNanos(5 * std.time.ns_per_ms);
        }
        self.reapExitedChildrenNoHang();

        var forced_termination: [8]bool = undefined;
        var ci: usize = 0;
        while (ci < forced_termination.len) : (ci += 1) forced_termination[ci] = false;
        // Force terminate ALL running children, not just stale ones.
        // Tiles that finish normally never become stale but may hang
        // waiting for external events (e.g. HTTP server, CNC HALT).
        for (state.cncs, 0..) |_, i| {
            const maybe_child = &state.children[i];
            var child = maybe_child.* orelse continue;
            switch (util.process_api.tryReapNoHang(&child)) {
                .running => {
                    const pid = child.id orelse continue;
                    util.process_api.forceTerminate(pid);
                    forced_termination[i] = true;
                    maybe_child.* = child;
                },
                .reaped => |term| {
                    self.updateHandleForOutcome(i, util.process_api.outcomeFromTerm(term, false));
                    maybe_child.* = null;
                },
                .detached, .failed => {
                    maybe_child.* = null;
                },
            }
        }

        self.waitProcess(io, &forced_termination);

        // v2.24: check if any tile crashed during stopProcess so deinit()
        // knows whether to skip the fragile C-level shared memory ops.
        for (self.handles) |h| {
            if (h.state == .crashed) {
                state.has_child_crashed = true;
                break;
            }
        }

        state.deinit(io, self.allocator);
        self.allocator.destroy(state);
        self.process_state = null;
    }

    /// Returns the current handle slice — a read-only snapshot of tile states.
    pub fn monitor(self: *const Supervisor) []const TileHandle {
        return self.handles;
    }

    /// Check if any tile has crashed. Reaps children and refreshes health
    /// before checking so stale children that died during the poll window
    /// are detected. Returns true if any tile is in .crashed state.
    pub fn hasCrashed(self: *Supervisor) bool {
        // Reap any children that died during the poll window.
        self.reapExitedChildrenNoHang();
        self.refreshProcessHealth();
        for (self.handles) |h| {
            if (h.state == .crashed) return true;
        }
        return false;
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

test "Supervisor monitor returns correct tile count" {
    const topo = topologies.paymentPipeline();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    try std.testing.expectEqual(topo.tiles.len, sup.monitor().len);
}
