/* tkgate: the CaseOps gate tile on Firedancer's fd_stem loop -- the boundary
   between the terminal tile (the Qt CaseOps desktop application, which owns
   HTTP, WebSocket and authentication) and the deterministic spine.

     terminal tile --(TkEvent)--> tkgate --(TkEvent)--> tkings

   tkgate has no sockets: it sees only TkEvent fragments on its one input link.
   Its input is fed from outside the tile graph (permit_no_producers) until the
   terminal tile exists; the integration test harness stands in for it.  Its
   one output is tkings's input, a reliable link: when tkings is behind, fd_stem
   stops tkgate from polling its input until credits return, so tkgate waits and
   never drops.

   Per fragment it checks the wire shape (tk_event_framing.h): one whole
   fragment of exactly sizeof(TkEvent), a known version, kind and flags, source
   TK_EVENT_SOURCE_TKGATE (a user request; replay enters through tkrepl, never
   here), and a nonzero idempotency key.  A fragment that fails is dropped and
   counted (CNC slot 1, wire_invalid).  One that passes is published to tkings
   unchanged (CNC slot 0, published), except that a request that arrives with
   an all-zero trace id is given 16 random bytes: the producer owns the trace
   id, and tkgate supplies one only where the producer sent none (W3C Trace
   Context: all zero is invalid).  tkings frames the rest.

   Follows the fd_stem callback contract in stem_helpers.h: DURING_FRAG copies
   and judges the copy, AFTER_FRAG commits (trace id, counters, publish).  The
   trace id is drawn in AFTER_FRAG because a draw advances the RNG. */
#define _GNU_SOURCE

#include "firedancer.h"
#include "audit_schema.h"
#include "tk_event_framing.h"
#include "tickoni/c_abi/shim/stem_helpers.h"
#include "tickoni/c_abi/shim/stem_diag.h"
#include "tickoni/c_abi/topo_run/tk_gate_stem.h"

#include "util/rng/fd_rng.h"

#include <string.h>

typedef struct {
    fd_rng_t       rng[1];           /* trace ids for requests that arrive without one */
    uint64_t       published;        /* events forwarded to tkings */
    uint64_t       wire_invalid;     /* fragments dropped for their wire shape */
    uint64_t       event_count;
    int            input_exhausted;
    stk_diag_out_t diag;
    void *         cnc;
    stk_link_in_t  in;               /* from the terminal tile */
    stk_link_out_t out;              /* to tkings */
    int            stage_valid;      /* a fragment was staged */
    int            stage_ok;         /* ...and its wire shape is valid */
    TkEvent        stage;
} tkgate_ctx_t;

#define TKGATE_CTX_ALIGN alignof(tkgate_ctx_t)

static uint64_t tkgate_event_count_param;

void tkgate_set_event_count( uint64_t event_count ) { tkgate_event_count_param = event_count; }

/* The wire shape tkgate forwards.  The trace id is not checked: an absent one
   is filled in, in AFTER_FRAG.  A pure function of the staged copy. */
int
tkgate_wire_ok( TkEvent const * ev ) {
    if( !tk_event_envelope_ok( ev ) )            return 0;
    if( ev->source!=TK_EVENT_SOURCE_TKGATE )      return 0;
    if( ev->idempotency_key==0UL )               return 0;
    return 1;
}

/* 16 random bytes, never all zero.  Two 64-bit draws (the bits
   fd_rng_uint128 would return), written byte by byte so no target needs a
   128-bit integer. */
static void
tkgate_trace_id_generate( fd_rng_t * rng, uint8_t id[ TK_TRACE_ID_SZ ] ) {
    do {
        for( ulong w=0UL; w<TK_TRACE_ID_SZ/8UL; w++ ) {
            ulong r = fd_rng_ulong( rng );
            for( ulong b=0UL; b<8UL; b++ ) id[ 8UL*w+b ] = (uint8_t)( r >> ( 56UL - 8UL*b ) );
        }
    } while( FD_UNLIKELY( tk_event_trace_id_is_zero( id ) ) );
}

/* DURING_FRAG: stage only (callback contract, stem_helpers.h).  A fragment
   whose chunk lies outside the input dcache is not read at all; one of the
   wrong size, or one that is not a whole message, is staged as invalid. */
static void
tkgate_during_frag( tkgate_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig, ulong chunk, ulong sz, ulong ctl ) {
    (void)in_idx; (void)seq;
    ctx->stage_valid = 0;
    ctx->stage_ok    = 0;
    if( FD_UNLIKELY( !stk_link_in_contains( &ctx->in, chunk ) ) ) return;
    ctx->stage_valid = 1;
    if( FD_UNLIKELY( sig!=TK_LINK_SIG_EVENT || sz!=TK_EVENT_SIZE ) ) return;
    if( FD_UNLIKELY( !fd_frag_meta_ctl_som( ctl ) || !fd_frag_meta_ctl_eom( ctl ) ) ) return;
    memcpy( &ctx->stage, stk_link_in_laddr( &ctx->in, chunk ), TK_EVENT_SIZE );
    ctx->stage_ok = tkgate_wire_ok( &ctx->stage );
}

/* AFTER_FRAG: the fragment is intact.  Count a drop, or publish to tkings. */
static void
tkgate_after_frag( tkgate_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig, ulong sz, ulong tsorig, ulong tspub, fd_stem_context_t * stem ) {
    (void)in_idx; (void)seq; (void)sig; (void)sz; (void)tsorig; (void)tspub;
    if( !ctx->stage_valid ) return;
    ctx->stage_valid = 0;

    if( !ctx->stage_ok ) {
        ctx->wire_invalid++;
    } else {
        TkEvent * ev = &ctx->stage;
        if( tk_event_trace_id_is_zero( ev->trace_id ) ) tkgate_trace_id_generate( ctx->rng, ev->trace_id );
        FD_LOG_DEBUG(( "tkgate: after_frag published" ));
        stk_link_out_publish( &ctx->out, stem, 0UL, TK_LINK_SIG_EVENT, ev, TK_EVENT_SIZE );
        ctx->published++;
    }
    stk_publish_counter( ctx->cnc, 0UL, ctx->published );
    stk_publish_counter( ctx->cnc, 1UL, ctx->wire_invalid );
    /* Unreliable diagnostic link: draws no credit, STEM_BURST stays 1. */
    stk_diag_publish( &ctx->diag, stem, in_idx, seq, ctx->published + ctx->wire_invalid, ctx->wire_invalid, 0UL );
    STK_EVENT_EXHAUSTED( ctx, ctx->event_count, ctx->published + ctx->wire_invalid );
}

#define STEM_NAME tkgate
#define STEM_BURST (1UL)
#define STEM_LAZY ((long)10e6)
#define STEM_CALLBACK_CONTEXT_TYPE tkgate_ctx_t
#define STEM_CALLBACK_CONTEXT_ALIGN TKGATE_CTX_ALIGN
#define STEM_CALLBACK_DURING_HOUSEKEEPING(ctx) stk_cnc_liveness( (ctx)->cnc )
#define STEM_CALLBACK_DURING_FRAG tkgate_during_frag
#define STEM_CALLBACK_AFTER_FRAG tkgate_after_frag
#define STEM_CALLBACK_SHOULD_SHUTDOWN(ctx) \
    ( (ctx)->input_exhausted || \
      ( (ctx)->cnc && fd_cnc_signal_query( (fd_cnc_t *)(ctx)->cnc )==FD_CNC_SIGNAL_HALT ) )
#include "disco/stem/fd_stem.c"
#undef STEM_NAME
#undef STEM_CALLBACK_CONTEXT_TYPE
#undef STEM_CALLBACK_CONTEXT_ALIGN
#undef STEM_CALLBACK_DURING_HOUSEKEEPING
#undef STEM_CALLBACK_DURING_FRAG
#undef STEM_CALLBACK_AFTER_FRAG
#undef STEM_CALLBACK_SHOULD_SHUTDOWN

static ulong tkgate_scratch_align_tile( void ) { return TKGATE_CTX_ALIGN; }
static ulong tkgate_scratch_footprint_tile( fd_topo_tile_t const * tile ) {
    (void)tile;
    return fd_ulong_align_up( sizeof(tkgate_ctx_t), TKGATE_CTX_ALIGN );
}

static void
tkgate_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkgate_ctx_t * ctx = STK_GET_CTX( tkgate_ctx_t, scratch, TKGATE_CTX_ALIGN );
    memset( ctx, 0, sizeof(*ctx) );
    /* The output count (one pipeline output plus an optional diagnostic link)
       is checked by stk_diag_out_init in unprivileged_init. */
    if( FD_UNLIKELY( tile->in_cnt!=1UL ) )
        FD_LOG_ERR(( "tkgate: expected exactly one input link, found %lu", tile->in_cnt ));
    ctx->event_count = tkgate_event_count_param;
    /* Trace ids are request identifiers, not secrets: a fast RNG seeded per
       run, so ids do not repeat from one run to the next. */
    if( FD_UNLIKELY( !fd_rng_join( fd_rng_new( ctx->rng, (uint)fd_tickcount(), 0UL ) ) ) )
        FD_LOG_ERR(( "tkgate: rng init failed" ));
}

static void
tkgate_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkgate_ctx_t * ctx = STK_GET_CTX( tkgate_ctx_t, scratch, TKGATE_CTX_ALIGN );
    STK_UNPRIV_INIT( topo, tile, ctx );
    if( FD_UNLIKELY( !ctx->cnc ) )
        FD_LOG_ERR(( "tkgate: CNC object not found for tile %lu", tile->id ));
    stk_diag_out_init( &ctx->diag, topo, tile, 1UL );

    stk_link_in_init ( &ctx->in,  topo, tile, 0UL, (ulong)TK_EVENT_SIZE );
    stk_link_out_init( &ctx->out, topo, tile, 0UL, (ulong)TK_EVENT_SIZE );
    FD_LOG_NOTICE(( "tkgate: ready, tile_id=%lu event_count=%lu", tile->id, ctx->event_count ));
}

static void
tkgate_run_entry( fd_topo_t * topo, fd_topo_tile_t * tile ) {
    void * scratch = fd_topo_obj_laddr( topo, tile->tile_obj_id );
    tkgate_ctx_t * ctx = STK_GET_CTX( tkgate_ctx_t, scratch, TKGATE_CTX_ALIGN );

    FD_LOG_DEBUG(( "tkgate: run entry ctx=%p tile=%s:%lu", (void*)ctx, tile->name, tile->id ));

    tkgate_run( topo, tile );
    tile->allow_shutdown = 1;

    FD_LOG_DEBUG(( "tkgate: run exit ctx=%p published=%lu wire_invalid=%lu",
                   (void*)ctx, ctx->published, ctx->wire_invalid ));
}

fd_topo_run_tile_t TK_GATE_RUN = {
    .name = TILE_ID_TKGATE,
    .keep_host_networking = 0,
    .allow_connect = 0,
    .allow_renameat = 0,
    .rlimit_file_cnt = 0,
    .rlimit_address_space = 0,
    .rlimit_data = 0,
    .rlimit_nproc = 0,
    .for_tpool = 0,
    .max_event_sz = NULL,
    .populate_allowed_seccomp = NULL,   /* no sockets: shared memory only */
    .populate_allowed_fds = NULL,
    .scratch_align = tkgate_scratch_align_tile,
    .scratch_footprint = tkgate_scratch_footprint_tile,
    .loose_footprint = NULL,
    .privileged_init = tkgate_privileged_init,
    .unprivileged_init = tkgate_unprivileged_init,
    .run = tkgate_run_entry,
    .rlimit_file_cnt_fn = NULL,
};

STK_DEFINE_RUN_TILE_ACCESSORS(
    tk_get_gate,
    TK_GATE_RUN,
    tkgate_tile_scratch_align,
    tkgate_tile_scratch_footprint
)
