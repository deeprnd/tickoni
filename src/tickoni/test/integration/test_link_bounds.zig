/// v2.14.S1 M6 fail-closed matrix (T14): runtime link dcache bounds check and
/// backpressure visibility, exercised directly against a real Tango
/// workspace (single process — no tile spawn needed, since these are
/// producer/consumer-local behaviors, not process-isolation behaviors).
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const util = @import("util");

fn attachScratchWksp(io: std.Io, run_dir: []const u8, name: [*:0]const u8) !*c_abi.wksp.Wksp {
    try rt.boot.bootWithSyntheticArgv(run_dir);

    var run_dir_handle = try std.Io.Dir.cwd().createDirPathOpen(io, run_dir, .{});
    run_dir_handle.close(io);
    const normal_dir = try std.fmt.allocPrint(std.testing.allocator, "{s}/.normal", .{run_dir});
    defer std.testing.allocator.free(normal_dir);
    var normal_dir_handle = try std.Io.Dir.cwd().createDirPathOpen(io, normal_dir, .{});
    normal_dir_handle.close(io);

    if (c_abi.wksp.wkspExistsNamed(name)) {
        _ = c_abi.wksp.wkspDeleteNamed(name);
    }
    var sub_page_cnt = [_]usize{256};
    var sub_cpu_idx = [_]usize{0};
    const rc = c_abi.wksp.wkspNewNamed(name, c_abi.wksp.shmem_normal_page_sz, 1, &sub_page_cnt, &sub_cpu_idx, 0o600, 1, 32);
    if (rc != 0) return error.WkspCreateFailed;
    return c_abi.wksp.wkspAttach(name) orelse error.WkspAttachFailed;
}

test "link_bounds: publish larger than the link's mtu fails closed instead of overrunning the dcache slot" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const wksp = try attachScratchWksp(std.testing.io, run_dir, "tkbnd0");
    defer {
        _ = c_abi.wksp.wkspDetach(wksp);
        _ = c_abi.wksp.wkspDeleteNamed("tkbnd0");
        c_abi.boot.halt();
    }

    const handles = try rt.link.create(wksp, 4, 8);
    var producer = try rt.link.Producer.join(wksp, handles);
    defer producer.leave();

    var stop_flag = std.atomic.Value(bool).init(false);
    var backpressure_waits = std.atomic.Value(u64).init(0);
    const oversized_payload = std.mem.zeroes([16]u8); // mtu is 8

    try std.testing.expectError(
        error.PayloadTooLarge,
        producer.publish(&oversized_payload, &backpressure_waits, &stop_flag, null),
    );
}

test "link_bounds: joining a zeroed (missing) link handle set fails closed" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const wksp = try attachScratchWksp(std.testing.io, run_dir, "tkbnd1");
    defer {
        _ = c_abi.wksp.wkspDetach(wksp);
        _ = c_abi.wksp.wkspDeleteNamed("tkbnd1");
        c_abi.boot.halt();
    }

    // A never-created LinkHandles set (all gaddrs 0) simulates a missing
    // mcache/dcache/fseq object — joining must fail closed, not dereference
    // an invalid workspace address.
    const missing = rt.link.LinkHandles{};
    try std.testing.expectError(error.McacheLaddrFailed, rt.link.Producer.join(wksp, missing));
    try std.testing.expectError(error.McacheLaddrFailed, rt.link.Consumer.join(wksp, missing));
}

test "link_bounds: producer backpressures and counts waits when the consumer does not advance" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const wksp = try attachScratchWksp(std.testing.io, run_dir, "tkbnd2");
    defer {
        _ = c_abi.wksp.wkspDetach(wksp);
        _ = c_abi.wksp.wkspDeleteNamed("tkbnd2");
        c_abi.boot.halt();
    }

    // Depth 2: the 3rd publish must block on backpressure since no consumer
    // ever advances the fseq in this test.
    const handles = try rt.link.create(wksp, 2, 8);
    var producer = try rt.link.Producer.join(wksp, handles);
    defer producer.leave();

    var stop_flag = std.atomic.Value(bool).init(false);
    var backpressure_waits = std.atomic.Value(u64).init(0);
    const payload = [_]u8{ 1, 2, 3, 4 };

    try producer.publish(&payload, &backpressure_waits, &stop_flag, null);
    try producer.publish(&payload, &backpressure_waits, &stop_flag, null);
    try std.testing.expectEqual(@as(u64, 0), backpressure_waits.load(.acquire));

    // A second thread flips stop after giving the producer a real chance to
    // spin on backpressure at least once, so publish() observes Stopped
    // instead of blocking this test forever.
    const Flipper = struct {
        fn run(flag: *std.atomic.Value(bool)) void {
            util.process.sleepNanos(20 * std.time.ns_per_ms);
            flag.store(true, .release);
        }
    };
    var flipper = try std.Thread.spawn(.{}, Flipper.run, .{&stop_flag});
    defer flipper.join();

    try std.testing.expectError(error.Stopped, producer.publish(&payload, &backpressure_waits, &stop_flag, null));
    try std.testing.expect(backpressure_waits.load(.acquire) > 0);
}
