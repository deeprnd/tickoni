/* Audit hash constants — single source of truth for C and Zig.
   Defined as static const (C internal linkage) so translate-c can
   extract the values as compile-time constants in the Zig bindings.
   Consumers use audit_mod.AUDIT_HASH_K0 etc. from @import("audit_mod").
   See: src/tickoni/codec/audit/hash.zig, audit_sink.zig */
#ifndef __AUDIT_CONSTS_H__
#define __AUDIT_CONSTS_H__

#include <stdint.h>

static const uint64_t AUDIT_HASH_K0 = 0x0000544455414B54ULL;  /* SipHash k0: "TKAUDT\0\0" LE */
static const uint64_t AUDIT_HASH_K1 = 2;                      /* SipHash k1: schema version */
static const uint64_t AUDIT_INITIAL_HASH = 0ULL;              /* Initial prev_hash (identity seed) */

#endif /* __AUDIT_CONSTS_H__ */
