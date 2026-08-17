const schema = @import("audit_schema");
const binary = @import("binary.zig");
const hash = @import("hash.zig");
const jsonl = @import("jsonl.zig");

pub const max_binary_len: usize = 256;

pub const ParsedBinary = struct {
    event: schema.AuditEvent,
    consumed_len: usize,
};

pub fn buildEvent(header_without_hash: schema.Header, payload: schema.AuditEvent.Payload) schema.AuditEvent {
    var event = schema.AuditEvent{ .header = header_without_hash, .payload = payload };
    const computed_hash = computeRecordHash(event);
    event.header.record_hash = computed_hash;
    return event;
}

pub fn computeRecordHash(event: schema.AuditEvent) u64 {
    return hash.computeRecordHash(event);
}

pub fn auditEventsEql(a: schema.AuditEvent, b: schema.AuditEvent) bool {
    return hash.auditEventsEql(a, b);
}

pub fn checkSchemaVersion(version: u16) error{UnknownSchemaVersion}!void {
    if (version > schema.audit_schema_version) return error.UnknownSchemaVersion;
}

pub fn parseRecordType(tag: u8) error{UnknownRecordType}!schema.RecordType {
    const e = @typeInfo(schema.RecordType).@"enum";
    inline for (e.field_names, e.field_values) |name, value| {
        if (value == tag) return @field(schema.RecordType, name);
    }
    return error.UnknownRecordType;
}

pub fn peekBinaryLen(input: []const u8) error{UnexpectedEof}!usize {
    return binary.peekBinaryLen(input);
}

pub fn formatBinary(buf: []u8, event: schema.AuditEvent) ![]u8 {
    return binary.formatBinary(buf, event);
}

pub fn parseBinary(input: []const u8) !ParsedBinary {
    return binary.parseBinary(input);
}

pub fn formatJsonLine(event: schema.AuditEvent, writer: anytype) !void {
    return jsonl.formatJsonLine(event, writer);
}
