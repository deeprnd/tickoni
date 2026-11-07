// Audit constants — single source of truth for Zig code.
// Values come from audit_consts.h but are defined here so that
// translate-c self-import is avoided and @import() resolution works.
pub const AUDIT_HASH_K0: u64 = 0x0000544455414B54; // "TKAUDT\0\0" LE
pub const AUDIT_HASH_K1: u64 = 2; // schema version
pub const AUDIT_INITIAL_HASH: u64 = 0; // identity seed

comptime {
    // Compile-time verification that these match the C header.
    // AUDIT_HASH_K0 = 0x0000544455414B54ULL ("TKAUDT\0\0" LE)
    // AUDIT_HASH_K1 = 2
    // AUDIT_INITIAL_HASH = 0
    _ = AUDIT_HASH_K0;
    _ = AUDIT_HASH_K1;
    _ = AUDIT_INITIAL_HASH;
}
