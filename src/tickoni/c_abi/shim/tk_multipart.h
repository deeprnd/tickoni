/* tk_multipart.h — bounded reassembly and fragmentation for multipart model
   content.  Header-only, static inline, no global state.  The wire contract
   (TkMpHeader, bounds, canonical framing rules) is tk_multipart_wire.h.

   Receiver (tk_mp_rx_t): one partial message at a time per input link.  Call
   tk_mp_rx_feed() from AFTER_FRAG with the fragment already staged out of the
   dcache by DURING_FRAG (callback contract in stem_helpers.h); it only mutates
   the receiver.  A message is delivered only on TK_MP_COMPLETE, after every
   byte, both boundaries and the whole-message hash have verified, so a caller
   can never act on a partial or corrupt message.

   On any TK_MP_ERR_* the receiver drops the message it was building and, when
   the failing fragment is not the last, swallows the rest of that message
   (TK_MP_DISCARD) until the next SOM.  `rx->fail` carries the identity of the
   message that failed so the owner can record an audited terminal failure; it
   is meaningful only right after an ERR status. */
#ifndef __TK_MULTIPART_H__
#define __TK_MULTIPART_H__

#include <string.h>

#include "tk_multipart_wire.h"
#include "../../../ballet/siphash13/fd_siphash13.h"

typedef enum {
    TK_MP_PARTIAL  = 0,   /* fragment accepted; message not complete */
    TK_MP_COMPLETE = 1,   /* message complete and verified; bytes in rx->buf[0, rx->cur.total_len) */
    TK_MP_DISCARD  = 2,   /* fragment of an already-failed message, dropped */

    TK_MP_ERR_VERSION     = 16,  /* wrong wire version */
    TK_MP_ERR_SIZE        = 17,  /* sz/frag_len inconsistent, empty, or over the link MTU */
    TK_MP_ERR_BOUNDARY    = 18,  /* SOM/EOM disagree with frag_idx/frag_cnt, or EOM before all bytes */
    TK_MP_ERR_OVERSIZE    = 19,  /* total_len zero or above TK_MP_MAX_MESSAGE_BYTES, or frag_cnt wrong */
    TK_MP_ERR_IDENTITY    = 20,  /* direction/content/id/length/hash differ from the message in progress */
    TK_MP_ERR_GAP         = 21,  /* a fragment (or its offset) was skipped */
    TK_MP_ERR_DUPLICATE   = 22,  /* a fragment index was repeated */
    TK_MP_ERR_OVERLAP     = 23,  /* offset rewinds into bytes already received */
    TK_MP_ERR_OVERFLOW    = 24,  /* bytes would pass total_len or the buffer */
    TK_MP_ERR_HASH        = 25,  /* reassembled bytes do not match message_hash */
    TK_MP_ERR_INTERLEAVED = 26,  /* a new SOM arrived mid-message: the old message is dropped and this
                                    fragment was NOT consumed; feed it again */
    TK_MP_ERR_TIMEOUT     = 27,  /* partial message outlived its deadline */
    TK_MP_ERR_ORPHAN      = 28   /* continuation fragment with no message in progress */
} tk_mp_status_t;

/* Identity of one logical message. */
typedef struct {
    uint8_t   direction;
    uint8_t   content_type;
    uint32_t  total_len;
    uint32_t  frag_cnt;
    uint64_t  run_id;
    uint64_t  model_request_id;
    uint64_t  message_hash;
} tk_mp_id_t;

/* Nanosecond time and durations.  Must be 64-bit: `long` is 32-bit on Windows
   (LLP64), where it wraps every ~4.29 s.  Callers read the clock with
   fd_log_wallclock_nanos(), not fd_log_wallclock(). */
typedef long long tk_ns_t;

typedef struct {
    int         active;         /* a partial message is being built */
    int         discard;        /* swallow continuation fragments until the next SOM */
    uint8_t     expect_dir;     /* TK_MP_DIR_* this link carries */
    tk_mp_id_t  cur;            /* message in progress, or the last completed one */
    tk_mp_id_t  fail;           /* message that failed on the last ERR status */
    uint32_t    next_idx;
    uint32_t    next_off;
    tk_ns_t     deadline;       /* `now` value at which the partial message times out */
    tk_ns_t     timeout;        /* same units as `now` */
    uint8_t *   buf;            /* caller-owned, capacity >= TK_MP_MAX_MESSAGE_BYTES */
} tk_mp_rx_t;

/* Number of fragments a message of `len` bytes occupies. */
static inline ulong
tk_mp_frag_cnt( ulong len ) {
    return (len + (ulong)TK_MP_FRAG_PAYLOAD_MAX - 1UL) / (ulong)TK_MP_FRAG_PAYLOAD_MAX;
}

/* Canonical whole-message hash: SipHash-1-3 over the raw message bytes under
   the multipart domain keys. */
static inline uint64_t
tk_mp_message_hash( uint8_t const * msg, ulong len ) {
    fd_siphash13_t sip[1];
    fd_siphash13_init( sip, TK_MP_HASH_K0, TK_MP_HASH_K1 );
    fd_siphash13_append( sip, msg, len );
    return fd_siphash13_fini( sip );
}

static inline void
tk_mp_rx_init( tk_mp_rx_t * rx, uint8_t expect_dir, uint8_t * buf, tk_ns_t timeout ) {
    memset( rx, 0, sizeof(*rx) );
    rx->expect_dir = expect_dir;
    rx->buf        = buf;
    rx->timeout    = timeout;
}

static inline tk_mp_id_t
tk_mp_id_of( TkMpHeader const * h ) {
    tk_mp_id_t id;
    id.direction        = h->direction;
    id.content_type     = h->content_type;
    id.total_len        = h->total_len;
    id.frag_cnt         = h->frag_cnt;
    id.run_id           = h->run_id;
    id.model_request_id = h->model_request_id;
    id.message_hash     = h->message_hash;
    return id;
}

static inline int
tk_mp_id_eq( tk_mp_id_t const * a, tk_mp_id_t const * b ) {
    return a->direction==b->direction && a->content_type==b->content_type &&
           a->total_len==b->total_len && a->frag_cnt==b->frag_cnt &&
           a->run_id==b->run_id && a->model_request_id==b->model_request_id &&
           a->message_hash==b->message_hash;
}

/* Drops the message in progress.  `eom` says whether the failing fragment was
   the last one of its message: if not, more of it is coming and is swallowed. */
static inline tk_mp_status_t
tk_mp_rx_fail( tk_mp_rx_t * rx, tk_mp_id_t const * id, int eom, tk_mp_status_t why ) {
    rx->fail    = *id;
    rx->active  = 0;
    rx->discard = !eom;
    return why;
}

/* Validates the fields of one fragment that stand alone, i.e. without the
   message in progress.  Returns 0 if acceptable, else the TK_MP_ERR_* code. */
static inline tk_mp_status_t
tk_mp_hdr_check( TkMpHeader const * h, ulong sz, int som, int eom, uint8_t expect_dir ) {
    if( h->version!=TK_MP_WIRE_VERSION )                         return TK_MP_ERR_VERSION;
    if( sz<=(ulong)TK_MP_HDR_SZ || sz>(ulong)TK_MP_LINK_MTU )    return TK_MP_ERR_SIZE;
    if( h->frag_len!=sz-(ulong)TK_MP_HDR_SZ )                    return TK_MP_ERR_SIZE;
    if( h->direction!=expect_dir )                               return TK_MP_ERR_IDENTITY;
    if( h->content_type<1 || h->content_type>TK_MP_CT_LAST )     return TK_MP_ERR_IDENTITY;
    if( h->total_len==0U || h->total_len>(uint32_t)TK_MP_MAX_MESSAGE_BYTES ) return TK_MP_ERR_OVERSIZE;
    if( h->frag_cnt!=tk_mp_frag_cnt( h->total_len ) )            return TK_MP_ERR_OVERSIZE;
    if( h->frag_idx>=h->frag_cnt )                               return TK_MP_ERR_BOUNDARY;
    if( som != (h->frag_idx==0U) )                               return TK_MP_ERR_BOUNDARY;
    if( eom != (h->frag_idx==h->frag_cnt-1U) )                   return TK_MP_ERR_BOUNDARY;
    /* Canonical framing: offset follows from the index, and only the last
       fragment may be short. */
    if( (ulong)h->frag_off != (ulong)h->frag_idx*(ulong)TK_MP_FRAG_PAYLOAD_MAX ) return TK_MP_ERR_OVERLAP;
    ulong want = eom ? (ulong)h->total_len-(ulong)h->frag_off : (ulong)TK_MP_FRAG_PAYLOAD_MAX;
    if( (ulong)h->frag_len!=want )                               return TK_MP_ERR_SIZE;
    return TK_MP_PARTIAL;
}

/* Feeds one staged fragment (`frag` points at a TkMpHeader followed by its
   payload, `sz` bytes in all).  `som`/`eom` are the fragment's control bits.
   `now` is a monotonic time in the receiver's timeout units.

   TK_MP_ERR_INTERLEAVED is the one status that does not consume the fragment:
   a SOM arrived while a message was in progress, so the producer abandoned
   that message.  The old message is dropped (its identity is in rx->fail) and
   the caller records its failure, then feeds the SAME fragment again, which
   now starts the new message.  This keeps one status per call even when the
   new message is a single fragment. */
static inline tk_mp_status_t
tk_mp_rx_feed( tk_mp_rx_t * rx, uint8_t const * frag, ulong sz, int som, int eom, tk_ns_t now ) {
    TkMpHeader h;
    if( sz<sizeof(h) ) {
        /* Too short to even name a message. */
        tk_mp_id_t none;
        memset( &none, 0, sizeof(none) );
        return tk_mp_rx_fail( rx, &none, eom, TK_MP_ERR_SIZE );
    }
    memcpy( &h, frag, sizeof(h) );
    tk_mp_id_t id = tk_mp_id_of( &h );

    /* A fragment of an already-failed message is dropped; the next SOM
       starts clean. */
    if( rx->discard && !som ) {
        if( eom ) rx->discard = 0;
        return TK_MP_DISCARD;
    }

    if( som && rx->active ) {
        rx->fail    = rx->cur;
        rx->active  = 0;
        rx->discard = 0;
        return TK_MP_ERR_INTERLEAVED;
    }

    tk_mp_status_t bad = tk_mp_hdr_check( &h, sz, som, eom, rx->expect_dir );
    if( bad!=TK_MP_PARTIAL ) {
        /* A malformed fragment fails the message in progress too, if any. */
        tk_mp_id_t failed = rx->active ? rx->cur : id;
        return tk_mp_rx_fail( rx, &failed, eom, bad );
    }

    if( som ) {
        rx->discard  = 0;
        rx->active   = 1;
        rx->cur      = id;
        rx->next_idx = 0U;
        rx->next_off = 0U;
        rx->deadline = now + rx->timeout;
    } else {
        if( !rx->active ) {
            /* Continuation with nothing in progress: swallow the rest. */
            return tk_mp_rx_fail( rx, &id, eom, TK_MP_ERR_ORPHAN );
        }
        if( !tk_mp_id_eq( &rx->cur, &id ) ) {
            tk_mp_id_t failed = rx->cur;
            return tk_mp_rx_fail( rx, &failed, eom, TK_MP_ERR_IDENTITY );
        }
        if( h.frag_idx<rx->next_idx ) {
            tk_mp_id_t failed = rx->cur;
            return tk_mp_rx_fail( rx, &failed, eom, TK_MP_ERR_DUPLICATE );
        }
        if( h.frag_idx>rx->next_idx ) {
            tk_mp_id_t failed = rx->cur;
            return tk_mp_rx_fail( rx, &failed, eom, TK_MP_ERR_GAP );
        }
    }

    /* h.frag_off == next_off by canonical framing and the index checks; the
       explicit bound keeps the copy inside both total_len and the buffer. */
    if( (ulong)h.frag_off+(ulong)h.frag_len>(ulong)rx->cur.total_len ||
        (ulong)h.frag_off+(ulong)h.frag_len>(ulong)TK_MP_MAX_MESSAGE_BYTES ) {
        tk_mp_id_t failed = rx->cur;
        return tk_mp_rx_fail( rx, &failed, eom, TK_MP_ERR_OVERFLOW );
    }
    memcpy( rx->buf+h.frag_off, frag+TK_MP_HDR_SZ, h.frag_len );
    rx->next_idx += 1U;
    rx->next_off  = h.frag_off+h.frag_len;

    if( eom ) {
        if( rx->next_off!=rx->cur.total_len || rx->next_idx!=rx->cur.frag_cnt ) {
            tk_mp_id_t failed = rx->cur;
            return tk_mp_rx_fail( rx, &failed, 1, TK_MP_ERR_BOUNDARY );
        }
        if( tk_mp_message_hash( rx->buf, rx->cur.total_len )!=rx->cur.message_hash ) {
            tk_mp_id_t failed = rx->cur;
            return tk_mp_rx_fail( rx, &failed, 1, TK_MP_ERR_HASH );
        }
        rx->active = 0;
        return TK_MP_COMPLETE;
    }
    return TK_MP_PARTIAL;
}

/* Times out a partial message.  Call from the stem's housekeeping/idle path
   (AFTER_CREDIT) so a stalled producer cannot pin a half-built message. */
static inline tk_mp_status_t
tk_mp_rx_poll( tk_mp_rx_t * rx, tk_ns_t now ) {
    if( rx->active && now>=rx->deadline ) {
        tk_mp_id_t failed = rx->cur;
        /* No EOM seen: whatever is still coming belongs to the dead message. */
        return tk_mp_rx_fail( rx, &failed, 0, TK_MP_ERR_TIMEOUT );
    }
    return TK_MP_PARTIAL;
}

/* ─── Sender ───

   A bounded cursor over one complete message.  The caller publishes at most
   the credit-reserved number of fragments per stem iteration and advances the
   cursor only after each publish (no single callback may assume it can emit
   the whole message). */
typedef struct {
    uint8_t const * msg;
    uint8_t         direction;
    uint8_t         content_type;
    uint32_t        total_len;
    uint32_t        frag_cnt;
    uint32_t        next_idx;
    uint64_t        run_id;
    uint64_t        model_request_id;
    uint64_t        message_hash;
} tk_mp_tx_t;

/* Returns 0 on success, -1 if the message is empty or over the bound. */
static inline int
tk_mp_tx_begin( tk_mp_tx_t * tx, uint8_t direction, uint8_t content_type,
                uint64_t run_id, uint64_t model_request_id,
                uint8_t const * msg, ulong len ) {
    if( len==0UL || len>(ulong)TK_MP_MAX_MESSAGE_BYTES ) return -1;
    tx->msg              = msg;
    tx->direction        = direction;
    tx->content_type     = content_type;
    tx->total_len        = (uint32_t)len;
    tx->frag_cnt         = (uint32_t)tk_mp_frag_cnt( len );
    tx->next_idx         = 0U;
    tx->run_id           = run_id;
    tx->model_request_id = model_request_id;
    tx->message_hash     = tk_mp_message_hash( msg, len );
    return 0;
}

static inline int
tk_mp_tx_done( tk_mp_tx_t const * tx ) {
    return tx->next_idx>=tx->frag_cnt;
}

/* Writes the next fragment (header + payload) into `out`, which must hold
   TK_MP_LINK_MTU bytes, and sets the SOM/EOM bits for the caller's
   fd_frag_meta_ctl.  Returns the fragment size (`sz`), or 0 if done. */
static inline ulong
tk_mp_tx_frag( tk_mp_tx_t * tx, uint8_t * out, int * som, int * eom ) {
    if( tk_mp_tx_done( tx ) ) return 0UL;
    ulong off = (ulong)tx->next_idx*(ulong)TK_MP_FRAG_PAYLOAD_MAX;
    ulong len = (ulong)tx->total_len-off;
    if( len>(ulong)TK_MP_FRAG_PAYLOAD_MAX ) len = (ulong)TK_MP_FRAG_PAYLOAD_MAX;

    TkMpHeader h;
    memset( &h, 0, sizeof(h) );
    h.version          = TK_MP_WIRE_VERSION;
    h.direction        = tx->direction;
    h.content_type     = tx->content_type;
    h.total_len        = tx->total_len;
    h.frag_off         = (uint32_t)off;
    h.frag_len         = (uint32_t)len;
    h.frag_idx         = tx->next_idx;
    h.frag_cnt         = tx->frag_cnt;
    h.run_id           = tx->run_id;
    h.model_request_id = tx->model_request_id;
    h.message_hash     = tx->message_hash;
    memcpy( out, &h, sizeof(h) );
    memcpy( out+TK_MP_HDR_SZ, tx->msg+off, len );

    *som = tx->next_idx==0U;
    *eom = tx->next_idx==tx->frag_cnt-1U;
    tx->next_idx += 1U;
    return (ulong)TK_MP_HDR_SZ+len;
}

#endif /* __TK_MULTIPART_H__ */
