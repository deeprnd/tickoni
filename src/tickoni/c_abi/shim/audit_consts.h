/* Audit hash constants — shared between C and Zig.
   audit_schema.h includes this file for the C side.
   Zig code references them via translate-c module (audit_mod):
   audit_mod.AUDIT_HASH_K0, audit_mod.AUDIT_HASH_K1, audit_mod.AUDIT_INITIAL_HASH. */
#ifndef __AUDIT_CONSTS_H__
#define __AUDIT_CONSTS_H__

#include <stdint.h>

#define AUDIT_HASH_K0  0x0000544455414B54ULL  /* SipHash key k0 ("TKAUDT\0\0" LE) */
#define AUDIT_HASH_K1  2                        /* SipHash key k1 (schema version) */
#define AUDIT_INITIAL_HASH 0x0000000000000000ULL  /* Initial prev_hash (identity seed) */

#endif /* __AUDIT_CONSTS_H__ */
