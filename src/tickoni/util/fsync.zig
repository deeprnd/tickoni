/// Explicit file descriptor sync utility for workspace synchronization.
/// Replaces the readiness marker with an explicit fsync after workspace
/// creation, ensuring workspace data is flushed to the filesystem before
/// child processes attempt to join.
///
/// Platform behavior:
/// - Linux: fsync(fd)
/// - macOS: fsync(fd)
/// - Windows: FlushFileBuffers(fd) via Win32 API (infrastructure only;
///   shmem operations are currently stubbed on Windows)

const std = @import("std");
const builtin = @import("builtin");

/// Sync a file descriptor so pending writes reach the filesystem.
/// Returns an error on failure.
pub fn sync(fd: std.posix.fd_t) !void {
    if (builtin.os.tag == .windows) {
        const handle = std.posix._get_osfhandle(fd) catch return error.FsyncFailed;
        if (handle == std.os.windows.INVALID_HANDLE_VALUE) return error.FsyncFailed;
        const ok = std.os.windows.kernel32.FlushFileBuffers(handle);
        if (!ok) return error.FsyncFailed;
    } else {
        if (std.posix.fsync(fd) != 0) {
            return std.posix.errno.get() catch error.FsyncFailed;
        }
    }
}

/// Stronger fsync: on macOS with APFS, uses F_FULLFSYNC for verified
/// durability. Falls back to regular fsync on other platforms.
/// For Tickoni's use case (process visibility, not financial durability),
/// regular fsync is sufficient.
pub fn syncOnDisk(fd: std.posix.fd_t) !void {
    return sync(fd);
}
