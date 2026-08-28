const std = @import("std");
const logger = @import("logger");
const File = std.Io.File;
const rt = @import("runtime");
const c_abi = @import("c_abi");
const util = @import("util");
const supervisor_mod = @import("supervisor.zig");
const Supervisor = supervisor_mod.Supervisor;
const ProcessPipelineConfig = supervisor_mod.ProcessPipelineConfig;
const tile_main = @import("tile_main.zig");
const topologies = @import("topologies");
const doctor_output = @import("doctor_output");
const demo_preflight = @import("demo_preflight");
const demo_cli = @import("demo_cli");
const demo_conformance = @import("demo_conformance");
const demo_comparator = @import("demo_comparator");
const demo_runner = @import("demo_runner");
const demo_substitution = @import("demo_substitution");
const version = @import("version");

const usage =
    \\Usage: tickoni-supervisor <command>
    \\
    \\Commands:
    \\  start           Run the Phase 0 Tickoni pipeline spike (dev/test mode)
    \\  start-process   Run the Phase 0 pipeline as isolated OS processes over
    \\                  Tango shared memory (v2.14.S1); requires <run-dir>
    \\  status          Print topology tile names
    \\  doctor          Run environment checks
    \\  demo investment --manifest <path> [--json|--plain]
    \\                  Run the deterministic investment demo (preflight-gated)
    \\  --version       Print version information
    \\
;

const ComparisonSummary = struct {
    scenario: []const u8,
    matches: bool,
    mismatch_count: usize,
};

fn boolText(value: bool) []const u8 {
    return if (value) "true" else "false";
}

pub fn main(init: std.process.Init) !void {
    const log = logger.get();
    logger.init();

    try log.enter("main", "init");
    defer log.exit("main", "init") catch {};

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
    if (verbose) {
        logger.enableVerbose();
        util.os_api.setEnv("ZIG_LOG_LEVEL", "debug");
    }

    if (verbose) log.debug("main", "main", "verbose mode enabled") catch {};

    // First arg is the command
    const cmd = if (arg_count > 0) args[0] else {
        try File.writeStreamingAll(File.stderr(), init.io, usage);
        std.process.exit(1);
    };

    // Handle --version flag
    if (std.mem.eql(u8, cmd, "--version")) {
        log.debug("main", "main", "version flag received") catch {};
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
        log.exit("main", "version") catch {};
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

    if (std.mem.eql(u8, cmd, "start")) {
        log.debug("main", "main", "start command received") catch {};
        try cmdStart(init, topologies.paymentPipeline());
    } else if (std.mem.eql(u8, cmd, "start-process")) {
        log.debug("main", "main", "start-process command received") catch {};
        const run_dir = it.next() orelse {
            try File.writeStreamingAll(File.stderr(), init.io, "start-process requires <run-dir>\n");
            std.process.exit(1);
        };
        try cmdStartProcess(init, topologies.paymentPipelineProcess(), run_dir, verbose);
    } else if (std.mem.eql(u8, cmd, "status")) {
        log.debug("main", "main", "status command received") catch {};
        try cmdStatus(init.io, topologies.paymentPipeline());
    } else if (std.mem.eql(u8, cmd, "doctor")) {
        log.debug("main", "main", "doctor command received") catch {};
        var format: doctor_output.Format = .text;
        while (it.next()) |a| {
            if (std.mem.eql(u8, a, "--json")) format = .json;
        }
        try cmdDoctor(init, format);
    } else if (std.mem.eql(u8, cmd, "demo")) {
        log.debug("main", "main", "demo command received") catch {};
        const demo_cmd = demo_cli.parseDemoArgs(args[1..arg_count]) catch |err| {
            var buf: [256]u8 = undefined;
            const msg = try std.fmt.bufPrint(&buf, "demo usage error: {}\n", .{err});
            try File.writeStreamingAll(File.stderr(), init.io, msg);
            try File.writeStreamingAll(File.stderr(), init.io, usage);
            std.process.exit(1);
        };
        try cmdDemo(init, demo_cmd);
    } else {
        var log_buf: [128]u8 = undefined;
        const msg = try std.fmt.bufPrint(&log_buf, "unknown command: {s}\n", .{cmd});
        log.err("main", "main", msg) catch {};
        try File.writeStreamingAll(File.stderr(), init.io, msg);
        try File.writeStreamingAll(File.stderr(), init.io, usage);
        std.process.exit(1);
    }
}

fn cmdDoctor(init: std.process.Init, format: doctor_output.Format) !void {
    const log = logger.get();
    try log.enter("cmdDoctor", "init");
    defer log.exit("cmdDoctor", "done") catch {};

    var buf: [8192]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    const fmt_msg = try std.fmt.bufPrint(&buf, "running doctor checks, format={s}", .{@tagName(format)});
    log.debug("main", "cmdDoctor", fmt_msg) catch {};
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
    log.debug("main", "cmdDoctor", diag_msg) catch {};
    std.process.exit(if (fail_count > 0) 1 else 0);
}

fn cmdStart(init: std.process.Init, topo: rt.topology.Topology) !void {
    const log = logger.get();
    try log.enter("cmdStart", "init");
    defer log.exit("cmdStart", "done") catch {};

    const stdout = File.stdout();
    var sup = try Supervisor.init(init.gpa, topo);
    defer sup.deinit();

    log.debug("main", "cmdStart", "starting payment pipeline: event_count=10000, queue_depth=64") catch {};
    try sup.startPaymentPipeline(.{ .event_count = 10_000, .queue_depth = 64 });
    log.debug("main", "cmdStart", "pipeline started, waiting") catch {};
    sup.wait();
    log.debug("main", "cmdStart", "pipeline completed") catch {};

    try File.writeStreamingAll(stdout, init.io, "tickoni-supervisor: Phase 0 pipeline completed\ntiles:\n");

    var buf: [256]u8 = undefined;
    for (sup.monitor()) |h| {
        const line = try std.fmt.bufPrint(&buf, "  [{d}] {s}  state={s}\n", .{
            h.tile_idx,
            topo.tiles[h.tile_idx].name,
            @tagName(h.state),
        });
        try File.writeStreamingAll(stdout, init.io, line);
    }

    if (sup.pipeline) |state| {
        const metrics = state.snapshotMetrics();
        const diag = state.snapshotDiag();
        const metrics_line = try std.fmt.bufPrint(
            &buf,
            "metrics: produced={d} normalized={d} invalid={d} duplicates={d} allowed={d} denied={d} audited={d} backpressure_waits={d} max_queue_depth={d} max_latency_hops={d}\n",
            .{
                metrics.produced,
                metrics.normalized,
                metrics.invalid,
                metrics.duplicates,
                metrics.allowed,
                metrics.denied,
                metrics.audited,
                metrics.backpressure_waits,
                metrics.max_queue_depth,
                metrics.max_latency_hops,
            },
        );
        try File.writeStreamingAll(stdout, init.io, metrics_line);

        const diag_line = try std.fmt.bufPrint(
            &buf,
            "diag: sandbox_failures={d} audit_records={d} crashed_tile={d} replay_checked={s} replay_match={s}\n",
            .{
                diag.sandbox_failures,
                diag.audit_records,
                diag.crashed_tile,
                if (diag.replay_checked) "true" else "false",
                if (diag.replay_match) "true" else "false",
            },
        );
        try File.writeStreamingAll(stdout, init.io, diag_line);
    }

    sup.stop();
    try File.writeStreamingAll(stdout, init.io, "tickoni-supervisor: stopped\n");
}

/// v2.14.S1: run the payment pipeline as one OS process per tile connected
/// by Tango shared memory instead of in-process threads. run_dir holds the
/// per-tile launch specs and the FD_SHMEM_PATH workspace backing.
fn cmdStartProcess(init: std.process.Init, topo: rt.topology.Topology, run_dir: []const u8, verbose: bool) !void {
    const log = logger.get();
    try log.enter("cmdStartProcess", "init");
    defer log.exit("cmdStartProcess", "done") catch {};

    const stdout = File.stdout();
    var sup = try Supervisor.init(init.gpa, topo);
    defer sup.deinit();

    var buf: [256]u8 = undefined;
    const proc_msg = try std.fmt.bufPrint(&buf, "starting process-mode pipeline: run_dir={s}", .{run_dir});
    log.debug("main", "cmdStartProcess", proc_msg) catch {};
    const process_config = ProcessPipelineConfig{ .run_dir = run_dir, .verbose = verbose };
    try sup.startPaymentPipelineProcess(init.io, process_config);
    log.debug("main", "cmdStartProcess", "process-mode pipeline started, monitoring tiles") catch {};

    try File.writeStreamingAll(stdout, init.io, "tickoni-supervisor: process-mode pipeline started\ntiles:\n");
    for (sup.monitor()) |h| {
        const line = try std.fmt.bufPrint(&buf, "  [{d}] {s}  pid={?}  state={s}\n", .{
            h.tile_idx,
            topo.tiles[h.tile_idx].name,
            h.pid,
            @tagName(h.state),
        });
        try File.writeStreamingAll(stdout, init.io, line);
    }

    // Poll for pipeline completion (audited count reaches event_count)
    const poll_interval_ns: u64 = 5 * std.time.ns_per_ms;
    const max_polls: u32 = 2000; // 10s bound
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= process_config.event_count) break;
        util.process.sleepNanos(poll_interval_ns);
    }

    const metrics = sup.snapshotProcessMetrics();
    const metrics_line = try std.fmt.bufPrint(
        &buf,
        "metrics: produced={d} normalized={d} invalid={d} duplicates={d} allowed={d} denied={d} audited={d}\n",
        .{ metrics.produced, metrics.normalized, metrics.invalid, metrics.duplicates, metrics.allowed, metrics.denied, metrics.audited },
    );
    try File.writeStreamingAll(stdout, init.io, metrics_line);

    sup.stopProcess(init.io);
    try File.writeStreamingAll(stdout, init.io, "tickoni-supervisor: process-mode pipeline stopped\n");
}

fn cmdStatus(io: std.Io, topo: rt.topology.Topology) !void {
    const log = logger.get();
    try log.enter("cmdStatus", "init");
    defer log.exit("cmdStatus", "done") catch {};

    const stdout = File.stdout();
    var buf: [256]u8 = undefined;

    const topo_msg = try std.fmt.bufPrint(&buf, "showing topology: {d} tiles, {d} channels", .{
        topo.tiles.len, topo.channels.len,
    });
    log.debug("main", "cmdStatus", topo_msg) catch {};

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

/// Demo command — fail-closed preflight check before running any demo.
///
/// If preflight fails, prints diagnostic error and exits 1.
/// No proposal/audit artifacts are created.
fn cmdDemo(init: std.process.Init, demo_cmd: demo_cli.Command) !void {
    // Load manifest
    const cwd = std.Io.Dir.cwd();
    const m = demo_preflight.loadManifest(init.gpa, init.io, cwd, demo_cmd.manifest_path) catch |err| {
        var buf: [256]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "error: could not load manifest '{s}': {}\n", .{ demo_cmd.manifest_path, err });
        try File.writeStreamingAll(File.stderr(), init.io, msg);
        std.process.exit(1);
    };
    defer demo_preflight.deinitManifest(m, init.gpa);

    // Gather installed system info
    var version_info = version.VersionInfo.init(init.gpa) catch |err| {
        var buf: [256]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "error: version info init failed: {}\n", .{err});
        try File.writeStreamingAll(File.stderr(), init.io, msg);
        std.process.exit(1);
    };
    defer version_info.deinit(init.gpa);

    // T6: wire manifest version into VersionInfo
    version_info.setDemoManifestVersion(init.gpa, m.demo_manifest_version) catch |err| {
        var buf: [256]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "error: failed to set demo manifest version: {}\n", .{err});
        try File.writeStreamingAll(File.stderr(), init.io, msg);
        std.process.exit(1);
    };

    // Run preflight — fail-closed
    const preflight_result = demo_preflight.evaluate(
        init.gpa,
        init.io,
        m,
        cwd,
        version_info.semver,
        version_info.runtime_tier,
        version_info.isolation_tier,
        "src/tickoni/demo/fixtures",
    ) catch |err| {
        var buf: [256]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "error: preflight failed: {}\n", .{err});
        try File.writeStreamingAll(File.stderr(), init.io, msg);
        std.process.exit(1);
    };
    defer demo_preflight.deinit(preflight_result, init.gpa);
    if (!preflight_result.passed) {
        var stderr_buffer: [4096]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buffer);
        try demo_preflight.formatFailure(preflight_result, &stderr_writer.interface);
        try stderr_writer.flush();
        std.process.exit(1);
    }

    const scenarios = [_]demo_substitution.Scenario{
        .allowed,
        .oversized_blocked,
        .restricted_instrument,
        .tampered_replay,
    };
    var artifacts: [scenarios.len]demo_conformance.Artifact = undefined;
    var baseline_artifacts: [scenarios.len]demo_conformance.Artifact = undefined;
    var comparisons: [scenarios.len]ComparisonSummary = undefined;
    const baseline_runtime_tier = "linux_full";
    const baseline_isolation_tier = m.requiredIsolationTierFor(baseline_runtime_tier) orelse "full";
    var comparison_all_match = true;
    for (scenarios, 0..) |scenario, idx| {
        const backend = demo_substitution.backendForScenario(scenario);
        artifacts[idx] = try demo_runner.runWithBackend(init.gpa, cwd, init.io, .{
            .manifest_id = "demo.investment.v1",
            .manifest_version = m.demo_manifest_version orelse "1",
            .tickoni_version = version_info.semver,
            .runtime_tier = version_info.runtime_tier,
            .isolation_tier = version_info.isolation_tier,
        }, backend);
        baseline_artifacts[idx] = try demo_runner.runWithBackend(init.gpa, cwd, init.io, .{
            .manifest_id = "demo.investment.v1",
            .manifest_version = m.demo_manifest_version orelse "1",
            .tickoni_version = version_info.semver,
            .runtime_tier = baseline_runtime_tier,
            .isolation_tier = baseline_isolation_tier,
        }, backend);
        const report = demo_comparator.compare(baseline_artifacts[idx], artifacts[idx]);
        comparisons[idx] = .{
            .scenario = artifacts[idx].scenario,
            .matches = report.matches,
            .mismatch_count = report.mismatch_count,
        };
        comparison_all_match = comparison_all_match and report.matches;
    }

    switch (demo_cmd.format) {
        .plain => {
            var header_buffer: [1024]u8 = undefined;
            const header = try std.fmt.bufPrint(
                &header_buffer,
                "comparison_baseline_runtime_tier: {s}\ncomparison_target_runtime_tier: {s}\ncomparison_target_isolation_tier: {s}\ncomparison_all_match: {s}\n",
                .{ baseline_runtime_tier, version_info.runtime_tier, version_info.isolation_tier, boolText(comparison_all_match) },
            );
            try File.writeStreamingAll(File.stdout(), init.io, header);
            for (comparisons) |comparison| {
                var comparison_buffer: [256]u8 = undefined;
                const line = try std.fmt.bufPrint(
                    &comparison_buffer,
                    "comparison_scenario: {s} match={s} mismatch_count={d}\n",
                    .{ comparison.scenario, boolText(comparison.matches), comparison.mismatch_count },
                );
                try File.writeStreamingAll(File.stdout(), init.io, line);
            }
            for (artifacts) |artifact| {
                try File.writeStreamingAll(File.stdout(), init.io, "---\n");
                var stdout_buffer: [4096]u8 = undefined;
                var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
                try demo_conformance.writePlain(&stdout_writer.interface, artifact);
                try stdout_writer.flush();
            }
        },
        .json => {
            var parts: [artifacts.len][]u8 = undefined;
            defer for (parts) |part| init.gpa.free(part);
            for (artifacts, 0..) |artifact, idx| {
                parts[idx] = try demo_conformance.allocJson(init.gpa, artifact);
            }
            const payload = try std.fmt.allocPrint(
                init.gpa,
                "{{\"suite\":[{s},{s},{s},{s}],\"preflight\":\"passed\",\"comparison\":{{\"baseline_runtime_tier\":\"{s}\",\"target_runtime_tier\":\"{s}\",\"target_isolation_tier\":\"{s}\",\"all_match\":{s},\"scenarios\":[{{\"scenario\":\"{s}\",\"matches\":{s},\"mismatch_count\":{d}}},{{\"scenario\":\"{s}\",\"matches\":{s},\"mismatch_count\":{d}}},{{\"scenario\":\"{s}\",\"matches\":{s},\"mismatch_count\":{d}}},{{\"scenario\":\"{s}\",\"matches\":{s},\"mismatch_count\":{d}}}]}}}}\n",
                .{ parts[0], parts[1], parts[2], parts[3], baseline_runtime_tier, version_info.runtime_tier, version_info.isolation_tier, boolText(comparison_all_match), comparisons[0].scenario, boolText(comparisons[0].matches), comparisons[0].mismatch_count, comparisons[1].scenario, boolText(comparisons[1].matches), comparisons[1].mismatch_count, comparisons[2].scenario, boolText(comparisons[2].matches), comparisons[2].mismatch_count, comparisons[3].scenario, boolText(comparisons[3].matches), comparisons[3].mismatch_count },
            );
            defer init.gpa.free(payload);
            try File.writeStreamingAll(File.stdout(), init.io, payload);
        },
    }
}
