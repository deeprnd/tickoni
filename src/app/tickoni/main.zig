const std = @import("std");
const logger = @import("logger");
const File = std.Io.File;
const rt = @import("runtime");
const c_abi = @import("c_abi");
const util = @import("util");
const supervisor_mod = @import("supervisor.zig");
const Supervisor = supervisor_mod.Supervisor;
const ProcessPipelineConfig = supervisor_mod.ProcessPipelineConfig;
const max_tiles = supervisor_mod.max_tiles;
const tile_main = @import("tile_main.zig");
const topologies = @import("topologies");
const doctor_output = @import("doctor_output");

const version = @import("version");

const usage =
    \\Usage: tickoni-supervisor <command>
    \\
    \\Commands:
    \\  start-process   Run the Phase 0 pipeline as isolated OS processes over
    \\                  Tango shared memory (v2.14.S1); requires <run-dir>
    \\  status          Print topology tile names
    \\  doctor          Run environment checks
    \\  --version       Print version information
    \\
;

pub fn main(init: std.process.Init) !void {
    var it = try std.process.Args.iterateAllocator(init.minimal.args, init.gpa);
    defer it.deinit();
    _ = it.next(); // skip program name

    // Collect args and check for --verbose before processing commands
    var verbose: bool = false;
    var args: [256][]const u8 = undefined;
    var arg_count: usize = 0;
    while (arg_count < args.len) : (arg_count += 1) {
        const arg = it.next() orelse break;
        if (std.mem.eql(u8, arg, "--verbose")) verbose = true;
        args[arg_count] = arg;
    }
    // --verbose sets TK_LOG_LEVEL=0 before logger.init() so the current
    // process picks up debug-level output. Child processes also inherit
    // the modified environment via standard POSIX env propagation.
    if (verbose) {
        util.os_api.setEnv("TK_LOG_LEVEL", "0");
        logger.init();
    } else {
        logger.init();
    }

    const log = logger.get();

    log.enter("main", "init");
    defer log.exit("main", "init");

    if (verbose) log.debug("main", "main", "verbose mode enabled");

    // First arg is the command
    const cmd = if (arg_count > 0) args[0] else {
        try File.writeStreamingAll(File.stderr(), init.io, usage);
        std.process.exit(1);
    };

    // Handle --version flag
    if (std.mem.eql(u8, cmd, "--version")) {
        log.debug("main", "main", "version flag received");
        const ver = @import("version");
        const info = ver.VersionInfo.init(init.gpa) catch |err| {
            var buf: [256]u8 = undefined;
            const msg = try std.fmt.bufPrint(&buf, "version info init: {}\n", .{err});
            try File.writeStreamingAll(File.stderr(), init.io, msg);
            std.process.exit(1);
        };
        var buf: [1024]u8 = undefined;
        var w = std.Io.Writer.fixed(&buf);
        try ver.formatVersionInfo(info, &w);
        try std.Io.File.writeStreamingAll(std.Io.File.stdout(), init.io, w.buffered());
        log.exit("main", "version");
        return;
    }

    // Handle --help flag
    if (std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h")) {
        try File.writeStreamingAll(File.stderr(), init.io, usage);
        std.process.exit(0);
    }

    // Internal supervisor-to-child handoff for v2.14.S1 process mode
    if (std.mem.eql(u8, cmd, "__tile-run")) {
        const spec_path = if (arg_count > 1) args[1] else std.process.exit(1);
        std.process.exit(tile_main.run(init.io, init.gpa, spec_path));
    }

    if (std.mem.eql(u8, cmd, "start-process")) {
        log.debug("main", "main", "start-process command received");
        const run_dir = if (arg_count > 1) args[1] else {
            try File.writeStreamingAll(File.stderr(), init.io, "start-process requires <run-dir>\n");
            std.process.exit(1);
        };
        try cmdStartProcess(init, topologies.paymentPipelineProcess(), run_dir, verbose);
    } else if (std.mem.eql(u8, cmd, "status")) {
        log.debug("main", "main", "status command received");
        try cmdStatus(init.io, topologies.paymentPipeline());
    } else if (std.mem.eql(u8, cmd, "doctor")) {
        log.debug("main", "main", "doctor command received");
        var format: doctor_output.Format = .text;
        while (it.next()) |a| {
            if (std.mem.eql(u8, a, "--json")) format = .json;
        }
        try cmdDoctor(init, format);
    } else {
        var log_buf: [128]u8 = undefined;
        const msg = try std.fmt.bufPrint(&log_buf, "unknown command: {s}\n", .{cmd});
        log.err("main", "main", msg);
        try File.writeStreamingAll(File.stderr(), init.io, msg);
        try File.writeStreamingAll(File.stderr(), init.io, usage);
        std.process.exit(1);
    }
}

fn cmdDoctor(init: std.process.Init, format: doctor_output.Format) !void {
    const log = logger.get();
    log.enter("cmdDoctor", "init");
    defer log.exit("cmdDoctor", "done");

    var buf: [8192]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    const fmt_msg = try std.fmt.bufPrint(&buf, "running doctor checks, format={s}", .{@tagName(format)});
    log.debug("main", "cmdDoctor", fmt_msg);
    try doctor_output.runAndFormat(init.io, init.gpa, format, &w);
    const output = w.buffered();
    try std.Io.File.writeStreamingAll(std.Io.File.stdout(), init.io, output);

    // Exit code: 0 for pass/warn, 1 for fail
    const doctor_checks = @import("doctor_checks");
    var results: [20]doctor_checks.Result = undefined;
    const count = doctor_checks.runAll(&results, init.io, init.gpa);
    var fail_count: usize = 0;
    for (results[0..count]) |r| {
        if (r.status == .fail) fail_count += 1;
    }
    const diag_msg = try std.fmt.bufPrint(&buf, "doctor checks complete: {d} failures", .{fail_count});
    log.debug("main", "cmdDoctor", diag_msg);
    std.process.exit(if (fail_count > 0) 1 else 0);
}

/// v2.14.S1: run the payment pipeline as one OS process per tile connected
/// by Tango shared memory instead of in-process threads. run_dir holds the
/// per-tile launch specs and the FD_SHMEM_PATH workspace backing.
fn cmdStartProcess(init: std.process.Init, topo: rt.topology.Topology, run_dir: []const u8, verbose: bool) !void {
    const log = logger.get();
    log.enter("cmdStartProcess", "init");
    defer log.exit("cmdStartProcess", "done");

    const stdout = File.stdout();
    var sup = try Supervisor.init(init.gpa, topo);
    defer sup.deinit();

    var buf: [256]u8 = undefined;
    const proc_msg = try std.fmt.bufPrint(&buf, "starting process-mode pipeline: run_dir={s}", .{run_dir});
    log.debug("main", "cmdStartProcess", proc_msg);
    const process_config = ProcessPipelineConfig{ .run_dir = run_dir, .verbose = verbose };
    try sup.startPaymentPipelineProcess(init.io, process_config);
    log.debug("main", "cmdStartProcess", "process-mode pipeline started, monitoring tiles");

    try File.writeStreamingAll(stdout, init.io, "tickoni-supervisor: process-mode pipeline started\ntiles:\n");
    for (sup.monitor()) |h| {
        const tile_name = topo.tiles[h.tile_idx].id.slice();
        const line = try std.fmt.bufPrint(&buf, "  [{d}] {s}  pid={?}  state={s}\n", .{
            h.tile_idx,
            tile_name,
            h.pid,
            @tagName(h.state),
        });
        try File.writeStreamingAll(stdout, init.io, line);
    }

    // Poll for pipeline completion with per-tile metric sampling.
    // Fixes V2.22.S4 "No black boxes" audit FAIL #1.
    const sample_interval_ns: u64 = 1 * std.time.ns_per_s;
    const max_samples: u32 = 600; // 10 min bound
    var sample_count: u32 = 0;

    // Collect per-tile snapshots for delta comparison.
    var prev_per_tile: [max_tiles]Supervisor.ProcessMetricSnapshot = undefined;
    for (0..prev_per_tile.len) |i| {
        prev_per_tile[i] = try sup.snapshotProcessMetricsForTile(i);
    }

    // Poll for pipeline completion with per-tile delta output
    while (sample_count < max_samples) : (sample_count += 1) {
        if (sup.snapshotProcessMetrics().audited >= process_config.event_count) break;
        util.process.sleepNanos(sample_interval_ns);

        var curr_per_tile: [max_tiles]Supervisor.ProcessMetricSnapshot = undefined;
        for (0..curr_per_tile.len) |i| {
            curr_per_tile[i] = try sup.snapshotProcessMetricsForTile(i);
        }

        // Print per-tile deltas
        const count = @min(prev_per_tile.len, curr_per_tile.len);
        for (0..count) |i| {
            const p = prev_per_tile[i];
            const c = curr_per_tile[i];
            const tile_id = topo.tiles[i].id;
            const delta_prod = @as(i64, @intCast(c.produced)) - @as(i64, @intCast(p.produced));
            const delta_norm = @as(i64, @intCast(c.normalized)) - @as(i64, @intCast(p.normalized));
            const delta_inv = @as(i64, @intCast(c.invalid)) - @as(i64, @intCast(p.invalid));
            const delta_dup = @as(i64, @intCast(c.duplicates)) - @as(i64, @intCast(p.duplicates));
            const delta_allow = @as(i64, @intCast(c.allowed)) - @as(i64, @intCast(p.allowed));
            const delta_deny = @as(i64, @intCast(c.denied)) - @as(i64, @intCast(p.denied));
            const delta_audit = @as(i64, @intCast(c.audited)) - @as(i64, @intCast(p.audited));
            if (delta_prod != 0 or delta_norm != 0 or delta_inv != 0 or delta_dup != 0 or delta_allow != 0 or delta_deny != 0 or delta_audit != 0) {
                const tile_name = tile_id.slice();
                const line = try std.fmt.bufPrint(
                    &buf,
                    "  tile={s}  dP={d} dN={d} dI={d} dD={d} dA={d} dR={d} dU={d}\n",
                    .{ tile_name, delta_prod, delta_norm, delta_inv, delta_dup, delta_allow, delta_deny, delta_audit },
                );
                try File.writeStreamingAll(stdout, init.io, line);
            }
        }
        try File.writeStreamingAll(stdout, init.io, "\n");

        for (0..curr_per_tile.len) |i| {
            prev_per_tile[i] = curr_per_tile[i];
        }
    }

    const metrics = sup.snapshotProcessMetrics();
    const metrics_line = try std.fmt.bufPrint(
        &buf,
        "metrics: produced={d} normalized={d} invalid={d} duplicates={d} allowed={d} denied={d} audited={d}\n",
        .{ metrics.produced, metrics.normalized, metrics.invalid, metrics.duplicates, metrics.allowed, metrics.denied, metrics.audited },
    );
    try File.writeStreamingAll(stdout, init.io, metrics_line);

    try sup.stopProcess(init.io);
    try File.writeStreamingAll(stdout, init.io, "tickoni-supervisor: process-mode pipeline stopped\n");
}

fn cmdStatus(io: std.Io, topo: rt.topology.Topology) !void {
    const log = logger.get();
    log.enter("cmdStatus", "init");
    defer log.exit("cmdStatus", "done");

    const stdout = File.stdout();
    var buf: [256]u8 = undefined;

    const topo_msg = try std.fmt.bufPrint(&buf, "showing topology: {d} tiles, {d} channels", .{
        topo.tiles.len, topo.channels.len,
    });
    log.debug("main", "cmdStatus", topo_msg);

    const header = try std.fmt.bufPrint(&buf, "topology: {d} tiles, {d} channels\n", .{
        topo.tiles.len, topo.channels.len,
    });
    try File.writeStreamingAll(stdout, io, header);

    for (topo.tiles, 0..) |t, i| {
        const line = try std.fmt.bufPrint(&buf, "  [{d}] id={s}  name={s}\n", .{
            i, t.id.slice(), t.name,
        });
        try File.writeStreamingAll(stdout, io, line);
    }
}
