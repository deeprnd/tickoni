/// Narrow Zig bindings over src/tickoni/c_abi/shim/ballet.c's tk_siphash13_*
/// primitives (real Firedancer fd_siphash13 underneath). Codec/schema hash
/// composition (field order, key selection) lives in Zig callers, not here.
const std = @import("std");

pub const Siphash13 = extern struct { bytes: [128]u8 align(128) = undefined, };

extern fn tk_siphash13_init(sip: *Siphash13, k0: u64, k1: u64) *Siphash13;
extern fn tk_siphash13_append(sip: *Siphash13, data: [*]const u8, sz: u64) *Siphash13;
extern fn tk_siphash13_fini(sip: *Siphash13) u64;

pub fn siphashInit(sip: *Siphash13, k0: u64, k1: u64) void { _ = tk_siphash13_init(sip, k0, k1); }

pub fn siphashAppend(sip: *Siphash13, data: []const u8) void { _ = tk_siphash13_append(sip, data.ptr, data.len); }

pub fn siphashFini(sip: *Siphash13) u64 { return tk_siphash13_fini(sip); }

test "Siphash13 matches the shim's opaque size and alignment" { try std.testing.expectEqual(@as(usize, 128), @sizeOf(Siphash13));
    try std.testing.expectEqual(@as(usize, 128), @alignOf(Siphash13)); }

test "siphash init/append/fini produces a deterministic, non-zero digest" {
    var sip: Siphash13 = .{};
    siphashInit(&sip, 0x1122334455667788, 42);
    siphashAppend(&sip, "hello");
    siphashAppend(&sip, "world");
    const h1 = siphashFini(&sip);
    try std.testing.expect(h1 != 0);

    var sip2: Siphash13 = .{};
    siphashInit(&sip2, 0x1122334455667788, 42);
    siphashAppend(&sip2, "hello");
    siphashAppend(&sip2, "world");
    try std.testing.expectEqual(h1, siphashFini(&sip2));
}

// ---------------------------------------------------------------------------
// Protobuf TLV encode/decode primitives (real Firedancer fd_pb_* underneath).
// Field IDs, submessage structure, and record-type dispatch are Tickoni
// schema logic and live in codec Zig callers, not here.
// ---------------------------------------------------------------------------

pub const pb_encoder_depth_max: usize = 63;

pub const PbEncoder = extern struct { buf0: ?[*]u8 = null,
    buf1: ?[*]u8 = null,
    cur: ?[*]u8 = null,
    depth: u32 = 0,
    lp_off: [pb_encoder_depth_max]u32 = [_]u32{ 0 }**pb_encoder_depth_max,
};

pub const PbInbuf = extern struct { cur: ?[*]const u8 = null,
    end: ?[*]const u8 = null, };

/// Matches the shim's anonymous union (varint/i64/len/i32 all alias the same
/// 8 bytes); only .varint and .len are read by any current caller.
pub const PbTlv = extern struct { wire_type: u32 = 0,
    field_id: u32 = 0,
    varint: u64 = 0,

    pub fn len(self: *const PbTlv) u64 {
        return self.varint; }
};

pub const pb_wire_type_varint: u32 = 0;
pub const pb_wire_type_i64: u32 = 1;
pub const pb_wire_type_len: u32 = 2;
pub const pb_wire_type_i32: u32 = 5;

extern fn tk_pb_encoder_init(encoder: *PbEncoder, out: [*]u8, out_sz: u64) ?*PbEncoder;
extern fn tk_pb_encoder_fini(encoder: *PbEncoder) c_int;
extern fn tk_pb_encoder_out_sz(encoder: *PbEncoder) u64;
extern fn tk_pb_submsg_open(encoder: *PbEncoder, field_id: u32) c_int;
extern fn tk_pb_submsg_close(encoder: *PbEncoder) c_int;
extern fn tk_pb_push_uint32(encoder: *PbEncoder, field_id: u32, value: u32) c_int;
extern fn tk_pb_push_uint64(encoder: *PbEncoder, field_id: u32, value: u64) c_int;
extern fn tk_pb_push_int64(encoder: *PbEncoder, field_id: u32, value: i64) c_int;
extern fn tk_pb_push_bytes(encoder: *PbEncoder, field_id: u32, bytes: [*]const u8, bytes_sz: u64) c_int;
extern fn tk_pb_inbuf_init(buf: *PbInbuf, data: [*]const u8, data_sz: u64) ?*PbInbuf;
extern fn tk_pb_inbuf_sz(buf: *PbInbuf) u64;
extern fn tk_pb_inbuf_cur(buf: *PbInbuf) [*]const u8;
extern fn tk_pb_inbuf_advance(buf: *PbInbuf, bytes_sz: u64) void;
extern fn tk_pb_read_tlv(buf: *PbInbuf, tlv: *PbTlv) c_int;

pub fn pbEncoderInit(encoder: *PbEncoder, out: []u8) bool { return tk_pb_encoder_init(encoder, out.ptr, out.len) != null; }
pub fn pbEncoderFini(encoder: *PbEncoder) bool { return tk_pb_encoder_fini(encoder) != 0; }
pub fn pbEncoderOutSz(encoder: *PbEncoder) u64 { return tk_pb_encoder_out_sz(encoder); }
pub fn pbSubmsgOpen(encoder: *PbEncoder, field_id: u32) bool { return tk_pb_submsg_open(encoder, field_id) != 0; }
pub fn pbSubmsgClose(encoder: *PbEncoder) bool { return tk_pb_submsg_close(encoder) != 0; }
pub fn pbPushUint32(encoder: *PbEncoder, field_id: u32, value: u32) bool { return tk_pb_push_uint32(encoder, field_id, value) != 0; }
pub fn pbPushUint64(encoder: *PbEncoder, field_id: u32, value: u64) bool { return tk_pb_push_uint64(encoder, field_id, value) != 0; }
pub fn pbPushInt64(encoder: *PbEncoder, field_id: u32, value: i64) bool { return tk_pb_push_int64(encoder, field_id, value) != 0; }
pub fn pbPushBytes(encoder: *PbEncoder, field_id: u32, bytes: []const u8) bool { return tk_pb_push_bytes(encoder, field_id, bytes.ptr, bytes.len) != 0; }
pub fn pbInbufInit(buf: *PbInbuf, data: []const u8) void { _ = tk_pb_inbuf_init(buf, data.ptr, data.len); }
pub fn pbInbufSz(buf: *PbInbuf) u64 { return tk_pb_inbuf_sz(buf); }
pub fn pbInbufCur(buf: *PbInbuf) [*]const u8 { return tk_pb_inbuf_cur(buf); }
pub fn pbInbufAdvance(buf: *PbInbuf, sz: u64) void { tk_pb_inbuf_advance(buf, sz); }
pub fn pbReadTlv(buf: *PbInbuf, tlv: *PbTlv) bool { return tk_pb_read_tlv(buf, tlv) != 0; }

test "PbEncoder/PbInbuf/PbTlv match the shim's layout" { try std.testing.expectEqual(@as(usize, 8 * 3 + 4 + 4 * pb_encoder_depth_max), @sizeOf(PbEncoder));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(PbEncoder, "cur"));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(PbInbuf, "cur"));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(PbTlv, "wire_type"));
    try std.testing.expectEqual(@as(usize, 4), @offsetOf(PbTlv, "field_id")); }

test "pb encode/decode round-trips a single varint field" {
    var buf: [64]u8 = undefined;
    var enc: PbEncoder = .{};
    try std.testing.expect(pbEncoderInit(&enc, &buf));
    try std.testing.expect(pbPushUint64(&enc, 1, 424242));
    const written = pbEncoderOutSz(&enc);
    try std.testing.expect(pbEncoderFini(&enc));

    var inbuf: PbInbuf = .{};
    pbInbufInit(&inbuf, buf[0..written]);
    var tlv: PbTlv = .{};
    try std.testing.expect(pbReadTlv(&inbuf, &tlv));
    try std.testing.expectEqual(pb_wire_type_varint, tlv.wire_type);
    try std.testing.expectEqual(@as(u32, 1), tlv.field_id);
    try std.testing.expectEqual(@as(u64, 424242), tlv.varint);
}
