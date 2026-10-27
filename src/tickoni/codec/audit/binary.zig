const std = @import("std");
const schema = @import("audit_schema");
const hash = @import("hash.zig");
const protobuf = @import("protobuf.zig");
const root = @import("mod.zig");
const wire = @import("wire.zig");

pub fn peekBinaryLen(input: []const u8) error{UnexpectedEof}!usize {
    if (input.len < @sizeOf(u32)) return error.UnexpectedEof;
    const body_len = std.mem.readInt(u32, input[0..@sizeOf(u32)], .little);
    return @sizeOf(u32) + @as(usize, body_len);
}

pub fn formatBinary(buf: []u8, event: schema.AuditEvent) ![]u8 {
    if (buf.len < @sizeOf(u32)) return error.NoSpaceLeft;
    var wire_event = wire.toWireEvent(event);
    var body_len: usize = 0;
    switch (protobuf.formatProtobuf(
        buf[@sizeOf(u32)..].ptr,
        buf.len - @sizeOf(u32),
        &wire_event,
        &body_len,
    )) {
        wire.status_ok => {},
        wire.status_no_space => return error.NoSpaceLeft,
        else => return error.InvalidBinaryRecord,
    }
    if (body_len > std.math.maxInt(u32)) return error.RecordTooLarge;
    std.mem.writeInt(u32, buf[0..@sizeOf(u32)], @intCast(body_len), .little);
    return buf[0 .. @sizeOf(u32) + body_len];
}

pub fn parseBinary(input: []const u8) !root.ParsedBinary {
    const consumed_len = try peekBinaryLen(input);
    if (input.len < consumed_len) return error.UnexpectedEof;
    var wire_event: wire.WireEvent = undefined;
    switch (protobuf.parseProtobuf(
        input[@sizeOf(u32)..consumed_len].ptr,
        consumed_len - @sizeOf(u32),
        &wire_event,
    )) {
        wire.status_ok => {},
        wire.status_invalid_protobuf => return error.InvalidBinaryRecord,
        else => return error.InvalidBinaryRecord,
    }
    const event = try validateParsedEvent(try wire.fromWireEvent(root, wire_event));
    return .{ .event = event, .consumed_len = consumed_len };
}

fn validateParsedEvent(event: schema.AuditEvent) !schema.AuditEvent {
    const expected_hash = hash.computeRecordHash(event);
    if (expected_hash != event.header.record_hash) return error.InvalidRecordHash;
    return event;
}
