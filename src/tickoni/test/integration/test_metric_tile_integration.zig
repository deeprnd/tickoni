/// v2.23-m: Integration tests for the metric tile (tkmetr) lifecycle.
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

const std = @import("std");
const c_abi = @import("c_abi");
const runtime = @import("runtime");
const supervisor_mod = @import("supervisor");
const topologies = @import("topologies");
const util = @import("util");

const Supervisor = supervisor_mod.Supervisor;

const METRICS_HOST = "127.0.0.1";



// ---------------------------------------------------------------------------
// HTTP helpers — raw TCP client that reads until the server closes the
// connection. std.http.Client blocks forever on HTTP/1.0 responses
// without Content-Length, which is exactly what fd_http_server sends.
//
// IMPORTANT: the caller owns resp.body and must free it.
// ---------------------------------------------------------------------------

const HttpResponse = struct {
    status_code: u16,
    body: []u8,
};

fn httpGet(io: std.Io, host: []const u8, port: u16, path: []const u8) anyerror!HttpResponse {
    const req = try std.fmt.allocPrint(
        std.testing.allocator,
        "GET {s} HTTP/1.1\r\nHost: {s}:{d}\r\nConnection: close\r\n\r\n",
        .{ path, host, port },
    );
    defer std.testing.allocator.free(req);

    var address = std.Io.net.IpAddress.parse(host, port) catch unreachable;
    var stream = try std.Io.net.IpAddress.connect(&address, io, .{ .mode = .stream, .protocol = .tcp });
    defer stream.socket.close(io);

    const fd = @as(c_int, @intCast(stream.socket.handle));

    var written: usize = 0;
    while (written < req.len) {
        const result = std.posix.system.write(
            fd,
            req[written..].ptr,
            req.len - written,
        );
        if (result < 0) return @errorFromInt(@as(u16, @intCast(-@as(c_int, @intCast(result)))));
        const n = @as(usize, @intCast(result));
        if (n == 0) return error.WriteFailed;
        written += n;
    }

    var read_buf: [256 * 1024]u8 = undefined;
    var total: usize = 0;
    while (total < read_buf.len) {
        const n = std.posix.read(fd, read_buf[total..]) catch |err| switch (err) {
            error.ConnectionResetByPeer => break,
            error.WouldBlock => break,
            else => return err,
        };
        if (n == 0) break;
        total += n;
    }

    if (total < 15) {
        std.testing.allocator.free(read_buf[0..total]);
        return error.InvalidResponse;
    }

    const response_text = read_buf[0..total];
    const body = try std.testing.allocator.dupe(u8, response_text);

    var it = std.mem.splitScalar(u8, body, '\n');
    const first_line = it.next() orelse {
        std.testing.allocator.free(body);
        return error.InvalidResponse;
    };
    const space1 = std.mem.indexOfScalar(u8, first_line, ' ') orelse {
        std.testing.allocator.free(body);
        return error.InvalidResponse;
    };
    const space2 = std.mem.indexOfScalar(u8, first_line[space1 + 1 ..], ' ') orelse {
        std.testing.allocator.free(body);
        return error.InvalidResponse;
    };
    const status_str = first_line[space1 + 1 .. space1 + 1 + space2];
    const status_code = std.fmt.parseInt(u16, status_str, 10) catch {
        std.testing.allocator.free(body);
        return error.InvalidResponse;
    };

    const header_end = std.mem.indexOf(u8, body, "\r\n\r\n") orelse {
        std.testing.allocator.free(body);
        return error.InvalidResponse;
    };
    const body_start = header_end + 4;
    const body_data = try std.testing.allocator.dupe(u8, body[body_start..]);
    std.testing.allocator.free(body);

    return HttpResponse{ .status_code = status_code, .body = body_data };
}

// ---------------------------------------------------------------------------
// Retry loop — call httpGet with bounded retries.
// ---------------------------------------------------------------------------

fn httpGetWithRetry(io: std.Io, host: []const u8, port: u16, path: []const u8, max_attempts: u8) anyerror!HttpResponse {
    var attempt: u8 = 0;
    while (attempt < max_attempts) : (attempt += 1) {
        if (httpGet(io, host, port, path)) |resp| {
            return resp;
        } else |_| {}
        util.process.sleepNanos(100 * std.time.ns_per_ms);
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
        if (std.mem.endsWith(u8, metric_name, "_total")) {
            metric_name = metric_name[0 .. metric_name.len - "_total".len];
        }
        if (!std.mem.eql(u8, metric_name, name)) continue;

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
            std.testing.allocator, "{s}/logs", .{run_dir},
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

    // Verify tkmetr tile exists in topology
    var found_metric_tile = false;
    for (topo.tiles) |tile| {
        if (std.mem.eql(u8, tile.id.slice(), "tkmetr")) {
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
// metric names. Bounded to 50 iterations (500ms) for a smoke test.
//
// NOTE: the tile name in Prometheus output is "metric" (from fd_tile_metric.name),
// not "tkmetr" (the Tickoni tile ID).
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

    // Now fetch /metrics and verify Prometheus content
    var captured: ?[]u8 = null;
    errdefer if (captured) |b| std.testing.allocator.free(b);

    var attempts: u8 = 0;
    while (attempts < 10) : (attempts += 1) {
        const resp = httpGet(std.testing.io, METRICS_HOST, port, "/metrics") catch {
            util.process.sleepNanos(10 * std.time.ns_per_ms);
            continue;
        };
        const has_required =
            std.mem.indexOf(u8, resp.body, "metric_boot_timestamp_nanos") != null and
            std.mem.indexOf(u8, resp.body, "metric_conn_active") != null and
            std.mem.indexOf(u8, resp.body, "kind=\"metric\"") != null;

        if (has_required) {
            captured = resp.body;
            std.testing.allocator.free(resp.body);
            break;
        } else {
            std.testing.allocator.free(resp.body);
        }
    }

    try std.testing.expect(captured != null);
    const body = captured orelse unreachable;

    try std.testing.expect(body.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, body, "# HELP") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "# TYPE") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "metric_boot_timestamp_nanos") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "metric_conn_active") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "kind=\"metric\"") != null);

    // Verify bytes read > 0 (tile processed events).
    const bytes_read = parsePrometheusMetric(body, "metric_bytes_read");
    try std.testing.expect(bytes_read != null);
    try std.testing.expect(bytes_read.? > 0);

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
    const event_count: u64 = 10;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = "metr2",
        .metric_port = port,
    });

    // Wait for pipeline to finish, then check 404.
    var wait_poll: u32 = 0;
    while (wait_poll < 200) : (wait_poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }

    const resp = httpGetWithRetry(std.testing.io, METRICS_HOST, port, "/foo", 5) catch unreachable;
    try std.testing.expectEqual(@as(u16, 404), resp.status_code);
    std.testing.allocator.free(resp.body);

    try expectNoCrashes(&sup, run_dir);
    sup.stopProcess(std.testing.io);
}

// ---------------------------------------------------------------------------
// Test: boot timestamp gauge is a large positive number (nanoseconds since
// epoch). Bounded to 10 iterations (1s).
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

    // Fetch metrics once — boot timestamp should always be present
    const resp = httpGetWithRetry(std.testing.io, METRICS_HOST, port, "/metrics", 5) catch unreachable;
    const ts = parsePrometheusMetric(resp.body, "metric_boot_timestamp_nanos") orelse
        std.debug.panic("metric_boot_timestamp_nanos not found in /metrics response", .{});
    std.testing.allocator.free(resp.body);

    // Nanoseconds since epoch in 2025+ is roughly 1.7e18+.
    try std.testing.expect(ts > 1000000000000000000);

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
        if (std.mem.eql(u8, tile.id.slice(), "tkmetr")) {
            tkmetr_idx = i;
            break;
        }
    }
    try std.testing.expect(tkmetr_idx != null);

    try std.testing.expectEqual(@as(usize, 8), topo.tiles.len);
}
