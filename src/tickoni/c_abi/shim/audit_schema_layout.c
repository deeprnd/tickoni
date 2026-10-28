/* audit_schema_layout.c — C helpers for Zig parity checks.
   audit_schema.h is the single source of truth for the Header layout. */

#include "audit_schema.h"

size_t audit_header_sizeof(void) { return sizeof(AuditHeader); }
size_t audit_header_alignof(void) { return _Alignof(AuditHeader); }

/* FNV-1a hash — mirrors the inline hash in tk_audit_during_frag.
   Both C and Zig call this with the same 5-field signature so the
   test can compare C output against the Zig fnv1a_hash_6 helper. */
uint64_t audit_fnv1a_hash_6(
    uint64_t seq,
    uint64_t source_offset,
    uint64_t prev_hash,
    uint8_t  outcome,
    uint64_t source_event_hash)
{
    uint64_t h = AUDIT_SEED;
    h = (h ^ seq)              * 0x100000001b3ULL;
    h = (h ^ source_offset)    * 0x100000001b3ULL;
    h = (h ^ prev_hash)        * 0x100000001b3ULL;
    h = (h ^ (uint64_t)outcome) * 0x100000001b3ULL;
    h = (h ^ source_event_hash) * 0x100000001b3ULL;
    return h;
}
