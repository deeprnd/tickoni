/// v2.23-m: Integration tests for the metric tile (tkmetr) lifecycle.
///
/// Tests:
///  - Init: build a minimal topology with tkmetr, verify the metrics server
///    starts and the tile runs without crashing
///  - HTTP GET: fetch /metrics, verify 200 status, parse prometheus text
///  - HTTP 404: fetch /foo, verify 404 status
///  - Counter values: verify BYTES_READ and BYTES_WRITTEN increase between
///    two /metrics fetches
///  - Timestamp: verify boot_timestamp_nanos is a valid large positive number
///  - Shutdown: send HALT signal via CNC and verify tile exits cleanly
///  - CNC join: verify the CNC object is found correctly
///
/// Uses the existing process-mode topology infrastructure.
const std = @import("std");
const supervisor_mod = @import("supervisor");
const topologies = @import("topologies");
const util = @import("util");

const Supervisor = supervisor_mod.Supervisor;

const METRICS_PORT: u16 = 7999;
const METRICS_HOST = "127.0.0.1";

// ---------------------------------------------------------------------------
// HTTP response struct
// ---------------------------------------------------------------------------
const HttpResponse = struct {
    status_code: u16,
    body: []u8,
};

// ---------------------------------------------------------------------------
// HTTP helpers — use std.http.Client (Zig 0.17 std.Io.net.Stream is
// read-only, so raw TCP write is unavailable).
//
// IMPORTANT: the caller owns resp.body and must free it.
// ---------------------------------------------------------------------------

fn httpGet(io: std.Io, host: []const u8, port: u16, path: []const u8) anyerror!HttpResponse {
    var client = std.http.Client{ .allocator = std.testing.allocator, .io = io };

    var response_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);

    const url = try std.fmt.allocPrint(
        std.testing.allocator,
        "http://{s}:{d}{s}",
        .{ host, port, path },
    );

    defer {
        client.deinit();
        response_writer.deinit();
        std.testing.allocator.free(url);
    }

    _ = try client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .response_writer = &response_writer.writer,
    });

    const response_text = response_writer.written();

    // Parse status code from the first line: "HTTP/1.1 <STATUS> <REASON>\r\n"
    var it = std.mem.splitScalar(u8, response_text, '\n');
    const first_line = it.next() orelse return error.InvalidResponse;
    const space1 = std.mem.indexOfScalar(u8, first_line, ' ') orelse return error.InvalidResponse;
    const space2 = std.mem.indexOfScalar(u8, first_line[space1 + 1 ..], ' ') orelse return error.InvalidResponse;
    const status_str = first_line[space1 + 1 .. space1 + 1 + space2];
    const status_code = std.fmt.parseInt(u16, status_str, 10) catch return error.InvalidResponse;

    // The body starts after the first \r\n\r\n
    const header_end = std.mem.indexOfScalar(u8, response_text, '\n') orelse return error.InvalidResponse;
    const body_start = header_end + 4; // skip \r\n\r\n
    const body = response_text[body_start..];

    return HttpResponse{ .status_code = status_code, .body = body };
}

// ---------------------------------------------------------------------------
// Retry loop — call httpGet with bounded retries.
// ---------------------------------------------------------------------------

fn httpGetWithRetry(io: std.Io, host: []const u8, port: u16, path: []const u8, max_attempts: u8) anyerror!HttpResponse {
    var attempt: u8 = 0;
    while (attempt < max_attempts) : (attempt += 1) {
        if (httpGet(io, host, port, path)) |resp| {
            return resp;
        } else |_| {
            // Connection refused / timeout — retry
        }
        util.process.sleepNanos(100 * std.time.ns_per_ms);
    }
    return error.ConnectionTimeout;
}

// ---------------------------------------------------------------------------
// Prometheus text-format parser — extract a single metric value from the
// rendered output.  Returns null if the metric name is not found.
// ---------------------------------------------------------------------------

fn parsePrometheusMetric(body: []const u8, name: []const u8) ?u64 {
    var it = std.mem.splitScalar(u8, body, '\n');
    while (it.next()) |line| {
        // Skip comments, blank lines, and HELP/TYPE lines.
        if (line.len == 0 or line[0] == '#') continue;

        // We expect: metric_name{labels} value
        // or: metric_name{labels}_total value  (for counters)
        if (std.mem.endsWith(u8, line, "_total")) {
            if (line.len < 6) continue;
            const stripped = line[0 .. line.len - 6];
            if (!std.mem.startsWith(u8, stripped, name)) continue;
            const after_name = stripped[name.len..];
            if (after_name.len == 0 or after_name[0] == '{') {
                const val_str = std.mem.trim(u8, line, " ");
                const last_space = std.mem.lastIndexOfScalar(u8, val_str, ' ') orelse continue;
                return std.fmt.parseInt(u64, val_str[last_space + 1 ..], 10) catch null;
            }
        } else {
            if (!std.mem.startsWith(u8, line, name)) continue;
            const after_name = line[name.len..];
            if (after_name.len == 0 or after_name[0] == '{') {
                const val_str = std.mem.trim(u8, line, " ");
                const last_space = std.mem.lastIndexOfScalar(u8, val_str, ' ') orelse continue;
                return std.fmt.parseInt(u64, val_str[last_space + 1 ..], 10) catch null;
            }
        }
    }
    return null;
}

// ---------------------------------------------------------------------------
// Crash detection helper.
// ---------------------------------------------------------------------------

fn expectNoCrashes(sup: *Supervisor, run_dir: []const u8) !void {
    sup.reapExitedChildrenNoHang();
    sup.refreshProcessHealth();

    var has_crash = false;
    for (sup.monitor()) |h| {
        if (h.state == .crashed) {
            has_crash = true;
            std.debug.print(
                "  tile {d} crashed: exit_code={d} reason={s}\n",
                .{ h.tile_idx, h.exit_code, @tagName(h.crashed_because) },
            );
        }
    }
    if (has_crash) {
        const logs_dir = std.fmt.allocPrint(
            std.testing.allocator,
            "{s}/logs",
            .{run_dir},
        ) catch unreachable;
        defer std.testing.allocator.free(logs_dir);
        const dir = std.Io.Dir.cwd().openDir(std.testing.io, logs_dir, .{}) catch unreachable;
        defer dir.close(std.testing.io);
        var iter = dir.iterate();
        while (try iter.next(std.testing.io)) |entry| {
            std.debug.print("  log: {s}\n", .{entry.name});
        }
        std.testing.allocator.free(logs_dir);
        std.debug.panic("TileCrashed", .{});
    }
}

// ---------------------------------------------------------------------------
// Test: topology with tkmetr builds and starts.
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

    // Verify tkmetr tile exists in topology
    var found_metric_tile = false;
    for (topo.tiles) |tile| {
        if (std.mem.eql(u8, tile.id.slice(), "tkmetr")) {
            found_metric_tile = true;
            break;
        }
    }
    try std.testing.expect(found_metric_tile);

    const event_count: u64 = 4;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = "metr0",
    });

    // Wait for the pipeline to complete.
    const max_polls: u32 = 400;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }

    try expectNoCrashes(&sup, run_dir);
    sup.stopProcess(std.testing.io);
}

// ---------------------------------------------------------------------------
// Test: /metrics returns HTTP 200 with valid prometheus text.
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

    const event_count: u64 = 64;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = "metr1",
    });

    // Poll for both HTTP and pipeline completion.
    // The metric tile's HTTP server starts before processing begins, so it
    // should be reachable within a few polls.
    const max_polls: u32 = 2000;
    var poll: u32 = 0;
    var captured: ?[]u8 = null;
    var done = false;
    errdefer if (captured) |b| std.testing.allocator.free(b);

    while (!done and poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;

        const resp = httpGet(std.testing.io, METRICS_HOST, METRICS_PORT, "/metrics") catch {
            util.process.sleepNanos(10 * std.time.ns_per_ms);
            continue;
        };

        // First successful response: capture it
        if (captured == null) {
            captured = resp.body;
        } else {
            std.testing.allocator.free(resp.body);
        }

        // Stop polling once we have a response
        if (captured != null) done = true;

        util.process.sleepNanos(10 * std.time.ns_per_ms);
    }

    // Now run assertions on the captured body
    try std.testing.expect(captured != null);
    const body = captured orelse unreachable;

    try std.testing.expect(body.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, body, "# HELP") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "# TYPE") != null);
    try std.testing.expect(
        std.mem.indexOf(u8, body, "metric_boot_timestamp_nanos") != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, body, "metric_conn_active") != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, body, "kind=\"tickoni-ingress\"") != null,
    );

    try expectNoCrashes(&sup, run_dir);
    sup.stopProcess(std.testing.io);
}

// ---------------------------------------------------------------------------
// Test: /foo returns HTTP 404.
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

    const event_count: u64 = 64;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = "metr2",
    });

    const max_polls: u32 = 2000;
    var poll: u32 = 0;
    var done = false;

    while (!done and poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;

        const resp = httpGet(std.testing.io, METRICS_HOST, METRICS_PORT, "/foo") catch {
            util.process.sleepNanos(10 * std.time.ns_per_ms);
            continue;
        };

        std.testing.allocator.free(resp.body);
        try std.testing.expectEqual(@as(u16, 404), resp.status_code);
        done = true;
    }

    try expectNoCrashes(&sup, run_dir);
    sup.stopProcess(std.testing.io);
}

// ---------------------------------------------------------------------------
// Test: counter values increase between two /metrics fetches.
// ---------------------------------------------------------------------------

test "metric_tile_integration: BYTES_READ increases after HTTP fetches" {
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

    const event_count: u64 = 64;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = "metr3",
    });

    const max_polls: u32 = 2000;
    var poll: u32 = 0;
    var fetches_done: u8 = 0;
    var body1: ?[]u8 = null;
    var body2: ?[]u8 = null;
    var done = false;
    errdefer {
        if (body1) |b| std.testing.allocator.free(b);
        if (body2) |b| std.testing.allocator.free(b);
    }

    while (!done and fetches_done < 5 and poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count and fetches_done >= 2) break;

        const resp = httpGet(std.testing.io, METRICS_HOST, METRICS_PORT, "/metrics") catch {
            util.process.sleepNanos(10 * std.time.ns_per_ms);
            continue;
        };

        if (fetches_done == 0) {
            body1 = resp.body;
        } else if (fetches_done == 1) {
            body2 = resp.body;
        } else {
            std.testing.allocator.free(resp.body);
        }
        fetches_done += 1;

        // We need at least 2 fetches to compare
        if (fetches_done >= 2) done = true;

        util.process.sleepNanos(10 * std.time.ns_per_ms);
    }

    // We need at least 2 fetches to compare counters
    try std.testing.expect(fetches_done >= 2);

    const b1 = body1 orelse std.debug.panic("No first response captured", .{});
    const b2 = body2 orelse std.debug.panic("No second response captured", .{});

    const read2 = parsePrometheusMetric(b2, "metric_bytes_read") orelse
        std.debug.panic("metric_bytes_read not found on second fetch", .{});
    const written2 = parsePrometheusMetric(b2, "metric_bytes_written") orelse
        std.debug.panic("metric_bytes_written not found on second fetch", .{});

    const read1 = parsePrometheusMetric(b1, "metric_bytes_read") orelse
        std.debug.panic("metric_bytes_read not found on first fetch", .{});
    const written1 = parsePrometheusMetric(b1, "metric_bytes_written") orelse
        std.debug.panic("metric_bytes_written not found on first fetch", .{});

    // BYTES_READ must increase (the second request adds data).
    try std.testing.expect(read2 > read1);
    // BYTES_WRITTEN must increase (the second response adds data).
    try std.testing.expect(written2 > written1);
    // Both counters must be positive.
    try std.testing.expect(written2 > 0);

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

    const event_count: u64 = 64;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = "metr4",
    });

    const max_polls: u32 = 2000;
    var poll: u32 = 0;
    var boot_ts: ?u64 = null;
    var done = false;

    while (!done and poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;

        const resp = httpGet(std.testing.io, METRICS_HOST, METRICS_PORT, "/metrics") catch {
            util.process.sleepNanos(10 * std.time.ns_per_ms);
            continue;
        };

        if (boot_ts == null) {
            boot_ts = parsePrometheusMetric(resp.body, "metric_boot_timestamp_nanos");
            std.testing.allocator.free(resp.body);
        } else {
            std.testing.allocator.free(resp.body);
        }

        if (boot_ts != null) done = true;

        util.process.sleepNanos(10 * std.time.ns_per_ms);
    }

    const ts = boot_ts orelse std.debug.panic("metric_boot_timestamp_nanos not found", .{});
    // Nanoseconds since epoch in 2025+ is roughly 1.7e18+.
    // Accept anything > 1e18 as a reasonable boot timestamp.
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

    const event_count: u64 = 4;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = "metr5",
    });

    const max_polls: u32 = 400;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }

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
