const std = @import("std");
const support = @import("mock_http_support");
const util = @import("util");

/// Force-close the listener by connecting with retries.  After 10 failed
/// attempts (500 ms total) we give up so stop() never blocks forever.
fn forceCloseListener(self: *Server) void {
    var attempt: u8 = 0;
    while (attempt < 10) : (attempt += 1) {
        if (std.Io.net.IpAddress.connect(&self.listener.socket.address, self.io, .{ .mode = .stream })) |stream| {
            stream.socket.close(self.io);
            return;
        } else |_| {}
        util.process.sleepNanos(50 * std.time.ns_per_ms);
    }
}

pub const Config = struct {
    health_body: []const u8 = "ok",
    portfolio_json: []const u8 = "{\"account_id\":2001,\"cash_cents\":5000000,\"buying_power_cents\":5000000}",
    quotes_json: []const u8 = "{\"as_of_ns\":1765792800000000000,\"quotes\":[{\"ticker\":\"NVDA\",\"ask_cents\":12500}]}",
    paper_order_json: []const u8 = "{\"paper_order_id\":\"mock-paper-order-1\",\"status\":\"filled\"}",
};

pub const Server = struct {
    io: std.Io,
    listener: std.Io.net.Server,
    thread: ?std.Thread = null,
    stop_flag: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    mutex: std.Io.Mutex = .init,
    last_request: ?support.RequestCapture = null,
    request_count: u32 = 0,
    config: Config,

    pub fn init(io: std.Io, config: Config) !Server {
        var address = std.Io.net.IpAddress.parse("127.0.0.1", 0) catch unreachable;
        const listener = try address.listen(io, .{ .reuse_address = true });
        return Server{
            .io = io,
            .listener = listener,
            .config = config,
        };
    }

    pub fn start(self: *Server) !void {
        self.thread = try std.Thread.spawn(.{}, serveLoop, .{self});
    }

    pub fn stop(self: *Server) void {
        self.stop_flag.store(true, .seq_cst);
        forceCloseListener(self);
        if (self.thread) |thread| thread.join();
        self.thread = null;
        self.listener.deinit(self.io);
    }

    pub fn baseUrlAlloc(self: *const Server, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{self.listener.socket.address.getPort()});
    }

    pub fn lastRequest(self: *Server) ?support.RequestCapture {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.last_request;
    }
};

fn serveLoop(server: *Server) void {
    while (true) {
        var stream = server.listener.accept(server.io) catch break;
        defer stream.socket.close(server.io);

        if (server.stop_flag.load(.seq_cst)) break;

        var read_buffer: [support.server_read_buffer_len]u8 = undefined;
        var write_buffer: [support.server_write_buffer_len]u8 = undefined;
        var reader = stream.reader(server.io, &read_buffer);
        var writer = stream.writer(server.io, &write_buffer);
        var http_server = std.http.Server.init(&reader.interface, &writer.interface);
        var request = http_server.receiveHead() catch continue;
        const req = support.captureRequest(&request) catch continue;
        server.mutex.lockUncancelable(server.io);
        server.last_request = req;
        server.request_count += 1;
        server.mutex.unlock(server.io);

        if (std.mem.eql(u8, req.methodSlice(), "GET") and std.mem.eql(u8, req.pathSlice(), "/health")) {
            support.respondText(&request, .ok, server.config.health_body) catch {};
            continue;
        }

        if (std.mem.eql(u8, req.methodSlice(), "GET") and std.mem.eql(u8, req.pathSlice(), "/accounts/2001/portfolio")) {
            support.respondJson(&request, .ok, server.config.portfolio_json) catch {};
            continue;
        }

        if (std.mem.eql(u8, req.methodSlice(), "POST") and std.mem.eql(u8, req.pathSlice(), "/quotes")) {
            support.respondJson(&request, .ok, server.config.quotes_json) catch {};
            continue;
        }

        if (std.mem.eql(u8, req.methodSlice(), "POST") and std.mem.eql(u8, req.pathSlice(), "/paper-orders")) {
            support.respondJson(&request, .ok, server.config.paper_order_json) catch {};
            continue;
        }

        support.respondText(&request, .not_found, "not found") catch {};
    }
}
