/* tk_capsule_hash.h — the content hash of a case capsule: the one definition
   tkcase (which records the capsule) and tkrepl (which replays it) both fold,
   so the two cannot drift apart.  C only: not part of the translate-c step.

   A chain over the capsule's events in order, each link a Firedancer SipHash1-3
   keyed with the previous link:

     h_0 = TK_CAPSULE_HASH_INIT
     h_i = SipHash13( k0 = TK_CAPSULE_HASH_K0, k1 = h_{i-1}, canonical(event_i) )

   canonical(event) is the envelope's defined fields in layout order, never
   padding or the unused tail of the body union, so equal events hash equal on
   every run.  The kind's own fields are covered by event_hash, tknorm's
   canonical hash of them.  pipeline_hops is transport bookkeeping and is left
   out.

   Include after firedancer.h and audit_schema.h. */
#ifndef __TK_CAPSULE_HASH_H__
#define __TK_CAPSULE_HASH_H__

#include "ballet/siphash13/fd_siphash13.h"

#define TK_CAPSULE_HASH_K0    0x0000535041434B54UL   /* "TKCAPS\0\0" LE */
#define TK_CAPSULE_HASH_INIT  0UL

static inline uint64_t
tk_capsule_hash_append( uint64_t prev, TkEvent const * ev ) {
    fd_siphash13_t sip[1];
    fd_siphash13_init( sip, TK_CAPSULE_HASH_K0, prev );
    fd_siphash13_append( sip, (uchar const *)&ev->version,         sizeof(ev->version) );
    fd_siphash13_append( sip, (uchar const *)&ev->kind,            sizeof(ev->kind) );
    fd_siphash13_append( sip, (uchar const *)&ev->source,          sizeof(ev->source) );
    fd_siphash13_append( sip, (uchar const *)&ev->flags,           sizeof(ev->flags) );
    fd_siphash13_append( sip, (uchar const *)&ev->duplicate,       sizeof(ev->duplicate) );
    fd_siphash13_append( sip, (uchar const *)&ev->decision,        sizeof(ev->decision) );
    fd_siphash13_append( sip, ev->trace_id,                        sizeof(ev->trace_id) );
    fd_siphash13_append( sip, (uchar const *)&ev->idempotency_key, sizeof(ev->idempotency_key) );
    fd_siphash13_append( sip, (uchar const *)&ev->source_offset,   sizeof(ev->source_offset) );
    fd_siphash13_append( sip, (uchar const *)&ev->event_hash,      sizeof(ev->event_hash) );
    fd_siphash13_append( sip, (uchar const *)&ev->case_id,         sizeof(ev->case_id) );
    fd_siphash13_append( sip, ev->decided_by,                      sizeof(ev->decided_by) );
    return fd_siphash13_fini( sip );
}

#endif /* __TK_CAPSULE_HASH_H__ */
