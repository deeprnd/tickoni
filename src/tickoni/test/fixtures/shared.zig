/// Shared test-fixture utilities used across investment fixtures.
///
/// These helpers are intentionally kept here rather than in a runtime
/// module because they produce values for deterministic audit chains,
/// not for the live event pipeline.

const std = @import("std");
const audit = @import("audit");
const runtime = @import("runtime");
const tile_ids = runtime.tile_ids;

/// Populate a `[N]u8` fixed-length buffer from `value`, zero-padding the
/// remainder.  Panics when `value` exceeds `N` or contains non-printable
/// ASCII bytes — this is a test-fixture invariant, not a runtime guard.
pub fn parseFixedAsciiBytes(comptime N: usize, value: []const u8) [N]u8 {
    if (value.len > N) @panic("fixed ASCII field too long");
    var out = std.mem.zeroes([N]u8);
    for (value, 0..) |byte, idx| {
        if (byte < 0x20 or byte > 0x7e) @panic("non-ASCII byte in fixed field");
        out[idx] = byte;
    }
    return out;
}

/// Build an `audit.Header` with the canonical schema version and a
/// zeroed timestamp/record_hash so `tkaudt` can compute them.

pub fn header(
    seq: u64,
    tile_id: []const u8,
    logical_actor_id: u64,
    capability_envelope_id: u64,
    run_id: u64,
    prev_hash: u64,
) audit.Header {
    var hdr = std.mem.zeroes(audit.Header);
    hdr.schema_version = audit.audit_schema_version;
    hdr.run_id = run_id;
    hdr.seq = seq;
    hdr.source_offset = seq + 1;
    hdr.tile_id = parseFixedAsciiBytes(6, tile_id);
    hdr.logical_actor_id = logical_actor_id;
    hdr.policy_version = parseFixedAsciiBytes(32, "tickoni.v1");
    hdr.capability_envelope_id = capability_envelope_id;
    hdr.timestamp_ns = 0;
    hdr.prev_hash = prev_hash;
    hdr.record_hash = 0;
    return hdr;
}
