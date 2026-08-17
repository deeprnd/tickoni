/// fd_util substrate boot policy for Tickoni process-mode entrypoints, layered
/// on the raw c_abi.boot.boot/halt bridge.
///
/// fd_boot takes argc/argv by reference and expects Unix argv shape (a
/// NULL-terminated array with argv[0] as a program name); Tickoni's process
/// entrypoints do not need real command-line flags beyond --shmem-path, so
/// bootWithSyntheticArgv supplies a minimal well-formed argv instead of
/// plumbing the real one through. Confirmed against the actual fd_boot call
/// chain in a throwaway spike (fd_env_strip_cmdline_ulong dereferences argv
/// unconditionally; argc==0 with an undefined argv crashes). The path is
/// passed as a --shmem-path argv flag rather than the FD_SHMEM_PATH
/// environment variable because both the supervisor and its self-exec'd
/// tile children each boot their own process-local fd_shmem subsystem, and
/// only the supervisor's own process env is under its direct control here.
///
/// The argv backing buffers are stack-local, not process-global: fd_boot's
/// private-boot helpers (fd_log/fd_shmem/fd_tile) copy out the values they
/// care about during this synchronous call and do not retain the argv or
/// string memory afterward, so nothing needs to outlive the call.
const std = @import("std");
const c_abi = @import("c_abi");

pub const shmem_path_cap: usize = 256;

const ProgNameBuf = @TypeOf("tickoni-tile".*);
const FlagNameBuf = @TypeOf("--shmem-path".*);

/// Fills `argv_buf` with a synthetic argv: program name only, or program
/// name + "--shmem-path <path>" when shmem_path is given. Returns argc.
/// Pure and testable: never calls c_abi.boot.boot().
fn buildArgv(
    shmem_path: ?[]const u8,
    prog_name_buf: *ProgNameBuf,
    flag_name_buf: *FlagNameBuf,
    shmem_path_buf: *[shmem_path_cap]u8,
    argv_buf: *[4]?[*:0]u8,
) error{ShmemPathTooLong}!c_int { prog_name_buf.* = "tickoni-tile".*;
    argv_buf[0] = prog_name_buf;
    argv_buf[1] = null;

    const path = shmem_path orelse return 1;
    if (path.len >= shmem_path_buf.len) return error.ShmemPathTooLong;
    @memcpy(shmem_path_buf[0..path.len], path);
    shmem_path_buf[path.len] = 0;
    const path_z: [:0]u8 = shmem_path_buf[0..path.len :0];

    flag_name_buf.* = "--shmem-path".*;
    argv_buf[1] = flag_name_buf;
    argv_buf[2] = path_z.ptr;
    argv_buf[3] = null;
    return 3; }

/// Boots fd_util's substrate with a synthetic argv (see buildArgv). Must be
/// paired with c_abi.boot.halt(). Not thread-safe to call concurrently with
/// itself; call once per process at startup.
pub fn bootWithSyntheticArgv(shmem_path: ?[]const u8) error{ShmemPathTooLong}!void { var prog_name_buf: ProgNameBuf = undefined;
    var flag_name_buf: FlagNameBuf = undefined;
    var shmem_path_buf: [shmem_path_cap]u8 = undefined;
    var argv_buf: [4]?[*:0]u8 = .{ null, null, null, null };

    var argc = try buildArgv(shmem_path, &prog_name_buf, &flag_name_buf, &shmem_path_buf, &argv_buf);
    var argv: [*][*:0]u8 = @ptrCast(&argv_buf);
    c_abi.boot.boot(&argc, &argv);
}

// ---------------------------------------------------------------------------
// Tests — buildArgv's synthetic argv shape only; fd_boot is not called (it
// has real side effects: log file creation, shmem subsystem init) and must
// not run in the offline unit lane.
// ---------------------------------------------------------------------------

test "buildArgv without a shmem path is a valid single-element argv" { var prog_name_buf: ProgNameBuf = undefined;
    var flag_name_buf: FlagNameBuf = undefined;
    var shmem_path_buf: [shmem_path_cap]u8 = undefined;
    var argv_buf: [4]?[*:0]u8 = .{ null, null, null, null };

    const argc = try buildArgv(null, &prog_name_buf, &flag_name_buf, &shmem_path_buf, &argv_buf);
    try std.testing.expectEqual(@as(c_int, 1), argc);
    try std.testing.expect(argv_buf[0] != null);
    try std.testing.expectEqual(@as(?[*:0]u8, null), argv_buf[1]);
    try std.testing.expectEqualStrings("tickoni-tile", &prog_name_buf);
}

test "buildArgv with a shmem path produces a 3-element argv" { var prog_name_buf: ProgNameBuf = undefined;
    var flag_name_buf: FlagNameBuf = undefined;
    var shmem_path_buf: [shmem_path_cap]u8 = undefined;
    var argv_buf: [4]?[*:0]u8 = .{ null, null, null, null };

    const path = "/tmp/tickoni-run";
    const argc = try buildArgv(path, &prog_name_buf, &flag_name_buf, &shmem_path_buf, &argv_buf);
    try std.testing.expectEqual(@as(c_int, 3), argc);
    try std.testing.expectEqualStrings("tickoni-tile", &prog_name_buf);
    try std.testing.expectEqualStrings("--shmem-path", &flag_name_buf);
    const path_z: [:0]u8 = shmem_path_buf[0..path.len :0];
    try std.testing.expectEqualStrings(path, path_z);
    try std.testing.expectEqual(@as(?[*:0]u8, null), argv_buf[3]);
}

test "buildArgv rejects an over-long shmem path" { var prog_name_buf: ProgNameBuf = undefined;
    var flag_name_buf: FlagNameBuf = undefined;
    var shmem_path_buf: [shmem_path_cap]u8 = undefined;
    var argv_buf: [4]?[*:0]u8 = .{ null, null, null, null };

    var too_long: [shmem_path_cap + 1]u8 = undefined;
    for (&too_long) |*c| c.* = 'a';
    try std.testing.expectError(error.ShmemPathTooLong, buildArgv(&too_long, &prog_name_buf, &flag_name_buf, &shmem_path_buf, &argv_buf));
}
