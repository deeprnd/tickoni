/// Audit constants — loaded from C header via translate-c (audit_mod).
/// The C header defines these as static const uint64_t so translate-c
/// generates proper Zig compile-time constants.
/// Values come from: src/tickoni/c_abi/shim/audit_consts.h
const audit_mod = @import("audit_mod");

pub const AUDIT_HASH_K0: u64 = audit_mod.AUDIT_HASH_K0;
pub const AUDIT_HASH_K1: u64 = audit_mod.AUDIT_HASH_K1;
pub const AUDIT_INITIAL_HASH: u64 = audit_mod.AUDIT_INITIAL_HASH;
