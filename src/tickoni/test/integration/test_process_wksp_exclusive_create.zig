/// Integration test: a named workspace is created exclusively across processes.
///
/// Creating a workspace name that another process already holds must fail, the
/// way the POSIX backend's O_CREAT|O_EXCL does. If it succeeded, two
/// supervisors on one name would share, and the second would zero, the first's
/// live Tango links. Windows enforces this only across processes: a named
/// mapping the creator does not own is handed back as a success unless the
/// backend checks for it (fd_shmem_windows.c, fd_shmem_create_multi), so the
/// test needs a real second process: tk-wksp-probe, built under -Dtest.
///
/// The same test runs on every platform; nothing here branches on the OS.
const std = @import("std");
const builtin = @import("builtin");
const c_abi = @import("c_abi");
const runtime = @import("runtime");
const util = @import("util");
const codes = @import("wksp_probe_codes.zig");

const probe_exe = "build/zig-out/bin/tk-wksp-probe" ++ builtin.target.exeFileExt();
const probe_timeout_ns: i96 = 30 * std.time.ns_per_s;

/// Runs tk-wksp-probe: a second process that tries to create `name` on the
/// shmem path. Returns its exit code (see wksp_probe_codes.zig).
fn runProbe(shmem_path: []const u8, name: []const u8) !u8 {
    const result = try std.process.run(std.testing.allocator, std.testing.io, .{
        .argv = &.{ probe_exe, shmem_path, name },
        .timeout = .{ .duration = .{ .raw = .{ .nanoseconds = probe_timeout_ns }, .clock = .awake } },
    });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    switch (result.term) {
        .exited => |code| return code,
        else => {
            std.debug.print("\n[wksp-probe] abnormal exit: {any}\nstderr: {s}\n", .{ result.term, result.stderr });
            return error.ProbeDidNotExit;
        },
    }
}

/// A shmem path with the `.normal` directory the POSIX backend keeps its
/// workspace files in, booted for this process, and a fresh workspace name.
const Fixture = struct {
    tmp: util.TmpDir,
    path_buf: [std.fs.max_path_bytes]u8 = undefined,
    path_len: usize = 0,
    name_buf: [runtime.topo_build.concrete_workspace_name_cap]u8 = undefined,
    name_len: usize = 0,

    fn init(self: *Fixture) !void {
        self.tmp = util.tmpDir();
        errdefer self.tmp.cleanup();
        self.path_len = try self.tmp.dir.realPath(std.testing.io, &self.path_buf);
        var normal_buf: [std.fs.max_path_bytes]u8 = undefined;
        const normal = try std.fmt.bufPrint(&normal_buf, "{s}/.normal", .{self.shmemPath()});
        var normal_dir = try std.Io.Dir.cwd().createDirPathOpen(std.testing.io, normal, .{});
        normal_dir.close(std.testing.io);

        var ws_buf: [16]u8 = undefined;
        const concrete = try runtime.topo_build.concreteWorkspaceName(&self.name_buf, util.nextWorkspaceName(&ws_buf));
        self.name_len = concrete.len;

        try runtime.boot.bootLite(self.shmemPath(), "");
    }

    fn deinit(self: *Fixture) void {
        c_abi.boot.halt();
        self.tmp.cleanup();
    }

    fn shmemPath(self: *const Fixture) []const u8 {
        return self.path_buf[0..self.path_len];
    }

    fn name(self: *const Fixture) [:0]const u8 {
        return self.name_buf[0..self.name_len :0];
    }
};

/// Creates `name` in this process and joins it, as a running supervisor does.
fn hold(name: [*:0]const u8) !*c_abi.wksp.Wksp {
    const page_cnt = [_]usize{codes.page_cnt};
    const cpu_idx = [_]usize{0};
    try std.testing.expectEqual(c_abi.wksp.wksp_success, c_abi.wksp.wkspNewNamed(name, c_abi.wksp.shmem_normal_page_sz, 1, &page_cnt, &cpu_idx, 0o600, 1, 0));
    return c_abi.wksp.wkspAttach(name) orelse error.WkspAttachFailed;
}

/// Leaves a held name: detaches and deletes it.
fn release(wksp: *c_abi.wksp.Wksp, name: [*:0]const u8) void {
    _ = c_abi.wksp.wkspDetach(wksp);
    _ = c_abi.wksp.wkspDeleteNamed(name);
}

test "wksp_exclusive_create_integration: a workspace another process holds cannot be created again" {
    var fx: Fixture = undefined;
    try fx.init();
    defer fx.deinit();

    const held = try hold(fx.name());
    defer release(held, fx.name());

    try std.testing.expectEqual(codes.refused, try runProbe(fx.shmemPath(), fx.name()));
}

test "wksp_exclusive_create_integration: the probe can create a name nobody holds" {
    // The control for the refusal above: same probe, same shape, a free name.
    // Without it a probe that fails for any other reason would pass that test.
    var fx: Fixture = undefined;
    try fx.init();
    defer fx.deinit();

    try std.testing.expectEqual(codes.created, try runProbe(fx.shmemPath(), fx.name()));
}

test "wksp_exclusive_create_integration: a released name can be created by another process" {
    var fx: Fixture = undefined;
    try fx.init();
    defer fx.deinit();

    const held = try hold(fx.name());
    try std.testing.expectEqual(codes.refused, try runProbe(fx.shmemPath(), fx.name()));
    release(held, fx.name());

    try std.testing.expectEqual(codes.created, try runProbe(fx.shmemPath(), fx.name()));
}
