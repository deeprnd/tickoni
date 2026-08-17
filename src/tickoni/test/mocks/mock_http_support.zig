const std = @import("std");

pub const max_method_len: usize = 16;
pub const max_path_len: usize = 256;
pub const max_body_len: usize = 4096;
pub const server_read_buffer_len: usize = 8192;
pub const server_write_buffer_len: usize = 512;
pub const request_body_read_buffer_len: usize = 1024;

pub const RequestCapture = struct { method: [max_method_len]u8 = [_]u8{ 0 }**max_method_len,
    method_len: u8 = 0,
    path: [max_path_len]u8 = [_]u8{ 0 }**max_path_len,
    path_len: u16 = 0,
    body: [max_body_len]u8 = [_]u8{ 0 }**max_body_len,
    body_len: u16 = 0,

    pub fn methodSlice(self: *const RequestCapture) []const u8 { return self.method[0..self.method_len]; }

    pub fn pathSlice(self: *const RequestCapture) []const u8 { return self.path[0..self.path_len]; }

    pub fn bodySlice(self: *const RequestCapture) []const u8 { return self.body[0..self.body_len]; }
};

pub const TestRuntime = struct {
    threaded: std.Io.Threaded,

    pub fn init() TestRuntime {
        return .{
            .threaded = std.Io.Threaded.init(std.testing.allocator, .{}),
        };
    }

    pub fn deinit(self: *TestRuntime) void { self.threaded.deinit(); }

    pub fn io(self: *TestRuntime) std.Io { return self.threaded.io(); }
};

pub const ReadRequestError = std.http.Server.ReceiveHeadError || std.http.Server.Request.ExpectContinueError || error{ MethodTooLong,
    PathTooLong,
    BodyTooLarge, };

pub fn captureRequest(request: *std.http.Server.Request) ReadRequestError!RequestCapture {
    var capture = RequestCapture{};
    const method = @tagName(request.head.method);
    const path = request.head.target;

    if (method.len > max_method_len) return error.MethodTooLong;
    if (path.len > max_path_len) return error.PathTooLong;
    capture.method_len = @intCast(method.len);
    capture.path_len = @intCast(path.len);
    @memcpy(capture.method[0..method.len], method);
    @memcpy(capture.path[0..path.len], path);

    var request_body_reader_buffer: [request_body_read_buffer_len]u8 = undefined;
    var request_body_reader = try request.readerExpectContinue(&request_body_reader_buffer);
    var body_writer = std.Io.Writer.fixed(&capture.body);
    _ = request_body_reader.streamRemaining(&body_writer) catch |err| switch (err) { error.WriteFailed => return error.BodyTooLarge,
        error.ReadFailed => return error.ReadFailed, };
    capture.body_len = @intCast(body_writer.end);
    return capture;
}

pub fn respondJson(request: *std.http.Server.Request, status: std.http.Status, body: []const u8) !void { try request.respond(body, .{
        .status = status,
        .keep_alive = false,
        .extra_headers = &.{
            .{ .name = "Content-Type", .value = "application/json" },
        },
    });
}

pub fn respondText(request: *std.http.Server.Request, status: std.http.Status, body: []const u8) !void { try request.respond(body, .{
        .status = status,
        .keep_alive = false,
        .extra_headers = &.{
            .{ .name = "Content-Type", .value = "text/plain" },
        },
    });
}
