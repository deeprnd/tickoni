/// Investigation test for std.http.Client connection pool timeout bug.
///
/// Bug: https://github.com/ziglang/zig/issues/21316 (migrated to #37195)
/// std lib http client pools connections, which means that sometimes they timeout,
/// leading to the server closing the connection. In such case the connection should
/// be reestablished, rather than failure reported.
///
/// This test:
/// 1. Spins up a simple Python HTTP server that closes idle connections after
///    a configurable timeout (simulating a real LLM server / llama.cpp behavior).
/// 2. Makes multiple sequential requests through std.http.Client, forcing reuse
///    of the pooled connection.
/// 3. After the server's idle timeout, attempts another request.
/// 4. Checks whether the request succeeds (pool re-established connection)
///    or fails with error.HttpConnectionClosing.

const std = @import("std");

const server_port: u16 = 19876;

fn buildPythonServerCode() []const u8 {
    // A simple HTTP server that mimics llama.cpp's Connection: close behavior
    // after idle timeout, which is the root cause of HttpConnectionClosing.
    return
        \\import http.server
        \\import socketserver
        \\import time
        \\import json
        \\
        \\IDLE_TIMEOUT = 2  # seconds before server closes the connection
        \\last_activity = time.monotonic()
        \\
        \\class Handler(http.server.BaseHTTPRequestHandler):
        \\    def do_GET(self):
        \\        self.send_response(200)
        \\        self.send_header("Content-Type", "text/plain")
        \\        self.end_headers()
        \\        self.wfile.write(b"ok")
        \\        self.update_activity()
        \\
        \\    def do_POST(self):
        \\        length = int(self.headers.get("Content-Length", 0))
        \\        self.rfile.read(length) if length else None
        \\        self.send_response(200)
        \\        self.send_header("Content-Type", "application/json")
        \\        body = json.dumps({"model": "test", "choices": [{"message": {"content": "{\"ok\":true}"}},], "usage": {}})
        \\        self.send_header("Content-Length", str(len(body)))
        \\        self.end_headers()
        \\        self.wfile.write(body.encode())
        \\        self.update_activity()
        \\
        \\    def update_activity(self):
        \\        global last_activity
        \\        last_activity = time.monotonic()
        \\
        \\    def log_request(self, *a, **kw): pass  # silence logs
        \\    def log_error(self, *a, **kw): pass
        \\
        \\class TimeoutServer(socketserver.TCPServer):
        \\    allow_reuse_address = True
        \\
        \\    def server_bind(self):
        \\        super().server_bind()
        \\        # Set TCP keepalive to detect dead peers
        \\        import socket
        \\        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
        \\
        \\    def handle_timeout(self):
        \\        """Called when a request handler times out. This forces
        \\        connection close so std.http.Client gets HttpConnectionClosing
        \\        on next reuse attempt."""
        \\        self.close_request(self.request)
        \\
        \\    def process_request(self, request, client_address):
        \\        # Use short timeout so the server closes idle connections quickly
        \\        import threading
        \\        t = threading.Thread(target=self.process_request_thread, args=(request, client_address))
        \\        t.daemon = True
        \\        t.start()
        \\
        \\    def process_request_thread(self, request, client_address):
        \\        try:
        \\            self.finish_request(request, client_address)
        \\        except Exception:
        \\            self.handle_error(request, client_address)
        \\        finally:
        \\            self.shutdown_request(request)
        \\
        \\if __name__ == "__main__":
        \\    server = TimeoutServer(("127.0.0.1", {port}), Handler)
        \\    print(f"LISTENING on 127.0.0.1:{port}")
        \\    server.serve_forever(poll_interval=0.1)
        .format(port=server_port);
}

/// Spin up a Python HTTP server on a local port.
fn startServer(io: std.Io) anyerror!struct { pid: u32, port: u16 } {
    const code = buildPythonServerCode();
    const tmp_dir = "/tmp";
    const script_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/tickoni_pool_test_server.py", .{tmp_dir});
    defer std.testing.allocator.free(script_path);

    var file = try io.cwd().createFile(std.testing.io, script_path, .{ .truncate = true });
    defer file.close(std.testing.io);
    try file.writeAll(std.testing.io, code);
    file.close(std.testing.io);

    const argv = [_][]const u8{ "python3", script_path };
    var process = try io.spawn(std.testing.allocator, argv[0], &argv, .{
        .env_map = .{},
        .output = .inherit,
        .error = .inherit,
    });

    // Wait for server to be ready
    try io.sleep(std.time.ns_per_s);

    return .{ .pid = process.getPid(), .port = server_port };
}

fn stopServer(pid: u32) void {
    _ = std.process.kill(pid, .SIGTERM) catch {};
    std.process.sleep(std.time.ns_per_ms * 100);
}

test "http client: connection pool timeout causes HttpConnectionClosing" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    // Start a server that will close idle connections
    const server = try startServer(io);
    defer stopServer(server.pid);

    var client = std.http.Client{ .allocator = allocator, .io = io };
    defer client.deinit();

    const url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}/health", .{server.port});
    defer allocator.free(url);

    // Make 2 initial requests — this creates and reuses the pooled connection
    var i: usize = 0;
    while (i < 2) : (i += 1) {
        var resp_writer: std.Io.Writer.Allocating = .init(allocator);
        defer resp_writer.deinit();
        _ = try client.fetch(.{
            .location = .{ .url = url },
            .method = .GET,
            .response_writer = &resp_writer.writer,
        });
        try std.testing.expectEqualStrings("ok", resp_writer.written());
    }

    // Wait for the server to close the idle connection.
    // We set IDLE_TIMEOUT=2s above, so 3s should be enough.
    try io.sleep(std.time.ns_per_s * 3);

    // Now try another request — this is where the bug manifests.
    // With the pool bug, this should fail with HttpConnectionClosing
    // because the server already closed the pooled connection.
    var resp_writer: std.Io.Writer.Allocating = .init(allocator);
    defer resp_writer.deinit();
    const err = client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .response_writer = &resp_writer.writer,
    }) catch |e| e;

    switch (err) {
        error.HttpConnectionClosing => {
            // BUG CONFIRMED: the connection pool reused a dead connection
            std.debug.print("BUG: HttpConnectionClosing on pooled connection reuse after idle timeout\n", .{});
            try std.testing.fail("HttpConnectionClosing bug reproduced — pool should re-establish connection");
        },
        else => |other| {
            // Any other error is unexpected for this test
            std.debug.print("UNEXPECTED error: {s}\n", .{@tagName(other)});
            try std.testing.fail("Expected HttpConnectionClosing but got different error");
        },
        // If fetch succeeded, the pool handled the dead connection correctly
        // (unlikely with this test setup, but would mean the bug is fixed)
    }
    _ = resp_writer.written();
}

test "http client: POST endpoint with pool reuse" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const server = try startServer(io);
    defer stopServer(server.pid);

    var client = std.http.Client{ .allocator = allocator, .io = io };
    defer client.deinit();

    const url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}/chat", .{server.port});
    defer allocator.free(url);

    const payload = "{\"model\":\"test\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"temperature\":0,\"top_p\":1,\"max_tokens\":32,\"stream\":false}";

    // Make initial requests
    var i: usize = 0;
    while (i < 2) : (i += 1) {
        var resp_writer: std.Io.Writer.Allocating = .init(allocator);
        defer resp_writer.deinit();
        _ = try client.fetch(.{
            .location = .{ .url = url },
            .method = .POST,
            .extra_headers = &.{.{ .name = "Content-Type", .value = "application/json" }},
            .payload = payload,
            .response_writer = &resp_writer.writer,
        });
    }

    // Wait for server to close the connection
    try io.sleep(std.time.ns_per_s * 3);

    // Reuse attempt — should trigger HttpConnectionClosing
    var resp_writer: std.Io.Writer.Allocating = .init(allocator);
    defer resp_writer.deinit();
    const err = client.fetch(.{
        .location = .{ .url = url },
        .method = .POST,
        .extra_headers = &.{.{ .name = "Content-Type", .value = "application/json" }},
        .payload = payload,
        .response_writer = &resp_writer.writer,
    }) catch |e| e;

    switch (err) {
        error.HttpConnectionClosing => {
            std.debug.print("BUG (POST): HttpConnectionClosing on pooled connection reuse after idle timeout\n", .{});
            try std.testing.fail("HttpConnectionClosing bug reproduced on POST");
        },
        else => |other| {
            std.debug.print("UNEXPECTED error: {s}\n", .{@tagName(other)});
            try std.testing.fail("Expected HttpConnectionClosing but got different error");
        },
    }
    _ = resp_writer.written();
}
