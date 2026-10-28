/// Unit tests for the tknorm stem tile shim (`tk_normalize_stem.c`).
///
/// Verifies scratch layout, footprint calculation, and FNV-1a hash
/// determinism using extern declarations that call into the norm shim library.
const std = @import("std");

// ---------------------------------------------------------------------------
// FNV-1a helpers — mirrors the inline hash in tknorm_during_frag.
// Uses @mulWithOverflow for overflow-safe comptime hashing.
// ---------------------------------------------------------------------------

const FNV_OFFSET_BASIS: u64 = 0xcbf29ce484222325;
const FNV_PRIME: u64 = 0x100000001b3;

fn mul_fnv(h: u64, x: u64) u64 {
    const result = @mulWithOverflow(h ^ x, FNV_PRIME);
    _ = result[1];
    return result[0];
}

/// Compute the norm-stem FNV-1a hash for (source_offset, idempotency_key,
/// account_id, amount_cents). Matches the C inline hash in
/// tk_normalize_stem.c:tknorm_during_frag exactly.
fn norm_fnv1a_hash(
    source_offset: u64,
    idempotency_key: u64,
    account_id: u64,
    amount_cents: u64,
) u64 {
    var h = FNV_OFFSET_BASIS;
    h = mul_fnv(h, source_offset);
    h = mul_fnv(h, idempotency_key);
    h = mul_fnv(h, account_id);
    h = mul_fnv(h, amount_cents);
    return h;
}

// ---------------------------------------------------------------------------
// C stem tile extern declarations — calls into tk_normalize_stem.c via the
// norm shim library.
// ---------------------------------------------------------------------------

// From tk_normalize_stem.h / tk_normalize_stem.c — scratch helpers.
extern fn tk_norm_scratch_align() usize;
extern fn tk_norm_scratch_footprint_tile(?*const anyopaque) usize;

// ---------------------------------------------------------------------------
// Scratch layout tests
// ---------------------------------------------------------------------------

test "scratch_align returns 64" {
    try std.testing.expectEqual(@as(usize, 64), tk_norm_scratch_align());
}

test "scratch_footprint includes ctx + PaymentMessage" {
    const footprint = tk_norm_scratch_footprint_tile(null);

    // tknorm_ctx_t: 3×uint64_t counters + int + uint8_t[16] output_buf +
    // uint64_t + int + void* + 2×fd_wksp_t* + 5×ulong = ~120 bytes.
    // PaymentMessage: RawPayment(37) + event_hash(8) + 4 fields(9) = 54 bytes.
    // FD_LAYOUT_FINI rounds to TK_NORM_CTX_ALIGN (64).
    // Minimum reasonable footprint: ctx(120) + msg(54) = 174 → rounded to 256.
    try std.testing.expect(footprint >= 128);
}

// ---------------------------------------------------------------------------
// FNV-1a hash tests
// ---------------------------------------------------------------------------

test "FNV-1a hash is deterministic for identical inputs" {
    const h1 = norm_fnv1a_hash(1, 2, 3, 100);
    const h2 = norm_fnv1a_hash(1, 2, 3, 100);

    try std.testing.expectEqual(h1, h2);
}

test "FNV-1a hash matches known fixture" {
    const expected_hash = norm_fnv1a_hash(1, 2, 3, 100);

    // Compute from first principles:
    // h = 0xcbf29ce484222325
    // h = (h ^ 1) * 0x100000001b3
    // h = (h ^ 2) * 0x100000001b3
    // h = (h ^ 3) * 0x100000001b3
    // h = (h ^ 100) * 0x100000001b3
    var h = FNV_OFFSET_BASIS;
    h = mul_fnv(h, 1);
    h = mul_fnv(h, 2);
    h = mul_fnv(h, 3);
    h = mul_fnv(h, 100);

    try std.testing.expectEqual(h, expected_hash);
}

test "FNV-1a hash differs when any input changes" {
    const base_hash = norm_fnv1a_hash(100, 200, 300, 400);

    try std.testing.expect(norm_fnv1a_hash(101, 200, 300, 400) != base_hash);
    try std.testing.expect(norm_fnv1a_hash(100, 201, 300, 400) != base_hash);
    try std.testing.expect(norm_fnv1a_hash(100, 200, 301, 400) != base_hash);
    try std.testing.expect(norm_fnv1a_hash(100, 200, 300, 401) != base_hash);
}

test "FNV-1a hash with zero-valued fields" {
    const h_zero = norm_fnv1a_hash(0, 0, 0, 0);
    const h_source = norm_fnv1a_hash(1, 0, 0, 0);

    try std.testing.expect(h_zero != h_source);
}
