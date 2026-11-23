/// Zig view of the multipart model-content wire contract.
///
/// The one definition is tk_multipart_wire.h (reached through audit_schema.h's
/// translate-c step as `audit_mod`); nothing here mirrors a C struct or number
/// by hand. These aliases give Zig consumers typed names for the bounds, and
/// the tests pin the Zig-visible values to the approved ones in the tkagnt
/// fd_stem migration plan ("Chosen numeric bounds") and the canonical
/// whole-message hash to the C implementation's.
const std = @import("std");
const audit_mod = @import("audit_mod");

pub const Header = audit_mod.TkMpHeader;

pub const wire_version: u16 = audit_mod.TK_MP_WIRE_VERSION;
pub const header_size: usize = audit_mod.TK_MP_HDR_SZ;
pub const link_mtu: usize = audit_mod.TK_MP_LINK_MTU;
pub const frag_payload_max: usize = audit_mod.TK_MP_FRAG_PAYLOAD_MAX;
pub const max_message_bytes: usize = audit_mod.TK_MP_MAX_MESSAGE_BYTES;
pub const max_frags: usize = audit_mod.TK_MP_MAX_FRAGS;
pub const link_depth: usize = audit_mod.TK_MP_LINK_DEPTH;
pub const max_prompt_messages: usize = audit_mod.TK_MP_MAX_PROMPT_MESSAGES;
pub const partial_timeout_ms: u64 = audit_mod.TK_MP_PARTIAL_TIMEOUT_MS;
/// Firedancer's fd_frag_meta_t.sz is 16 bits: no fragment may exceed this.
pub const fd_sz_ceiling: usize = audit_mod.TK_MP_FD_SZ_CEILING;

pub const hash_k0: u64 = audit_mod.TK_MP_HASH_K0;
pub const hash_k1: u64 = audit_mod.TK_MP_HASH_K1;

pub const Direction = enum(u8) {
    request = audit_mod.TK_MP_DIR_REQUEST,
    result = audit_mod.TK_MP_DIR_RESULT,
};

pub const ContentType = enum(u8) {
    chat = audit_mod.TK_MP_CT_CHAT,
    embedding = audit_mod.TK_MP_CT_EMBEDDING,
};

/// Fragments a message of `len` bytes occupies under the canonical framing.
pub fn fragCount(len: usize) usize {
    return (len + frag_payload_max - 1) / frag_payload_max;
}

/// Canonical whole-message hash: SipHash-1-3 under the multipart domain keys.
/// Independent of Firedancer's fd_siphash13 so the C implementation is checked
/// against the algorithm, not against itself.
pub fn messageHash(msg: []const u8) u64 {
    var key: [16]u8 = undefined;
    std.mem.writeInt(u64, key[0..8], hash_k0, .little);
    std.mem.writeInt(u64, key[8..16], hash_k1, .little);
    return std.hash.SipHash64(1, 3).toInt(msg, &key);
}

/// Control bits of a fragment (fd_frag_meta_ctl with orig 0, err 0).
pub fn ctlBits(som: bool, eom: bool) u16 {
    return @as(u16, @intFromBool(som)) | (@as(u16, @intFromBool(eom)) << 1);
}

/// One fragment of a logical message: its size on the link and boundary bits.
pub const Fragment = struct {
    sz: usize,
    som: bool,
    eom: bool,
};

pub const SendError = error{ EmptyMessage, MessageTooLarge };

/// Builds fragment `idx` of `msg` into `out` (header plus payload) under the
/// canonical framing in tk_multipart_wire.h, the same bytes tk_mp_tx_frag
/// produces. `idx` must be below `fragCount(msg.len)`. The whole-message hash
/// is passed in so a sender hashes once, not per fragment.
pub fn writeFragment(
    out: *[link_mtu]u8,
    direction: Direction,
    content_type: ContentType,
    run_id: u64,
    model_request_id: u64,
    msg: []const u8,
    message_hash: u64,
    idx: usize,
) Fragment {
    const frags = fragCount(msg.len);
    std.debug.assert(msg.len > 0 and msg.len <= max_message_bytes and idx < frags);
    const off = idx * frag_payload_max;
    const len = @min(msg.len - off, frag_payload_max);

    var h = std.mem.zeroes(Header);
    h.version = wire_version;
    h.direction = @backingInt(direction);
    h.content_type = @backingInt(content_type);
    h.total_len = @intCast(msg.len);
    h.frag_off = @intCast(off);
    h.frag_len = @intCast(len);
    h.frag_idx = @intCast(idx);
    h.frag_cnt = @intCast(frags);
    h.run_id = run_id;
    h.model_request_id = model_request_id;
    h.message_hash = message_hash;
    @memcpy(out[0..header_size], std.mem.asBytes(&h));
    @memcpy(out[header_size..][0..len], msg[off..][0..len]);
    return .{ .sz = header_size + len, .som = idx == 0, .eom = idx == frags - 1 };
}

/// Pinned across languages: test_multipart.c asserts the same constant for the
/// same bytes, so the C sender and any Zig verifier agree on the canonical hash.
pub const hash_vector_input = "tickoni multipart vector";
pub const hash_vector_expected: u64 = 12765886097428848014;

test "bounds match the approved contract" {
    try std.testing.expectEqual(@as(u16, 1), wire_version);
    try std.testing.expectEqual(@as(usize, 64), header_size);
    try std.testing.expectEqual(@as(usize, 8192), link_mtu);
    try std.testing.expectEqual(@as(usize, 8128), frag_payload_max);
    try std.testing.expectEqual(@as(usize, 262_144), max_message_bytes);
    try std.testing.expectEqual(@as(usize, 33), max_frags);
    try std.testing.expectEqual(@as(usize, 32), link_depth);
    try std.testing.expectEqual(@as(usize, 16), max_prompt_messages);
    try std.testing.expectEqual(@as(u64, 2000), partial_timeout_ms);
}

test "a fragment fits the 16-bit fd sz and a maximum message exceeds one fragment and the link depth" {
    try std.testing.expectEqual(@as(usize, 65_535), fd_sz_ceiling);
    try std.testing.expect(link_mtu <= fd_sz_ceiling);
    try std.testing.expectEqual(link_mtu, header_size + frag_payload_max);
    try std.testing.expect(max_message_bytes > fd_sz_ceiling);
    try std.testing.expectEqual(max_frags, fragCount(max_message_bytes));
    try std.testing.expect(max_frags > link_depth);
}

test "header layout is the 64-byte wire record" {
    try std.testing.expectEqual(header_size, @sizeOf(Header));
    try std.testing.expectEqual(@as(usize, 4), @offsetOf(Header, "total_len"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(Header, "run_id"));
    try std.testing.expectEqual(@as(usize, 40), @offsetOf(Header, "message_hash"));
}

test "fragment count follows the canonical framing at its boundaries" {
    try std.testing.expectEqual(@as(usize, 1), fragCount(1));
    try std.testing.expectEqual(@as(usize, 1), fragCount(frag_payload_max));
    try std.testing.expectEqual(@as(usize, 2), fragCount(frag_payload_max + 1));
    try std.testing.expectEqual(@as(usize, 9), fragCount(65_536)); // one fd fragment cannot hold it
}

test "direction and content tags are distinct non-zero values" {
    try std.testing.expect(@backingInt(Direction.request) != @backingInt(Direction.result));
    try std.testing.expect(@backingInt(Direction.request) != 0 and @backingInt(Direction.result) != 0);
    try std.testing.expect(@backingInt(ContentType.chat) != @backingInt(ContentType.embedding));
}

test "canonical hash vector matches the pinned value" {
    try std.testing.expectEqual(hash_vector_expected, messageHash(hash_vector_input));
}

test "writeFragment frames a message the way the C sender does" {
    // Three fragments: two full ones and a short tail.
    var msg: [2 * frag_payload_max + 100]u8 = undefined;
    for (&msg, 0..) |*b, i| b.* = @truncate(i *% 7);
    const hash = messageHash(&msg);
    var out: [link_mtu]u8 = undefined;
    var total: usize = 0;
    for (0..3) |i| {
        const f = writeFragment(&out, .request, .chat, 5, 77, &msg, hash, i);
        var h: Header = undefined;
        @memcpy(std.mem.asBytes(&h), out[0..header_size]);
        try std.testing.expectEqual(wire_version, h.version);
        try std.testing.expectEqual(@as(u32, msg.len), h.total_len);
        try std.testing.expectEqual(@as(u32, 3), h.frag_cnt);
        try std.testing.expectEqual(@as(u32, @intCast(i)), h.frag_idx);
        try std.testing.expectEqual(@as(u32, @intCast(i * frag_payload_max)), h.frag_off);
        try std.testing.expectEqual(hash, h.message_hash);
        try std.testing.expectEqual(i == 0, f.som);
        try std.testing.expectEqual(i == 2, f.eom);
        try std.testing.expect(f.sz <= link_mtu and f.sz <= fd_sz_ceiling);
        try std.testing.expectEqual(@as(usize, h.frag_len), f.sz - header_size);
        try std.testing.expectEqualSlices(u8, msg[h.frag_off..][0..h.frag_len], out[header_size..f.sz]);
        total += h.frag_len;
    }
    try std.testing.expectEqual(msg.len, total);
}

test "a message above the fd fragment size splits into fragments that each fit it" {
    const len = fd_sz_ceiling + 1;
    try std.testing.expect(fragCount(len) > 1);
    try std.testing.expect(frag_payload_max + header_size <= fd_sz_ceiling);
}

test "ctlBits packs SOM and EOM like fd_frag_meta_ctl" {
    try std.testing.expectEqual(@as(u16, 3), ctlBits(true, true));
    try std.testing.expectEqual(@as(u16, 1), ctlBits(true, false));
    try std.testing.expectEqual(@as(u16, 2), ctlBits(false, true));
    try std.testing.expectEqual(@as(u16, 0), ctlBits(false, false));
}
