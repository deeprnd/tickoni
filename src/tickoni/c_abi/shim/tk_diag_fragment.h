/* tk_diag_fragment.h — diagnostic fragment sent by pipeline tiles to tkdiag, and
   the aggregation rules tkdiag applies to the fragments it receives
   (doc/execution/plans/v2.10-s14-tkdiag-fan-in.md, "Resolved Design").

   Included at the end of audit_schema.h (it uses TILE_ID_*), so Zig sees it
   through the one translate-c step as audit_mod.diag_fragment_t,
   audit_mod.tkdiag_agg_t and audit_mod.TK_DIAG_*.  No Zig struct mirrors it.

   Who sends what:

     tkings, tknorm, tkdedu, tkpoly, tkaudt  ->  tkdiag
         one fragment per processed event, over a dedicated UNRELIABLE link
         (depth TK_DIAG_LINK_DEPTH, MTU TK_DIAG_LINK_MTU).  A producer never
         waits for tkdiag; tkdiag keeps only the latest fragment per input.

   Fields hold CUMULATIVE counters of the sending tile, so tkdiag derives every
   aggregate from the latest fragment per input and never adds a fragment into
   a running total.  A producer fills only the fields it owns; the rest are 0:

     events_processed    every producer
     errors              tknorm invalid, tkdedu duplicates, tkpoly denied,
                         tkaudt rejected records
     backpressure_waits  tkings (its pipeline link's producer waits)
     audit_records       tkaudt
     max_queue_depth, sandbox_failures, replay_checked, replay_match, crashed
                         reserved: no tile tracks them yet, always 0.  A crashed
                         process publishes nothing, so `crashed` can only ever
                         be a tile's own report of a fatal fault; crash
                         detection stays with the supervisor. */
#ifndef __TK_DIAG_FRAGMENT_H__
#define __TK_DIAG_FRAGMENT_H__

#include <stdint.h>
#include <stddef.h>
#include <string.h>

/* Tile type codes, in pipeline order. */
enum {
    TK_DIAG_TYPE_INGEST    = 1,
    TK_DIAG_TYPE_NORMALIZE = 2,
    TK_DIAG_TYPE_DEDUPE    = 3,
    TK_DIAG_TYPE_POLICY    = 4,
    TK_DIAG_TYPE_AUDIT     = 5
};

/* Diagnostic link shape.  The MTU is sizeof(diag_fragment_t). */
enum {
    TK_DIAG_LINK_DEPTH = 64,
    TK_DIAG_LINK_MTU   = 128
};

/* Most inputs tkdiag aggregates: one per diagnostic producer, with headroom. */
enum { TKDIAG_MAX_INPUTS = 8 };

typedef struct {
    uint32_t tile_id;            /*   0  Firedancer tile index of the sender */
    uint32_t tile_type;          /*   4  TK_DIAG_TYPE_* */
    uint64_t seq;                /*   8  sender's diag fragment counter, 1, 2, 3, ... */
    uint64_t timestamp_ns;       /*  16  tk_monotonic_nanos() when published */
    uint64_t events_processed;   /*  24  cumulative */
    uint64_t errors;             /*  32  cumulative */
    uint64_t backpressure_waits; /*  40  cumulative */
    uint64_t max_queue_depth;    /*  48  reserved, 0 */
    uint64_t sandbox_failures;   /*  56  reserved, 0 */
    uint64_t audit_records;      /*  64  cumulative (tkaudt) */
    int32_t  crashed;            /*  72  0 healthy, 1 tile reports a fatal fault; reserved, 0 */
    int32_t  replay_checked;     /*  76  0 or 1; reserved, 0 */
    int32_t  replay_match;       /*  80  0 or 1; reserved, 0 */
    uint8_t  reserved[44];       /*  84  must be zero */
} diag_fragment_t;

_Static_assert( sizeof(diag_fragment_t)==128UL,                    "diag_fragment_t must be 128 bytes" );
_Static_assert( sizeof(diag_fragment_t)==(unsigned long)TK_DIAG_LINK_MTU, "the diag link MTU is the fragment size" );
_Static_assert( offsetof(diag_fragment_t, seq)==8UL,               "diag_fragment_t.seq ABI drift" );
_Static_assert( offsetof(diag_fragment_t, timestamp_ns)==16UL,     "diag_fragment_t.timestamp_ns ABI drift" );
_Static_assert( offsetof(diag_fragment_t, events_processed)==24UL, "diag_fragment_t.events_processed ABI drift" );
_Static_assert( offsetof(diag_fragment_t, errors)==32UL,           "diag_fragment_t.errors ABI drift" );
_Static_assert( offsetof(diag_fragment_t, backpressure_waits)==40UL, "diag_fragment_t.backpressure_waits ABI drift" );
_Static_assert( offsetof(diag_fragment_t, max_queue_depth)==48UL,  "diag_fragment_t.max_queue_depth ABI drift" );
_Static_assert( offsetof(diag_fragment_t, sandbox_failures)==56UL, "diag_fragment_t.sandbox_failures ABI drift" );
_Static_assert( offsetof(diag_fragment_t, audit_records)==64UL,    "diag_fragment_t.audit_records ABI drift" );
_Static_assert( offsetof(diag_fragment_t, crashed)==72UL,          "diag_fragment_t.crashed ABI drift" );
_Static_assert( offsetof(diag_fragment_t, replay_match)==80UL,     "diag_fragment_t.replay_match ABI drift" );
_Static_assert( offsetof(diag_fragment_t, reserved)==84UL,         "diag_fragment_t.reserved ABI drift" );

/* Type code of a diagnostic producer, by tile name; 0 for any other tile. */
static inline uint32_t
tk_diag_type_for_tile_name( char const * name ) {
    if( !name ) return 0U;
    if( strcmp( name, TILE_ID_TKINGS )==0 ) return TK_DIAG_TYPE_INGEST;
    if( strcmp( name, TILE_ID_TKNORM )==0 ) return TK_DIAG_TYPE_NORMALIZE;
    if( strcmp( name, TILE_ID_TKDEDU )==0 ) return TK_DIAG_TYPE_DEDUPE;
    if( strcmp( name, TILE_ID_TKPOLY )==0 ) return TK_DIAG_TYPE_POLICY;
    if( strcmp( name, TILE_ID_TKAUDT )==0 ) return TK_DIAG_TYPE_AUDIT;
    return 0U;
}

/* Shape check of a fragment, independent of which input it arrived on: a known
   tile type, a sequence number (they start at 1), 0/1 flags, and zero reserved
   bytes.  Anything else is not a fragment a producer would send. */
static inline int
tk_diag_fragment_valid( diag_fragment_t const * f ) {
    if( !f ) return 0;
    if( f->tile_type<TK_DIAG_TYPE_INGEST || f->tile_type>TK_DIAG_TYPE_AUDIT ) return 0;
    if( f->seq==0UL ) return 0;
    if( f->crashed<0 || f->crashed>1 ) return 0;
    if( f->replay_checked<0 || f->replay_checked>1 ) return 0;
    if( f->replay_match<0 || f->replay_match>1 ) return 0;
    for( size_t i=0UL; i<sizeof(f->reserved); i++ )
        if( f->reserved[i] ) return 0;
    return 1;
}

/* ─── Aggregation state ───

   The latest accepted fragment per input, the fan-in's own counters, and the
   aggregates derived from those slots after every accepted fragment. */
typedef struct {
    uint64_t        in_cnt;                                 /* bound inputs; 0 = no diagnostic links */
    uint32_t        bound_tile_id  [TKDIAG_MAX_INPUTS];     /* producer's Firedancer tile index */
    uint32_t        bound_tile_type[TKDIAG_MAX_INPUTS];     /* producer's TK_DIAG_TYPE_* */
    uint8_t         seen           [TKDIAG_MAX_INPUTS];     /* an accepted fragment is in latest[] */
    diag_fragment_t latest         [TKDIAG_MAX_INPUTS];

    uint64_t        accepted;                               /* fragments accepted */
    uint64_t        rejected;                               /* fragments refused: malformed, wrong sender, stale */

    uint64_t        tiles_reporting;                        /* inputs with an accepted fragment */
    uint64_t        crashed_tiles;                          /* inputs whose latest fragment reports a fault */
    uint64_t        sandbox_failures;                       /* sum over latest fragments */
    uint64_t        total_errors;                           /* sum over latest fragments */
    uint64_t        total_audit_records;                    /* max over latest fragments */
    uint64_t        total_backpressure_waits;               /* sum over latest fragments */
    uint64_t        max_queue_depth;                        /* max over latest fragments */
} tkdiag_agg_t;

static inline uint64_t
tkdiag_sat_add( uint64_t a, uint64_t b ) {
    return (a>UINT64_MAX-b) ? UINT64_MAX : a+b;
}

/* Binds `in_cnt` inputs to their producers' identities (taken from the
   topology wiring, never from a fragment).  Returns 0 on success, -1 if the
   count is outside 1..TKDIAG_MAX_INPUTS, an array is missing, a type is not a
   diagnostic producer's, or two inputs name the same producer type. */
static inline int
tkdiag_agg_init( tkdiag_agg_t *   agg,
                 uint64_t         in_cnt,
                 uint32_t const * tile_id,
                 uint32_t const * tile_type ) {
    if( !agg ) return -1;
    memset( agg, 0, sizeof(*agg) );
    if( in_cnt<1UL || in_cnt>(uint64_t)TKDIAG_MAX_INPUTS || !tile_id || !tile_type ) return -1;
    for( uint64_t i=0UL; i<in_cnt; i++ ) {
        if( tile_type[i]<TK_DIAG_TYPE_INGEST || tile_type[i]>TK_DIAG_TYPE_AUDIT ) { memset( agg, 0, sizeof(*agg) ); return -1; }
        for( uint64_t j=0UL; j<i; j++ )
            if( tile_type[j]==tile_type[i] ) { memset( agg, 0, sizeof(*agg) ); return -1; }
        agg->bound_tile_id  [i] = tile_id  [i];
        agg->bound_tile_type[i] = tile_type[i];
    }
    agg->in_cnt = in_cnt;
    return 0;
}

/* Offers a fragment received on input `in_idx`.  Returns 1 if accepted into the
   input's slot, 0 if refused (counted in `rejected`; nothing else changes).
   Refused: no such input; a malformed fragment; a sender that is not the
   input's bound producer; and any sequence number not greater than the last
   accepted on that input (stale or duplicate). */
static inline int
tkdiag_agg_accept( tkdiag_agg_t *         agg,
                   uint64_t               in_idx,
                   diag_fragment_t const * f ) {
    if( in_idx>=agg->in_cnt || !tk_diag_fragment_valid( f )
        || f->tile_id  !=agg->bound_tile_id  [in_idx]
        || f->tile_type!=agg->bound_tile_type[in_idx]
        || ( agg->seen[in_idx] && f->seq<=agg->latest[in_idx].seq ) ) {
        agg->rejected = tkdiag_sat_add( agg->rejected, 1UL );
        return 0;
    }
    agg->latest[in_idx] = *f;
    agg->seen  [in_idx] = 1;
    agg->accepted = tkdiag_sat_add( agg->accepted, 1UL );

    /* Re-derive every aggregate from the latest fragments. */
    agg->tiles_reporting     = 0UL;
    agg->crashed_tiles       = 0UL;
    agg->sandbox_failures    = 0UL;
    agg->total_errors        = 0UL;
    agg->total_audit_records = 0UL;
    agg->total_backpressure_waits = 0UL;
    agg->max_queue_depth     = 0UL;
    for( uint64_t i=0UL; i<agg->in_cnt; i++ ) {
        if( !agg->seen[i] ) continue;
        diag_fragment_t const * l = &agg->latest[i];
        agg->tiles_reporting += 1UL;
        if( l->crashed ) agg->crashed_tiles += 1UL;
        agg->sandbox_failures = tkdiag_sat_add( agg->sandbox_failures, l->sandbox_failures );
        agg->total_errors     = tkdiag_sat_add( agg->total_errors,     l->errors );
        if( l->audit_records>agg->total_audit_records ) agg->total_audit_records = l->audit_records;
        agg->total_backpressure_waits = tkdiag_sat_add( agg->total_backpressure_waits, l->backpressure_waits );
        if( l->max_queue_depth>agg->max_queue_depth ) agg->max_queue_depth = l->max_queue_depth;
    }
    return 1;
}

/* How many fragments wait on an input, as a tile sees it right after processing
   fragment `processed_seq`: the producer's published sequence is the next one
   it will publish, so those after `processed_seq` and before it are waiting.
   The producer publishes its sequence to the mcache only periodically, so the
   value can lag the tile, in which case nothing is counted.  Wrap-safe. */
static inline uint64_t
tkdiag_backlog( uint64_t producer_seq,
                uint64_t processed_seq ) {
    int64_t ahead = (int64_t)( producer_seq - (processed_seq + 1UL) );
    return ahead>0 ? (uint64_t)ahead : 0UL;
}

/* ─── Tile liveness observation ───

   tkdiag watches every tile of the topology the way Firedancer's diag tile does
   (src/disco/diag/fd_diag_tile.c): a tile publishes its own TILE_STATUS gauge in
   its metrics region (0 booting, 1 running, 2 shut down cleanly, set by
   topo_run before the process exits), and tkdiag checks whether the tile's
   process still exists.  A process that is gone while its status is not
   "shutdown" died abnormally.  A status of 0 at that point means it never
   started running: it died during boot or sandbox entry.  Unlike Firedancer,
   whose supervisor tears down the whole process tree on any death, Tickoni's
   supervisor keeps the other tiles running, so tkdiag reports the death at once.

   An observation is sticky: there is no tile restart inside a run, so a tile
   found dead stays dead. */
enum {
    TKDIAG_STATUS_BOOT     = 0,
    TKDIAG_STATUS_RUN      = 1,
    TKDIAG_STATUS_SHUTDOWN = 2
};

typedef struct {
    uint8_t dead;        /* gone without a clean shutdown */
    uint8_t never_ran;   /* dead while still booting: died during boot or sandbox entry */
} tkdiag_tile_obs_t;

/* Applies one observation.  `alive`: the tile's process was found; `status`: its
   TILE_STATUS gauge.  Returns 1 the first time the tile is found dead without a
   clean shutdown (the caller logs it once), else 0. */
static inline int
tkdiag_obs_update( tkdiag_tile_obs_t * o,
                   int                 alive,
                   uint64_t            status ) {
    if( o->dead || alive || status==TKDIAG_STATUS_SHUTDOWN ) return 0;
    o->dead      = 1;
    o->never_ran = status==TKDIAG_STATUS_BOOT;
    return 1;
}

/* Tiles counted as crashed: observed dead, or whose latest accepted fragment
   reports a fatal fault of its own, each tile once.  `obs` is indexed by
   Firedancer tile index and holds `tile_cnt` entries; a fragment's tile_id is
   such an index. */
static inline uint64_t
tkdiag_crashed_total( tkdiag_agg_t const *      agg,
                      tkdiag_tile_obs_t const * obs,
                      uint64_t                  tile_cnt ) {
    uint64_t total = 0UL;
    for( uint64_t i=0UL; i<tile_cnt; i++ ) {
        int crashed = obs[i].dead;
        for( uint64_t j=0UL; j<agg->in_cnt && !crashed; j++ )
            if( agg->seen[j] && agg->bound_tile_id[j]==i && agg->latest[j].crashed ) crashed = 1;
        total += (uint64_t)crashed;
    }
    /* A reporting tile outside the observed range still counts. */
    for( uint64_t j=0UL; j<agg->in_cnt; j++ )
        if( agg->seen[j] && agg->bound_tile_id[j]>=tile_cnt && agg->latest[j].crashed ) total += 1UL;
    return total;
}

/* Tiles that died before they ran: boot or sandbox-entry failures. */
static inline uint64_t
tkdiag_boot_failures( tkdiag_tile_obs_t const * obs,
                      uint64_t                  tile_cnt ) {
    uint64_t total = 0UL;
    for( uint64_t i=0UL; i<tile_cnt; i++ ) total += (uint64_t)obs[i].never_ran;
    return total;
}

#endif /* __TK_DIAG_FRAGMENT_H__ */
