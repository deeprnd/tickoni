/// tkagnt's prompt table handoff (plan v2.NN rev 2, D5).
///
/// An agent request names its prompt by reference (`TkPromptRef`: hash and
/// length); the prompt bytes never cross the spine. The supervisor writes the
/// run's prompts once, to `tkagnt.prompts` beside topology.spec, before any
/// child exists, and only the tkagnt child reads it back and installs each
/// prompt in the C tile's content-addressed table (`tkagnt_set_prompt`), which
/// re-verifies every prompt against its hash. A file is, in order:
///
///   * a fixed header (`Header`): magic, version, prompt count and total bytes;
///   * per prompt: its 16-byte frame (hash u64, length u32, reserved u32) and
///     then its bytes.
///
/// The bounds are the C tile's (`TKAGNT_PROMPT_*`, tk_agent_wire.h): at most
/// `prompt_cap` prompts of at most `prompt_max_bytes` each, `store_bytes` in
/// all. A run with no prompts still gets a file, so a missing file is a
/// startup failure, not an empty table.
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");

pub const file_name = "tkagnt.prompts";
pub const header_magic: u32 = 0x544b4150; // "TKAP"
pub const header_version: u16 = 1;

pub const prompt_cap: usize = c_abi.tkagnt.prompt_cap;
pub const store_bytes: usize = c_abi.tkagnt.prompt_store_bytes;
pub const prompt_max_bytes: usize = c_abi.tkagnt.prompt_max_bytes;

pub const Header = extern struct {
    magic: u32 = header_magic,
    version: u16 = header_version,
    reserved: u16 = 0,
    count: u32,
    total_bytes: u32,
};

const entry_head_len: usize = 16;

comptime {
    std.debug.assert(@sizeOf(Header) == 16);
}

pub const ValidateError = error{
    TooManyAgentPrompts,
    AgentPromptBound,
    AgentPromptStoreBound,
    DuplicateAgentPrompt,
};

pub const ReadError = error{
    PromptsTruncated,
    PromptsTrailingBytes,
    PromptsBadMagic,
    PromptsBadVersion,
    PromptsMalformed,
};

/// The content-addressed reference an agent request carries for `bytes`.
pub fn ref(bytes: []const u8) c_abi.tkagnt.PromptRef {
    var r = std.mem.zeroes(c_abi.tkagnt.PromptRef);
    r.prompt_hash = c_abi.multipart.messageHash(bytes);
    r.prompt_len = @intCast(bytes.len);
    return r;
}

/// The run's prompt set against the tile's bounds, before anything is written.
pub fn validate(prompts: []const []const u8) ValidateError!void {
    if (prompts.len > prompt_cap) return error.TooManyAgentPrompts;
    var total: usize = 0;
    for (prompts, 0..) |p, i| {
        if (p.len == 0 or p.len > prompt_max_bytes) return error.AgentPromptBound;
        total += p.len;
        const h = c_abi.multipart.messageHash(p);
        for (prompts[0..i]) |previous| {
            if (c_abi.multipart.messageHash(previous) == h) return error.DuplicateAgentPrompt;
        }
    }
    if (total > store_bytes) return error.AgentPromptStoreBound;
}

/// Path of the file: beside topology.spec in `run_dir`, or relative to the
/// directory handle when `run_dir` is empty (tests).
pub fn path(buf: []u8, run_dir: []const u8) std.fmt.BufPrintError![]const u8 {
    if (run_dir.len > 0) return std.fmt.bufPrint(buf, "{s}/" ++ file_name, .{run_dir});
    return std.fmt.bufPrint(buf, file_name, .{});
}

/// Validates the set, then writes the file. Nothing is written if validation
/// fails.
pub fn write(io: std.Io, dir: std.Io.Dir, run_dir: []const u8, prompts: []const []const u8) !void {
    try validate(prompts);
    var path_buf: [rt.launch_spec.shmem_path_cap + 32]u8 = undefined;
    const file_path = try path(&path_buf, run_dir);
    var file = try rt.file_io.createOwnerOnlyFile(io, dir, file_path);
    defer file.close(io);
    var total: u32 = 0;
    for (prompts) |p| total += @intCast(p.len);
    const header = Header{ .count = @intCast(prompts.len), .total_bytes = total };
    try file.writePositionalAll(io, std.mem.asBytes(&header), 0);
    var off: u64 = @sizeOf(Header);
    for (prompts) |p| {
        var head: [entry_head_len]u8 = std.mem.zeroes([entry_head_len]u8);
        std.mem.writeInt(u64, head[0..8], c_abi.multipart.messageHash(p), .little);
        std.mem.writeInt(u32, head[8..12], @intCast(p.len), .little);
        try file.writePositionalAll(io, &head, off);
        off += head.len;
        try file.writePositionalAll(io, p, off);
        off += p.len;
    }
}

/// Reads the file and installs every prompt in this process's tkagnt tile.
/// Fail closed: a missing, short, long, mis-magic'd or mis-versioned file, an
/// out-of-bound frame, or a prompt the tile refuses (it re-checks the hash)
/// stops the child before the tile runs. Returns the prompts installed.
pub fn install(io: std.Io, dir: std.Io.Dir, file_path: []const u8, allocator: std.mem.Allocator) !usize {
    var file = try rt.file_io.openFile(io, dir, file_path);
    defer file.close(io);
    var header: Header = undefined;
    if ((try file.readPositionalAll(io, std.mem.asBytes(&header), 0)) != @sizeOf(Header)) return error.PromptsTruncated;
    if (header.magic != header_magic) return error.PromptsBadMagic;
    if (header.version != header_version) return error.PromptsBadVersion;
    if (header.count > prompt_cap or header.total_bytes > store_bytes) return error.PromptsMalformed;

    const section_len: usize = header.total_bytes + @as(usize, header.count) * entry_head_len;
    const blob = try allocator.alloc(u8, section_len);
    defer allocator.free(blob);
    if ((try file.readPositionalAll(io, blob, @sizeOf(Header))) != section_len) return error.PromptsTruncated;
    var extra: [1]u8 = undefined;
    if ((try file.readPositionalAll(io, &extra, @sizeOf(Header) + section_len)) != 0) return error.PromptsTrailingBytes;

    var off: usize = 0;
    var i: usize = 0;
    while (i < header.count) : (i += 1) {
        if (off + entry_head_len > blob.len) return error.PromptsMalformed;
        const hash = std.mem.readInt(u64, blob[off..][0..8], .little);
        const len: usize = std.mem.readInt(u32, blob[off + 8 ..][0..4], .little);
        off += entry_head_len;
        if (len == 0 or off + len > blob.len) return error.PromptsMalformed;
        try c_abi.tkagnt.setPrompt(hash, blob[off..][0..len]);
        off += len;
    }
    if (off != blob.len) return error.PromptsMalformed;
    return header.count;
}

test "validate refuses prompts outside the tile's bounds" {
    try validate(&.{ "one", "two" });
    try std.testing.expectError(error.AgentPromptBound, validate(&.{""}));
    try std.testing.expectError(error.DuplicateAgentPrompt, validate(&.{ "same", "same" }));
    var many: [prompt_cap + 1][]const u8 = undefined;
    var names: [prompt_cap + 1][4]u8 = undefined;
    for (&many, &names, 0..) |*p, *n, i| {
        n.* = .{ 'p', @intCast('a' + i), 0, 0 };
        p.* = n[0..2];
    }
    try std.testing.expectError(error.TooManyAgentPrompts, validate(&many));
}

test "ref binds a prompt by its multipart message hash and length" {
    const r = ref("prompt bytes");
    try std.testing.expectEqual(c_abi.multipart.messageHash("prompt bytes"), r.prompt_hash);
    try std.testing.expectEqual(@as(u32, 12), r.prompt_len);
}

test "install refuses a truncated, mis-magic'd or trailing file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.testing.io;

    try std.testing.expectError(error.FileNotFound, install(io, tmp.dir, file_name, std.testing.allocator));

    var file = try tmp.dir.createFile(io, file_name, .{});
    try file.writePositionalAll(io, &[_]u8{ 1, 2, 3 }, 0);
    file.close(io);
    try std.testing.expectError(error.PromptsTruncated, install(io, tmp.dir, file_name, std.testing.allocator));

    var bad = Header{ .count = 0, .total_bytes = 0 };
    bad.magic = 0xdeadbeef;
    file = try tmp.dir.createFile(io, file_name, .{});
    try file.writePositionalAll(io, std.mem.asBytes(&bad), 0);
    file.close(io);
    try std.testing.expectError(error.PromptsBadMagic, install(io, tmp.dir, file_name, std.testing.allocator));

    const empty = Header{ .count = 0, .total_bytes = 0 };
    file = try tmp.dir.createFile(io, file_name, .{});
    try file.writePositionalAll(io, std.mem.asBytes(&empty), 0);
    try file.writePositionalAll(io, "x", @sizeOf(Header));
    file.close(io);
    try std.testing.expectError(error.PromptsTrailingBytes, install(io, tmp.dir, file_name, std.testing.allocator));
}

test "an empty prompt set round-trips to an empty table" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(std.testing.io, tmp.dir, "", &.{});
    try std.testing.expectEqual(@as(usize, 0), try install(std.testing.io, tmp.dir, file_name, std.testing.allocator));
}
