/// tkings producer lifecycle proof through the real supervisor and stem child.
const std = @import("std");
const rt = @import("runtime");
const supervisor_mod = @import("supervisor");
const topologies = @import("topologies");
const util = @import("util");

test "tkings_integration: child launches through __stem-run and halts cleanly" {
    if (@import("builtin").target.os.tag != .linux) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];

    var sup = try supervisor_mod.Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    var workspace_buf: [16]u8 = undefined;
    // Zero is an idle source, so the child remains alive for argv inspection
    // and must stop on the CNC HALT sent by stopProcess.
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = 0,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = util.nextWorkspaceName(&workspace_buf),
        .metric_port = util.nextMetricPort(),
    });

    var ingest_idx: usize = 0;
    while (!sup.topo.tiles[ingest_idx].name.eql(rt.tile_ids.tkings)) : (ingest_idx += 1) {}
    const pid = sup.monitor()[ingest_idx].pid orelse return error.IngestChildHasNoPid;
    var cmdline_path_buf: [64]u8 = undefined;
    const cmdline_path = try std.fmt.bufPrint(&cmdline_path_buf, "/proc/{d}/cmdline", .{pid});

    var found_stem = false;
    var found_tile = false;
    var poll: u32 = 0;
    while (poll < 400) : (poll += 1) {
        var file = std.Io.Dir.cwd().openFile(std.testing.io, cmdline_path, .{}) catch {
            util.process.sleepNanos(5 * std.time.ns_per_ms);
            continue;
        };
        var cmdline: [4096]u8 = undefined;
        const len = file.readPositionalAll(std.testing.io, &cmdline, 0) catch 0;
        file.close(std.testing.io);
        var args = std.mem.splitScalar(u8, cmdline[0..len], 0);
        while (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "__stem-run")) found_stem = true;
            if (std.mem.eql(u8, arg, "__tile-run")) found_tile = true;
        }
        if (found_stem or found_tile) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }
    try std.testing.expect(found_stem);
    try std.testing.expect(!found_tile);
    try std.testing.expectEqual(@as(u64, 0), sup.snapshotProcessMetrics().produced);
    try sup.stopProcess(std.testing.io);
    try std.testing.expectEqual(rt.tile.TileState.stopped, sup.monitor()[ingest_idx].state);
}
