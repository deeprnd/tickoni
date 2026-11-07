const std = @import("std");

pub fn BoundedQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        buf: []T,
        /// Written by the consumer, observed by the producer.
        head: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
        /// Written by the producer, observed by the consumer.
        tail: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
        /// Written by the producer or supervisor during shutdown.
        closed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        max_len: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
        push_waits: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            return .{ .buf = try allocator.alloc(T, capacity) };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.buf);
        }

        pub fn push(self: *Self, value: T, stop: *std.atomic.Value(bool)) error{ Closed, Stopped }!void {
            while (true) {
                if (self.closed.load(.acquire)) return error.Closed;

                const tail = self.tail.load(.monotonic);
                const head = self.head.load(.acquire);
                const len = tail - head;
                if (len < self.buf.len) {
                    const idx = tail & (self.buf.len - 1);
                    self.buf[idx] = value;
                    updateMaxUsize(&self.max_len, len + 1);
                    self.tail.store(tail + 1, .release);
                    return;
                }

                _ = self.push_waits.fetchAdd(1, .release);
                if (stop.load(.acquire)) return error.Stopped;
                // std.Thread.yield() error is an OS scheduling failure — retrying
                // or aborting provides no benefit; the loop naturally slows and recovers.
                std.Thread.yield() catch {};
            }
        }

        pub fn pop(self: *Self, stop: *std.atomic.Value(bool)) ?T {
            while (true) {
                const head = self.head.load(.monotonic);
                const tail = self.tail.load(.acquire);
                if (head != tail) {
                    const value = self.buf[head & (self.buf.len - 1)];
                    self.head.store(head + 1, .release);
                    return value;
                }

                if (self.closed.load(.acquire)) return null;
                if (stop.load(.acquire)) return null;
                // std.Thread.yield() error is an OS scheduling failure — retrying
                // or aborting provides no benefit; the loop naturally slows and recovers.
                std.Thread.yield() catch {};
            }
        }

        pub fn close(self: *Self) void {
            self.closed.store(true, .release);
        }

        pub fn maxDepth(self: *Self) usize {
            return self.max_len.load(.acquire);
        }

        pub fn pushWaits(self: *Self) u64 {
            return self.push_waits.load(.acquire);
        }
    };
}

pub fn updateMaxU64(value: *std.atomic.Value(u64), candidate: u64) void {
    var current = value.load(.acquire);
    while (candidate > current) {
        if (value.cmpxchgWeak(current, candidate, .release, .acquire)) |observed| {
            current = observed;
        } else {
            return;
        }
    }
}

pub fn updateMaxUsize(value: *std.atomic.Value(usize), candidate: usize) void {
    var current = value.load(.acquire);
    while (candidate > current) {
        if (value.cmpxchgWeak(current, candidate, .release, .acquire)) |observed| {
            current = observed;
        } else {
            return;
        }
    }
}
