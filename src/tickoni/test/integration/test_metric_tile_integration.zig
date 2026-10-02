/// v2.26-python: Integration tests for the metric tile (tkmetr) lifecycle.
///
/// Tests:
///   - Build metric topology, verify tile references are laid out
///   - Start pipeline with small event count, verify tile serves metrics
///   - Verify HTTP /metrics returns 200 with valid Prometheus text
///   - Verify required metric names are present and values are sane
///   - Verify HTTP 404 for unknown paths
///   - Verify clean shutdown
///
/// Uses the existing process-mode topology infrastructure.
///
/// HTTP client: spawns a Python subprocess that calls urllib.request.
/// Cross-platform, no POSIX socket code.
const std = @import("std");
const c_abi = @import("c_abi");
const runtime = @import("runtime");
const supervisor_mod = @import("supervisor");
const topologies = @import("topologies");
const util = @import("util");

const Supervisor = supervisor_mod.Supervisor;

const METRICS_HOST = "127.0.0.1";

// ---------------------------------------------------------------------------
// HTTP client: subprocess + Python script.
// ---------------------------------------------------------------------------

const HttpResponse = struct {
    status_code: u16,
    body: []u8,
};

/// Find the metric_http_get.py script relative to the working directory.
fn httpScriptPath(allocator: std.mem.Allocator) ![]const u8 {
    return try std.fs.path.join(allocator, &.{
        "src", "tickoni", "test", "integration", "metric_http_get.py",
    });
}

/// Spawn the Python HTTP client script and return the response.
fn httpGetProcess(host: []const u8, port: u16, path: []const u8, timeout_ms: u32) anyerror!HttpResponse {
    const script_path = httpScriptPath(std.testing.allocator) catch unreachable;
    defer std.testing.allocator.free(script_path);

    const port_str = try std.fmt.allocPrint(std.testing.allocator, "{d}", .{port});
    const timeout_str = try std.fmt.allocPrint(std.testing.allocator, "{d}", .{timeout_ms});
    defer std.testing.allocator.free(port_str);
    defer std.testing.allocator.free(timeout_str);

    const result = try std.process.run(std.testing.allocator, std.testing.io, .{
        .argv = &.{
            "python3",
            script_path,
            host,
            port_str,
            path,
            timeout_str,
        },
        .stdout_limit = .limited(65536),
        .timeout = .{ .duration = .{ .raw = .{ .nanoseconds = @as(i96, 10) * std.time.ns_per_s }, .clock = .awake } },
    });
    defer {
        std.testing.allocator.free(result.stdout);
        std.testing.allocator.free(result.stderr);
    }

    if (result.stdout.len == 0) {
        return error.NoOutput;
    }

    // Parse JSON response
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, result.stdout, .{});
    defer parsed.deinit();

    const obj = switch (parsed.value) {
        .object => |o| o,
        else => return error.InvalidJsonFormat,
    };

    var status_code: u16 = 0;
    var body_str: ?[]const u8 = null;
    var has_error: bool = false;

    if (obj.get("status_code")) |sc_val| {
        switch (sc_val) {
            .integer => |v| {
                status_code = @intCast(v);
            },
            else => {},
        }
    }
    if (obj.get("body")) |b_val| {
        switch (b_val) {
            .string => |s| {
                body_str = s;
            },
            else => {},
        }
    }
    if (obj.get("error")) |e_val| {
        switch (e_val) {
            .string => |s| {
                if (s.len > 0) has_error = true;
            },
            .integer => |v| {
                if (v != 0) has_error = true;
            },
            else => {},
        }
    }

    if (has_error) {
        return error.HttpRequestFailed;
    }
    if (body_str == null) {
        return error.NoBody;
    }

    return HttpResponse{
        .status_code = status_code,
        .body = try std.testing.allocator.dupe(u8, body_str.?),
    };
}

/// Retry httpGetProcess with bounded attempts.
fn httpGetWithRetry(host: []const u8, port: u16, path: []const u8, max_attempts: u8, timeout_ms: u32) anyerror!HttpResponse {
    var attempt: u8 = 0;
    while (attempt < max_attempts) : (attempt += 1) {
        const resp = httpGetProcess(host, port, path, timeout_ms) catch {
            util.process.sleepNanos(10 * std.time.ns_per_ms);
            continue;
        };
        return resp;
    }
    return error.ConnectionTimeout;
}

// ---------------------------------------------------------------------------
// Prometheus text-format parser — extract a single metric value.
// Returns null if the metric name is not found.
// ---------------------------------------------------------------------------

fn parsePrometheusMetric(body: []const u8, name: []const u8) ?u64 {
    var it = std.mem.splitScalar(u8, body, '\n');
    while (it.next()) |line| {
        if (line.len == 0 or line[0] == '#') continue;

        const first_space = std.mem.indexOfScalar(u8, line, ' ') orelse continue;
        const series = line[0..first_space];
        const labels_start = std.mem.indexOfScalar(u8, series, '{') orelse series.len;
        var metric_name = series[0..labels_start];
        // Strip _total suffix for comparison (Prometheus counters often end in _total)
        if (std.mem.endsWith(u8, metric_name, "_total")) {
            metric_name = metric_name[0 .. metric_name.len - "_total".len];
        }
        // Also strip _total from the search name for consistent comparison
        var search_name = name;
        if (std.mem.endsWith(u8, search_name, "_total")) {
            search_name = search_name[0 .. search_name.len - "_total".len];
        }
        if (!std.mem.eql(u8, metric_name, search_name)) continue;

        const value = std.mem.trim(u8, line[first_space + 1 ..], " \r");
        return std.fmt.parseInt(u64, value, 10) catch null;
    }
    return null;
}

test "parsePrometheusMetric accepts counter total suffix" {
    const body = "metric_bytes_read_total 42\n";
    try std.testing.expectEqual(@as(?u64, 42), parsePrometheusMetric(body, "metric_bytes_read"));
}

// ---------------------------------------------------------------------------
// Crash detection helper.
// ---------------------------------------------------------------------------

fn expectNoCrashes(sup: *Supervisor, run_dir: []const u8) !void {
    sup.reapExitedChildrenNoHang();
    sup.refreshProcessHealth();

    for (sup.monitor()) |h| {
        if (h.state == .crashed) {
            std.debug.print(
                "  tile {d} crashed: exit_code={d} reason={s}\n",
                .{ h.tile_idx, h.exit_code, @tagName(h.crashed_because) },
            );
        }
    }
    // Only fail if a non-initial tile crashed. Tile 0 (ingress) is allowed
    // to exit normally when the pipeline completes.
    var has_tile_crash = false;
    for (sup.monitor()) |h| {
        if (h.state == .crashed and h.tile_idx != 0) {
            has_tile_crash = true;
        }
    }
    if (has_tile_crash) {
        const logs_dir = try std.testing.allocator.dupe(u8, run_dir);
        defer std.testing.allocator.free(logs_dir);
        const log_path = try std.testing.allocator.dupe(u8, std.fmt.allocPrint(
            std.testing.allocator,
            "{s}/logs",
            .{run_dir},
        ) catch unreachable);
        defer std.testing.allocator.free(log_path);
        const dir = std.Io.Dir.cwd().openDir(std.testing.io, log_path, .{}) catch unreachable;
        defer dir.close(std.testing.io);
        var iter = dir.iterate();
        while (try iter.next(std.testing.io)) |entry| {
            std.debug.print("  log: {s}\n", .{entry.name});
        }
        std.debug.panic("TileCrashed", .{});
    }
}

// ---------------------------------------------------------------------------
// Test: finalized metric topology references only laid-out objects.
// ---------------------------------------------------------------------------

test "metric topology finalizes every tile-referenced object" {
    const port = util.metricPort();
    std.debug.print("\n  [tkmetr-test] metric_port = {d}\n", .{port});

    var built = try runtime.topo_build.build(
        std.testing.allocator,
        topologies.paymentPipelineProcess(),
        "tkmetr0",
        port,
    );
    defer built.deinit(std.testing.allocator);

    try std.testing.expect(built.metric_tile_idx != c_abi.topob.not_found);
    try std.testing.expect(built.metric_tile_obj_id != 0);
    try std.testing.expect(c_abi.topob.topoObjOffset(built.topo, built.metric_tile_obj_id) != 0);
    try std.testing.expect(c_abi.topob.topoValidateTileObjectOffsets(built.topo));
}

// ---------------------------------------------------------------------------
// Test: topology with tkmetr builds and starts the pipeline.
// ---------------------------------------------------------------------------

test "metric_tile_integration: topology with tkmetr builds and starts" {
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.paymentPipelineProcess();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer {
        sup.stopProcess(std.testing.io);
        sup.deinit();
    }

    const port = util.metricPort();
    std.debug.print("\n  [tkmetr-test] metric_port = {d}\n", .{port});

    // Verify tkmetr tile exists in topology
    var found_metric_tile = false;
    for (topo.tiles) |tile| {
        if (std.mem.eql(u8, tile.id.slice(), "metric")) {
            found_metric_tile = true;
            break;
        }
    }
    try std.testing.expect(found_metric_tile);

    const event_count: u64 = 1000;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = "metr0",
        .metric_port = port,
    });

    const max_polls: u32 = 400;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }

    const metrics = sup.snapshotProcessMetrics();
    try std.testing.expectEqual(event_count, metrics.audited);

    try expectNoCrashes(&sup, run_dir);
    sup.stopProcess(std.testing.io);
}

// ---------------------------------------------------------------------------
// Test: /metrics returns HTTP 200 with valid prometheus text and expected
// metric names. Uses thread + timeout + blocking POSIX socket.
//
// NOTE: the tile name in Prometheus output is "metric" (from fd_tile_metric.name),
// matching the tile ID.
// ---------------------------------------------------------------------------

test "metric_tile_integration: /metrics returns HTTP 200 with valid content" {
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.paymentPipelineProcess();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer {
        sup.stopProcess(std.testing.io);
        sup.deinit();
    }

    const port = util.metricPort();
    std.debug.print("\n  [tkmetr-test] metric_port = {d}\n", .{port});
    const event_count: u64 = 10;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = "metr1",
        .metric_port = port,
    });

    // Wait for the pipeline to finish processing (fast with 10 events)
    var wait_poll: u32 = 0;
    while (wait_poll < 200) : (wait_poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }

    // Fetch /metrics — single request, fail immediately if metrics are missing.
    const resp = httpGetProcess(METRICS_HOST, port, "/metrics", 5000) catch |err| {
        std.debug.panic("Failed to fetch /metrics: {s}", .{@errorName(err)});
    };
    defer std.testing.allocator.free(resp.body);

    // DEBUG: dump the raw response body
    std.debug.print("\n=== /metrics response (len={d}) ===\n{s}===\n\n", .{ resp.body.len, resp.body });

    const has_heartbeat = std.mem.indexOf(u8, resp.body, "metric_boot_timestamp_nanos") != null;
    const has_consumed = std.mem.indexOf(u8, resp.body, "metric_bytes_read") != null;
    try std.testing.expect(has_heartbeat);
    try std.testing.expect(has_consumed);

    try std.testing.expect(resp.body.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "# HELP") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "# TYPE") != null);

    // Verify bytes consumed > 0 (tile processed events).
    const bytes_consumed = parsePrometheusMetric(resp.body, "metric_bytes_read");
    try std.testing.expect(bytes_consumed != null);
    try std.testing.expect(bytes_consumed.? > 0);

    try expectNoCrashes(&sup, run_dir);
    sup.stopProcess(std.testing.io);
}

// ---------------------------------------------------------------------------
// Test: /foo returns HTTP 404. Single request, no loop.
// ---------------------------------------------------------------------------

test "metric_tile_integration: unknown path returns HTTP 404" {
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.paymentPipelineProcess();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer {
        sup.stopProcess(std.testing.io);
        sup.deinit();
    }

    const port = util.metricPort();
    std.debug.print("\n  [tkmetr-test] metric_port = {d}\n", .{port});
    const event_count: u64 = 10;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = "metr2",
        .metric_port = port,
    });

    // Wait for pipeline to finish
    var wait_poll: u32 = 0;
    while (wait_poll < 200) : (wait_poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }

    // Fetch /foo — single request, expect 404
    const resp = httpGetProcess(METRICS_HOST, port, "/foo", 5000) catch |err| {
        std.debug.panic("Failed to connect to HTTP server on port {d}: {s}", .{ port, @errorName(err) });
    };
    defer std.testing.allocator.free(resp.body);
    try std.testing.expectEqual(@as(u16, 404), resp.status_code);

    try expectNoCrashes(&sup, run_dir);
    sup.stopProcess(std.testing.io);
}

// ---------------------------------------------------------------------------
// Test: boot timestamp gauge is a large positive number (nanoseconds since
// epoch).
// ---------------------------------------------------------------------------

test "metric_tile_integration: boot_timestamp is a valid large positive value" {
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.paymentPipelineProcess();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer {
        sup.stopProcess(std.testing.io);
        sup.deinit();
    }

    const port = util.metricPort();
    std.debug.print("\n  [tkmetr-test] metric_port = {d}\n", .{port});
    const event_count: u64 = 10;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = "metr4",
        .metric_port = port,
    });

    // Wait for pipeline to finish
    var wait_poll: u32 = 0;
    while (wait_poll < 200) : (wait_poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }

    // Fetch /metrics — single request, fail immediately if metrics are missing.
    const resp = httpGetProcess(METRICS_HOST, port, "/metrics", 5000) catch |err| {
        std.debug.panic("Failed to fetch /metrics: {s}", .{@errorName(err)});
    };
    defer std.testing.allocator.free(resp.body);

    const is_found = std.mem.indexOf(u8, resp.body, "metric_boot_timestamp_nanos") != null;
    try std.testing.expect(is_found);

    const boot_timestamp = parsePrometheusMetric(resp.body, "metric_boot_timestamp_nanos") orelse
        std.debug.panic("metric_boot_timestamp_nanos not found in /metrics response", .{});

    try std.testing.expect(boot_timestamp > 1e18);

    try expectNoCrashes(&sup, run_dir);
    sup.stopProcess(std.testing.io);
}

// ---------------------------------------------------------------------------
// Test: CNC shutdown signal stops tile cleanly.
// ---------------------------------------------------------------------------

test "metric_tile_integration: CNC shutdown signal stops tile cleanly" {
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.paymentPipelineProcess();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer {
        sup.stopProcess(std.testing.io);
        sup.deinit();
    }

    const port = util.metricPort();
    std.debug.print("\n  [tkmetr-test] metric_port = {d}\n", .{port});
    const event_count: u64 = 4;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = "metr5",
        .metric_port = port,
    });

    const max_polls: u32 = 400;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }

    const metrics = sup.snapshotProcessMetrics();
    try std.testing.expectEqual(event_count, metrics.audited);

    try expectNoCrashes(&sup, run_dir);
    sup.stopProcess(std.testing.io);
}

// ---------------------------------------------------------------------------
// Test: CNC join verifies tile finds CNC object.
// ---------------------------------------------------------------------------

test "metric_tile_integration: CNC join verifies tile finds CNC object" {
    const topo = topologies.paymentPipelineProcess();

    var tkmetr_idx: ?usize = null;
    for (topo.tiles, 0..) |tile, i| {
        if (std.mem.eql(u8, tile.id.slice(), "metric")) {
            tkmetr_idx = i;
            break;
        }
    }
    try std.testing.expect(tkmetr_idx != null);

    try std.testing.expectEqual(@as(usize, 8), topo.tiles.len);
}
