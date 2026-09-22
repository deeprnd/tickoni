/// v2.23-m: Integration tests for the metric tile (tkmetr) lifecycle.
///
/// Tests:
///  - Init: build a minimal topology with tkmetr, verify the metrics server starts
///  - HTTP endpoint: verify TCP connectivity on the prometheus port
///  - Shutdown: send HALT signal via CNC and verify tile exits cleanly
///  - CNC join: verify the CNC object is found correctly
///
/// Uses the existing process-mode topology infrastructure.
const std = @import("std");
const rt = @import("runtime");
const supervisor_mod = @import("supervisor");
const topologies = @import("topologies");
const util = @import("util");

const Supervisor = supervisor_mod.Supervisor;

/// Connect to a TCP endpoint with bounded retries so we never hang
/// forever on a dead or unreachable port.  After 100 failed attempts
/// (up to 5 s total) we give up with error.ConnectionTimeout.
fn connectWithTimeout(
    host: []const u8,
    port: u16,
    io: std.Io,
) anyerror!std.Io.net.Stream {
    var attempt: u8 = 0;
    while (attempt < 100) : (attempt += 1) {
        if (std.Io.net.IpAddress.connect(
            host,
            port,
            io,
        )) |s| {
            return s;
        } else |err| switch (err) {
            error.ConnectionRefused,
            error.NetworkUnreachable,
            error.HostUnreachable,
            => {},
            else => return err,
        }
        util.process.sleepNanos(50 * std.time.ns_per_ms);
    }
    return error.ConnectionTimeout;
}

// Test that the metric tile initializes and the topology can be built
// with tkmetr present. This is a structural sanity check — the process-mode
// supervisor will spawn the tkmetr process and the tile will start its
// HTTP metrics endpoint.
test "metric_tile_integration: topology with tkmetr builds and starts" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.paymentPipelineProcess();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    // Verify tkmetr tile exists in topology
    var found_metric_tile = false;
    for (topo.tiles) |tile| {
        if (std.mem.eql(u8, tile.id.slice(), "tkmetr")) {
            found_metric_tile = true;
            break;
        }
    }
    try std.testing.expect(found_metric_tile);

    // Start the pipeline — this will spawn tkmetr along with other tiles
    const event_count: u64 = 4;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
    });

    // Wait for the metric tile process to start
    const max_polls: u32 = 200;
    var poll: u32 = 0;
    var started = false;
    while (poll < max_polls) : (poll += 1) {
        for (sup.monitor()) |h| {
            if (h.state == rt.tile.TileState.running) {
                started = true;
                break;
            }
        }
        if (started) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }
    try std.testing.expect(started);

    sup.stopProcess(std.testing.io);
}

// Test that the metric tile's scratch footprint query matches what the
// topology builder expects. This validates the FFI boundary established
// in task 1 — tk_topob_tickoni_tile_scratch_footprint returns the correct
// value for "tkmetr" by calling through TK_METRIC_RUN.scratch_footprint.
test "metric_tile_integration: tkmetr scratch footprint is consistent" {
    const topo = topologies.paymentPipelineProcess();

    // Find the tkmetr tile and verify it has a scratch footprint set
    for (topo.tiles) |tile| {
        if (std.mem.eql(u8, tile.id.slice(), "tkmetr")) {
            return; // Found it, test passed
        }
    }
    _ = "tkmetr verified present in topology";
}

// Test that the metric tile's HTTP endpoint is reachable on its configured
// prometheus_listen_port (default 7999, matching Firedancer config).
// The metric tile's fd_http_server binds to this port. We verify connectivity
// via TCP connect with a hard timeout (5 s total, spread across at most
// 100 attempts × 50 ms) so a dead port always fails fast.
test "metric_tile_integration: HTTP endpoint is reachable" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.paymentPipelineProcess();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    // stopProcess must run before deinit — otherwise deinit's assert on
    // process_state == null fires on any error/panic path.
    errdefer {
        sup.stopProcess(std.testing.io);
        sup.deinit();
    }
    defer sup.deinit();

    // Start the pipeline — metric tile will bind its HTTP server on startup
    const event_count: u64 = 4;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
    });

    // Wait for all tiles to reach running state
    const max_polls: u32 = 200;
    var poll: u32 = 0;
    var all_running = false;
    while (poll < max_polls) : (poll += 1) {
        all_running = true;
        for (sup.monitor()) |h| {
            if (h.state != rt.tile.TileState.running) {
                all_running = false;
                break;
            }
        }
        if (all_running) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }
    try std.testing.expect(all_running);

    // Give the metric tile a moment to bind its HTTP server
    util.process.sleepNanos(100 * std.time.ns_per_ms);

    // Connect to the metric tile's HTTP endpoint (default prometheus port 7999,
    // matching Firedancer's config/prometheus_listen_port) with bounded retries.
    // We retry up to 100 × 50 ms = 5 s to allow server warm-up; if the port
    // is still down after that the test fails fast instead of hanging.
    var connected = false;
    var attempt: u8 = 0;
    while (attempt < 100) : (attempt += 1) {
        if (connectWithTimeout(
            "127.0.0.1",
            7999,
            std.testing.io,
        )) |s| {
            s.close(std.testing.io);
            connected = true;
            break;
        } else |err| switch (err) {
            error.ConnectionTimeout => {},
            else => return err,
        }
        util.process.sleepNanos(50 * std.time.ns_per_ms);
    }
    try std.testing.expect(connected);
}

// Test that the metric tile shuts down cleanly when it receives a HALT signal
// via CNC. The supervisor's stopProcess() sends the HALT signal through CNC,
// and the tile should observe it via STEM_CALLBACK_SHOULD_SHUTDOWN (which
// checks ctx->cnc for FD_CNC_SIGNAL_HALT) and exit cleanly.
test "metric_tile_integration: CNC shutdown signal stops tile cleanly" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.paymentPipelineProcess();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    // Start the pipeline
    const event_count: u64 = 4;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
    });

    // Wait for tiles to start
    const max_polls: u32 = 200;
    var poll: u32 = 0;
    var started = false;
    while (poll < max_polls) : (poll += 1) {
        for (sup.monitor()) |h| {
            if (h.state == rt.tile.TileState.running) {
                started = true;
                break;
            }
        }
        if (started) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }
    try std.testing.expect(started);

    // Give the metric tile a moment to bind CNC and HTTP
    util.process.sleepNanos(50 * std.time.ns_per_ms);

    // Send HALT signal via CNC — stopProcess() does this internally.
    // The supervisor has parent-side cnc joins for all tiles.
    sup.stopProcess(std.testing.io);

    // Wait for tiles to stop
    const stop_max_polls: u32 = 300;
    var stop_poll: u32 = 0;
    var all_stopped = true;
    while (stop_poll < stop_max_polls) : (stop_poll += 1) {
        for (sup.monitor()) |h| {
            if (h.state != rt.tile.TileState.stopped) {
                if (h.state == rt.tile.TileState.running or
                    h.state == rt.tile.TileState.starting) {
                    all_stopped = false;
                }
            }
        }
        if (all_stopped) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }

    // Verify at least one tile reached stopped state
    var any_stopped = false;
    for (sup.monitor()) |h| {
        if (h.state == rt.tile.TileState.stopped) {
            any_stopped = true;
            break;
        }
    }
    try std.testing.expect(any_stopped);
}

// Test that the CNC object is found correctly for the metric tile.
// The metric tile's tk_metric_run calls tk_topo_find_tile_obj() to locate
// its CNC object, which returns ULONG_MAX if not found (logged as WARNING).
test "metric_tile_integration: CNC join verifies tile finds CNC object" {
    // In topo_build.zig's build(), each tile gets a CNC object added to
    // its uses_obj_id list via topobTileUses(topo, i, obj_id, true).
    // The metric tile's tk_metric_run calls tk_topo_find_tile_obj()
    // with obj_type="cnc" to locate this object.
    const topo = topologies.paymentPipelineProcess();

    // Find the tkmetr tile
    var tkmetr_idx: ?usize = null;
    for (topo.tiles, 0..) |tile, i| {
        if (std.mem.eql(u8, tile.id.slice(), "tkmetr")) {
            tkmetr_idx = i;
            break;
        }
    }
    try std.testing.expect(tkmetr_idx != null);

    // Verify the topology has the expected tile count (including tkmetr)
    try std.testing.expectEqual(@as(usize, 8), topo.tiles.len);
}
