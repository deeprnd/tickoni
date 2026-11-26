/// tk-wksp-probe: second-process helper for test_process_wksp_exclusive_create.zig.
///
/// A named workspace must be created exclusively across processes: creating a
/// name another process already holds fails, on every OS. The process that
/// holds the name is the test; this program is the other process. It boots
/// shared memory on the given path, tries to create the workspace once, and
/// reports the outcome through its exit code:
///
///   tk-wksp-probe <shmem-path> <workspace-name>
///
/// A workspace the probe did create is deleted again before it exits, so a
/// run leaves no name behind. Test-only: built under -Dtest and never part of
/// the product.
const std = @import("std");
const logger = @import("logger");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const codes = @import("wksp_probe_codes.zig");

pub fn main(init: std.process.Init) !void {
    var it = try std.process.Args.iterateAllocator(init.minimal.args, init.gpa);
    defer it.deinit();
    _ = it.next(); // program name
    const shmem_path = it.next() orelse std.process.exit(codes.usage);
    const name = it.next() orelse std.process.exit(codes.usage);
    if (it.next() != null) std.process.exit(codes.usage);

    logger.init();
    rt.boot.bootLite(shmem_path, "") catch std.process.exit(codes.usage);

    const name_z = try init.gpa.dupeSentinel(u8, name, 0);
    defer init.gpa.free(name_z);
    const page_cnt = [_]usize{codes.page_cnt};
    const cpu_idx = [_]usize{0};
    const rc = c_abi.wksp.wkspNewNamed(name_z, c_abi.wksp.shmem_normal_page_sz, 1, &page_cnt, &cpu_idx, 0o600, 1, 0);
    var code: u8 = codes.refused;
    if (rc == c_abi.wksp.wksp_success) {
        _ = c_abi.wksp.wkspDeleteNamed(name_z);
        code = codes.created;
    }
    c_abi.boot.halt();
    std.process.exit(code);
}
