const std = @import("std");
const c_abi = @import("c_abi");

pub const shmem_path_cap: usize = 256;

/// Fills `argv` with a synthetic argv: program name only, or program
/// name + " --shmem-path <path> --log-path -" when shmem_path is given.
/// Returns argc. Pure and testable: never calls c_abi.boot.boot().
fn buildArgv(
    shmem_path: ?[]const u8,
    shmem_path_buf: *[shmem_path_cap]u8,
    argv: *[5][*:0]u8,
) error{ShmemPathTooLong}!c_int {
    // String literals are *const [:0]u8; fd_boot reads argv elements
    // as C strings, never writes through them. The const cast is safe.
    argv[0] = @constCast("tickoni-tile");

    const path = shmem_path orelse {
        argv[1] = @constCast("--log-path");
        argv[2] = @constCast("-");
        return 3;
    };
    if (path.len >= shmem_path_buf.len) return error.ShmemPathTooLong;
    @memcpy(shmem_path_buf[0..path.len], path);
    shmem_path_buf[path.len] = 0;
    // path_z is a slice-to-string cast of shmem_path_buf; it points into
    // mutable memory so this cast to [*:0]u8 is safe.
    const path_z: [*:0]u8 = shmem_path_buf[0..path.len :0];

    argv[1] = @constCast("--shmem-path");
    argv[2] = path_z;
    // Disable async log pipe: without this fd_boot creates an async pipe
    // with no reader, causing SIGPIPE on every log write. "--log-path -"
    // tells fd_boot to log to stdout (sync, no pipe).
    argv[3] = @constCast("--log-path");
    argv[4] = @constCast("-");
    return 5;
}

/// Boots fd_util's substrate with a synthetic argv (see buildArgv). Must be
/// paired with c_abi.boot.halt(). Not thread-safe to call concurrently with
/// itself; call once per process at startup.
pub fn bootWithSyntheticArgv(shmem_path: ?[]const u8) error{ShmemPathTooLong}!void {
    var shmem_path_buf: [shmem_path_cap]u8 = undefined;
    // Non-nullable pointer array — every element must be a valid pointer
    // because C's fd_boot dereferences argv[0..argc] unconditionally.
    var argv_buf: [5][*:0]u8 = undefined;

    const argc = try buildArgv(shmem_path, &shmem_path_buf, &argv_buf);

    // Pad remaining slots with valid empty-string pointers so fd_boot's loop
    // bounds (set by argc) never read uninitialized memory.
    var i = argc;
    while (i < 5) : (i += 1) {
        argv_buf[@intCast(i)] = @constCast("");
    }

    // V2.14.S8.T4: Use the C shim tk_boot_with_argv which takes a char**
    // and internally creates a char*** (address of the local variable).
    // This avoids Zig's unreliable @ptrCast between fixed-size and
    // open-ended arrays.
    const argv_ptr: [*][*:0]u8 = @ptrCast(&argv_buf);
    c_abi.boot.bootWithArgv(@intCast(argc), argv_ptr);
}

// ---------------------------------------------------------------------------
// Tests — buildArgv's synthetic argv shape only; fd_boot is not called (it
// has real side effects: log file creation, shmem subsystem init) and must
// not run in the offline unit lane.
// ---------------------------------------------------------------------------

test "buildArgv without a shmem path is a valid single-element argv" {
    var shmem_path_buf: [shmem_path_cap]u8 = undefined;
    var argv: [5][*:0]u8 = undefined;

    const argc = try buildArgv(null, &shmem_path_buf, &argv);
    try std.testing.expectEqual(@as(c_int, 3), argc);
    try std.testing.expectEqualStrings("tickoni-tile", argv[0]);
    try std.testing.expectEqualStrings("--log-path", argv[1]);
    try std.testing.expectEqualStrings("-", argv[2]);
}

test "buildArgv with a shmem path produces a 5-element argv" {
    var shmem_path_buf: [shmem_path_cap]u8 = undefined;
    var argv: [5][*:0]u8 = undefined;

    const path = "/tmp/tickoni-run";
    const argc = try buildArgv(path, &shmem_path_buf, &argv);
    try std.testing.expectEqual(@as(c_int, 5), argc);
    try std.testing.expectEqualStrings("tickoni-tile", argv[0]);
    try std.testing.expectEqualStrings("--shmem-path", argv[1]);
    try std.testing.expectEqualStrings(path, argv[2]);
    try std.testing.expectEqualStrings("--log-path", argv[3]);
    try std.testing.expectEqualStrings("-", argv[4]);
}

test "buildArgv rejects an over-long shmem path" {
    var shmem_path_buf: [shmem_path_cap]u8 = undefined;
    var argv: [4][*:0]u8 = undefined;

    var too_long: [shmem_path_cap + 1]u8 = undefined;
    for (&too_long) |*c| c.* = 'a';
    try std.testing.expectError(error.ShmemPathTooLong, buildArgv(&too_long, &shmem_path_buf, &argv));
}
