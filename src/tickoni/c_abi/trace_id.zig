//! A request trace id as it travels in the C wire structs (TK_TRACE_ID_SZ
//! opaque bytes, audit_schema.h) and as a u128 in Zig code where a number is
//! more convenient.  The conversion is little-endian, so a u128 written here
//! puts the same bytes in a record as the former `__uint128_t` field did on
//! x86_64/ARM64, and the audit hash over those bytes is unchanged.

const std = @import("std");
const audit_mod = @import("audit_mod");

pub const len = audit_mod.TK_TRACE_ID_SZ;
pub const Bytes = [len]u8;

pub fn fromInt(v: u128) Bytes {
    var out: Bytes = undefined;
    std.mem.writeInt(u128, &out, v, .little);
    return out;
}

pub fn toInt(id: Bytes) u128 {
    return std.mem.readInt(u128, &id, .little);
}

test "trace id round-trips through its little-endian bytes" {
    const v: u128 = 0x0f0e0d0c0b0a09080706050403020100;
    const b = fromInt(v);
    for (b, 0..) |byte, i| try std.testing.expectEqual(@as(u8, @intCast(i)), byte);
    try std.testing.expectEqual(v, toInt(b));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(Bytes));
}
