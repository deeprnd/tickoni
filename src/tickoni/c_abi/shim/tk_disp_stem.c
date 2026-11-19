/* tk_disp_stem.c — fd_stem tile registered under the tkdisp tile id.
 *
 * One tile, two shapes, chosen by the links it is wired with:
 *
 *   Sink      (1 input: tkagnt's terminal results; no output).  The minimal agent
 *             topology.  Keeps each TkAgentResultMsg in a fixed ring for
 *             inspection from the supervisor's scratch base and counts them.
 *
 *   Scheduler (2 inputs: events from tkcase and tkagnt's terminal results; 1
 *             output: the agent request link to tkagnt).  The full investment
 *             workflow.  For each event it receives it sends ONE agent request
 *             built from a fixed template supplied by the run configuration
 *             (tkdisp_set_template): the tier, scope and prompt come from that
 *             template, never from the event's contents.  This is scaffolding,
 *             not dispatch policy: how a financial event should become an agent
 *             request is not defined by the tkagnt migration plan.  The request's
 *             run id is the event's source offset plus one, so a terminal result
 *             correlates back to the event.  Requests are sent one at a time as
 *             multipart fragment streams, in event order.
 *
 * Follows the fd_stem callback contract in stem_helpers.h:
 * - BEFORE_FRAG: a new event is left queued upstream (return -1) while the
 *   scheduler's bounded event queue is full: lossless backpressure.
 * - DURING_FRAG: validate framing, size and sig; stage.  Stages only.
 * - AFTER_FRAG: append a result to the ring, or queue an event.  No publish.
 * - AFTER_CREDIT (scheduler): send the next request fragments, at most
 *   STEM_BURST per iteration, so the credit reservation is exact.
 * - SHOULD_SHUTDOWN: event_count exhaustion (results received) + CNC HALT.
 */

#define _GNU_SOURCE

#include "firedancer.h"
#include "audit_schema.h"
#include "tk_multipart.h"
#include "tickoni/c_abi/shim/stem_helpers.h"
#include "tickoni/c_abi/topo_run/tk_disp_stem.h"

#include "disco/topo/fd_topo.h"
#include "util/wksp/fd_wksp.h"
#include "util/fd_util.h"

#include <string.h>
#include <stddef.h>

#define TKDISP_RESULT_CAPACITY 256
#define TKDISP_QUEUE_CAPACITY  64UL
#define TKDISP_STEM_BURST      4UL
#define TKDISP_EVENT_MAX       256UL      /* the event link's MTU bound */

typedef struct {
    uint64_t received;          /* committed terminal results */
    int      stage_valid;
    int      stage_is_result;   /* else an event */
    TkAgentResultMsg staged;
    uint8_t  stage_event[TKDISP_EVENT_MAX];
    void *   cnc;
    void *   wksp;
    ulong    in_chunk0[2];
    ulong    in_wmark[2];
    uint64_t event_count;
    int      input_exhausted;

    /* Scheduler shape. */
    int      scheduler;
    ulong    result_in;         /* input index of the terminal-result link */
    ulong    event_in;          /* input index of the event link */
    ulong    out_idx;
    void *   out_wksp;
    ulong    out_chunk0, out_wmark, out_chunk;
    uint64_t scheduled;         /* requests started */
    uint64_t events_seen;
    uint64_t queue[TKDISP_QUEUE_CAPACITY];   /* event source offsets awaiting a request */
    ulong    queue_head, queue_cnt;
    tk_mp_tx_t tx;
    int      tx_active;
    uint8_t * txbuf;            /* TK_MP_MAX_MESSAGE_BYTES, after the result ring */
    /* results[] follows the context in the same scratch object; see
       tkdisp_results_of(). */
} tkdisp_ctx_t;

#define TKDISP_CTX_ALIGN alignof(tkdisp_ctx_t)

static void tkdisp_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tkdisp_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static int  tkdisp_before_frag( tkdisp_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig );
static void tkdisp_during_frag( tkdisp_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig,
                                ulong chunk, ulong sz, ulong ctl );
static void tkdisp_after_frag( tkdisp_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig,
                               ulong sz, ulong tsorig, ulong tspub, fd_stem_context_t * stem );
static void tkdisp_after_credit( tkdisp_ctx_t * ctx, fd_stem_context_t * stem, int * opt_poll_in, int * charge_busy );
static void tkdisp_run_entry( fd_topo_t * topo, fd_topo_tile_t * tile );

#define STEM_NAME                         tkdisp
#define STEM_BURST                        (TKDISP_STEM_BURST)
#define STEM_LAZY                         ((long)10e6)
#define STEM_CALLBACK_CONTEXT_TYPE        tkdisp_ctx_t
#define STEM_CALLBACK_CONTEXT_ALIGN       TKDISP_CTX_ALIGN
#define STEM_CALLBACK_DURING_HOUSEKEEPING(ctx) stk_cnc_liveness( (ctx)->cnc )
#define STEM_CALLBACK_BEFORE_FRAG         tkdisp_before_frag
#define STEM_CALLBACK_DURING_FRAG         tkdisp_during_frag
#define STEM_CALLBACK_AFTER_FRAG          tkdisp_after_frag
#define STEM_CALLBACK_AFTER_CREDIT        tkdisp_after_credit
#define STEM_CALLBACK_SHOULD_SHUTDOWN(ctx) \
  ( (ctx)->input_exhausted || \
    ( (ctx)->cnc && fd_cnc_signal_query( (fd_cnc_t *)(ctx)->cnc ) == FD_CNC_SIGNAL_HALT ) )

#include "disco/stem/fd_stem.c"

#undef STEM_NAME
#undef STEM_CALLBACK_CONTEXT_TYPE
#undef STEM_CALLBACK_CONTEXT_ALIGN
#undef STEM_CALLBACK_DURING_HOUSEKEEPING
#undef STEM_CALLBACK_BEFORE_FRAG
#undef STEM_CALLBACK_DURING_FRAG
#undef STEM_CALLBACK_AFTER_FRAG
#undef STEM_CALLBACK_AFTER_CREDIT
#undef STEM_CALLBACK_SHOULD_SHUTDOWN

/* The result ring sits directly after the aligned context, and the request
   buffer after the ring.  The single definition of those offsets: init uses
   them, and the accessors recompute them from the caller's scratch base (a
   cross-process read cannot trust a stored pointer). */
static inline TkAgentResultMsg *
tkdisp_results_of( tkdisp_ctx_t * ctx ) {
    return (TkAgentResultMsg *)fd_ulong_align_up( (ulong)ctx + sizeof(tkdisp_ctx_t),
                                                  alignof(TkAgentResultMsg) );
}

static inline uint8_t *
tkdisp_txbuf_of( tkdisp_ctx_t * ctx ) {
    return (uint8_t *)( tkdisp_results_of( ctx ) + TKDISP_RESULT_CAPACITY );
}

static ulong
tkdisp_scratch_align_tile( void ) {
    return fd_ulong_max( TKDISP_CTX_ALIGN, alignof(TkAgentResultMsg) );
}

static ulong
tkdisp_scratch_footprint_tile( fd_topo_tile_t const * tile ) {
    (void)tile;
    ulong footprint = fd_ulong_align_up( sizeof(tkdisp_ctx_t), alignof(TkAgentResultMsg) );
    footprint += sizeof(TkAgentResultMsg) * TKDISP_RESULT_CAPACITY;
    footprint += (ulong)TK_MP_MAX_MESSAGE_BYTES;
    return fd_ulong_align_up( footprint, tkdisp_scratch_align_tile() );
}

static uint64_t tkdisp_event_count_param;

/* The request template (scheduler shape): a full agent request header and a
   prompt, set once by the Zig child from the run configuration. */
static TkAgentRequestHdr tkdisp_template_hdr;
static uint8_t           tkdisp_template_prompt[ 64UL*1024UL ];
static ulong             tkdisp_template_prompt_len;
static int               tkdisp_template_set;

void
tkdisp_set_event_count( uint64_t event_count ) {
    tkdisp_event_count_param = event_count;
}

/* Installs the request template.  Returns 0, or nonzero (and installs nothing)
   if the header is not a well-formed agent request or the prompt is empty or
   over the template bound. */
int
tkdisp_set_template( TkAgentRequestHdr const * hdr, uint8_t const * prompt, ulong prompt_len ) {
    if( !hdr || !prompt )                                              return 1;
    if( hdr->version!=TK_AGENT_WIRE_VERSION )                          return 2;
    if( prompt_len==0UL || prompt_len>sizeof(tkdisp_template_prompt) ) return 3;
    tkdisp_template_hdr        = *hdr;
    memcpy( tkdisp_template_prompt, prompt, prompt_len );
    tkdisp_template_prompt_len = prompt_len;
    tkdisp_template_set        = 1;
    return 0;
}

static void
tkdisp_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkdisp_ctx_t * ctx = STK_GET_CTX(tkdisp_ctx_t, scratch, TKDISP_CTX_ALIGN);
    memset( ctx, 0, sizeof(*ctx) );
    ctx->event_count = tkdisp_event_count_param;
    ctx->wksp        = stk_derive_wksp( topo, tile, 0 );
    ctx->txbuf       = tkdisp_txbuf_of( ctx );
}

/* The tile that produces `link_id`, or NULL. */
static fd_topo_tile_t const *
tkdisp_link_producer( fd_topo_t const * topo, ulong link_id ) {
    for( ulong t=0UL; t<topo->tile_cnt; t++ ) {
        fd_topo_tile_t const * other = &topo->tiles[t];
        for( ulong o=0UL; o<other->out_cnt; o++ )
            if( other->out_link_id[o]==link_id ) return other;
    }
    return NULL;
}

static void
tkdisp_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkdisp_ctx_t * ctx = STK_GET_CTX(tkdisp_ctx_t, scratch, TKDISP_CTX_ALIGN);

    STK_UNPRIV_INIT(topo, tile, ctx);
    if( FD_UNLIKELY( !ctx->cnc ) )
        FD_LOG_ERR(( "tkdisp: CNC object not found for tile %lu", tile->id ));
    if( FD_UNLIKELY( !ctx->wksp ) )
        FD_LOG_ERR(( "tkdisp: input workspace is not joined" ));

    ctx->scheduler = tile->out_cnt==1UL;
    if( ctx->scheduler ) {
        if( FD_UNLIKELY( tile->in_cnt!=2UL ) )
            FD_LOG_ERR(( "tkdisp: a scheduler has two inputs (events, results), found %lu", tile->in_cnt ));
        if( FD_UNLIKELY( !tkdisp_template_set ) )
            FD_LOG_ERR(( "tkdisp: the request template was not set" ));
        ctx->event_in  = ULONG_MAX;
        ctx->result_in = ULONG_MAX;
        for( ulong i=0UL; i<2UL; i++ ) {
            fd_topo_tile_t const * producer = tkdisp_link_producer( topo, tile->in_link_id[i] );
            int from_agent = producer && strcmp( producer->name, TILE_ID_TKAGNT )==0;
            if( from_agent ) ctx->result_in = i; else ctx->event_in = i;
        }
        if( FD_UNLIKELY( ctx->event_in==ULONG_MAX || ctx->result_in==ULONG_MAX ) )
            FD_LOG_ERR(( "tkdisp: inputs must be one event link and one tkagnt result link" ));

        fd_topo_link_t const * out_link = &topo->links[tile->out_link_id[0]];
        if( FD_UNLIKELY( !out_link->dcache || out_link->mtu<(ulong)TK_MP_LINK_MTU ) )
            FD_LOG_ERR(( "tkdisp: request output needs an mtu of %lu, found %lu", (ulong)TK_MP_LINK_MTU, out_link->mtu ));
        ctx->out_idx   = 0UL;
        ctx->out_wksp  = fd_topo_obj_wksp_base( topo, out_link->dcache_obj_id );
        if( FD_UNLIKELY( !ctx->out_wksp ) )
            FD_LOG_ERR(( "tkdisp: output workspace is not joined" ));
        ctx->out_chunk0 = fd_dcache_compact_chunk0( ctx->out_wksp, out_link->dcache );
        ctx->out_wmark  = fd_dcache_compact_wmark( ctx->out_wksp, out_link->dcache, out_link->mtu );
        ctx->out_chunk  = ctx->out_chunk0;
    } else {
        if( FD_UNLIKELY( tile->in_cnt!=1UL ) )
            FD_LOG_ERR(( "tkdisp: a sink expects exactly one input link, found %lu", tile->in_cnt ));
        if( FD_UNLIKELY( tile->out_cnt!=0UL ) )
            FD_LOG_ERR(( "tkdisp: a sink expects no output links, found %lu", tile->out_cnt ));
        ctx->result_in = 0UL;
        ctx->event_in  = ULONG_MAX;
    }

    for( ulong i=0UL; i<tile->in_cnt; i++ ) {
        fd_topo_link_t const * in_link = &topo->links[tile->in_link_id[i]];
        ulong need = i==ctx->result_in ? sizeof(TkAgentResultMsg) : (ulong)PAYMENT_MSG_SIZE;
        if( FD_UNLIKELY( !in_link->dcache || in_link->mtu<need || in_link->mtu>TKDISP_EVENT_MAX ) )
            FD_LOG_ERR(( "tkdisp: input %lu has no dcache or an mtu outside [%lu, %lu]: %lu", i, need, TKDISP_EVENT_MAX, in_link->mtu ));
        if( FD_UNLIKELY( stk_derive_wksp( topo, tile, i )!=ctx->wksp ) )
            FD_LOG_ERR(( "tkdisp: input %lu is not in the workspace shared with input 0", i ));
        ctx->in_chunk0[i] = fd_dcache_compact_chunk0( ctx->wksp, in_link->dcache );
        ctx->in_wmark[i]  = fd_dcache_compact_wmark( ctx->wksp, in_link->dcache, in_link->mtu );
    }
}

/* Lossless backpressure for events: a new event stays queued upstream while the
   bounded queue is full. */
static int
tkdisp_before_frag( tkdisp_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig ) {
    (void)seq; (void)sig;
    if( ctx->scheduler && in_idx==ctx->event_in && ctx->queue_cnt>=TKDISP_QUEUE_CAPACITY ) return -1;
    return 0;
}

static void
tkdisp_during_frag( tkdisp_ctx_t * ctx,
                    ulong          in_idx,
                    ulong          seq,
                    ulong          sig,
                    ulong          chunk,
                    ulong          sz,
                    ulong          ctl ) {
    (void)seq; (void)ctl;

    ctx->stage_valid = 0;
    if( in_idx>1UL ) return;
    if( FD_UNLIKELY( chunk < ctx->in_chunk0[in_idx] || chunk > ctx->in_wmark[in_idx] ) ) return;

    if( in_idx==ctx->result_in ) {
        if( sig!=TK_LINK_SIG_AGENT_RESULT ) return;
        if( !stk_validate_frag( sz, sizeof(TkAgentResultMsg), ctx->wksp ) ) return;
        memcpy( &ctx->staged, stk_chunk_to_gaddr( ctx->wksp, chunk ), sizeof(TkAgentResultMsg) );
        if( ctx->staged.version != TK_AGENT_WIRE_VERSION ) return;
        ctx->stage_is_result = 1;
    } else {
        /* An event: a payment-pipeline envelope.  Only its source offset is
           read; nothing else about it reaches the request. */
        if( sig!=TK_LINK_SIG_PAYMENT ) return;
        if( !stk_validate_frag( sz, PAYMENT_MSG_SIZE, ctx->wksp ) ) return;
        memcpy( ctx->stage_event, stk_chunk_to_gaddr( ctx->wksp, chunk ), PAYMENT_MSG_SIZE );
        ctx->stage_is_result = 0;
    }
    ctx->stage_valid = 1;
}

static void
tkdisp_after_frag( tkdisp_ctx_t *      ctx,
                   ulong               in_idx,
                   ulong               seq,
                   ulong               sig,
                   ulong               sz,
                   ulong               tsorig,
                   ulong               tspub,
                   fd_stem_context_t * stem ) {
    (void)in_idx; (void)seq; (void)sig; (void)sz; (void)tsorig; (void)tspub; (void)stem;

    if( !ctx->stage_valid )
        return;
    ctx->stage_valid = 0;

    if( !ctx->stage_is_result ) {
        /* before_frag guaranteed room. */
        PaymentMessage const * ev = (PaymentMessage const *)ctx->stage_event;
        ulong tail = (ctx->queue_head + ctx->queue_cnt) % TKDISP_QUEUE_CAPACITY;
        ctx->queue[tail] = ev->raw.source_offset;
        ctx->queue_cnt  += 1UL;
        ctx->events_seen += 1UL;
        return;
    }

    if( FD_UNLIKELY( ctx->received >= TKDISP_RESULT_CAPACITY ) ) {
        FD_LOG_WARNING(( "tkdisp: result ring full at %lu", (ulong)ctx->received ));
        return;
    }
    tkdisp_results_of( ctx )[ctx->received] = ctx->staged;
    ctx->received += 1;

    STK_EVENT_EXHAUSTED( ctx, ctx->event_count, ctx->received );
}

/* Starts the next request: the template with this event's run id, then the
   template prompt.  Nothing of the event but its offset is used. */
static void
tkdisp_begin_request( tkdisp_ctx_t * ctx, uint64_t source_offset ) {
    TkAgentRequestHdr hdr = tkdisp_template_hdr;
    uint64_t run_id = source_offset + 1UL;
    hdr.scope.run_id = run_id;
    memcpy( ctx->txbuf, &hdr, sizeof(hdr) );
    memcpy( ctx->txbuf+sizeof(hdr), tkdisp_template_prompt, tkdisp_template_prompt_len );
    if( FD_UNLIKELY( tk_mp_tx_begin( &ctx->tx, TK_MP_DIR_REQUEST, TK_MP_CT_AGENT_REQUEST, run_id, run_id,
                                     ctx->txbuf, sizeof(hdr)+tkdisp_template_prompt_len )!=0 ) )
        FD_LOG_ERR(( "tkdisp: the request template exceeds the multipart ceiling" ));
    ctx->tx_active  = 1;
    ctx->scheduled += 1UL;
}

static void
tkdisp_after_credit( tkdisp_ctx_t *      ctx,
                     fd_stem_context_t * stem,
                     int *               opt_poll_in,
                     int *               charge_busy ) {
    (void)opt_poll_in;
    if( !ctx->scheduler ) return;

    ulong budget = TKDISP_STEM_BURST;
    while( budget ) {
        if( !ctx->tx_active ) {
            if( !ctx->queue_cnt ) break;
            uint64_t offset = ctx->queue[ctx->queue_head];
            ctx->queue_head = (ctx->queue_head+1UL) % TKDISP_QUEUE_CAPACITY;
            ctx->queue_cnt -= 1UL;
            tkdisp_begin_request( ctx, offset );
        }
        ulong chunk = ctx->out_chunk;
        int som, eom;
        ulong sz  = tk_mp_tx_frag( &ctx->tx, (uint8_t *)fd_chunk_to_laddr( ctx->out_wksp, chunk ), &som, &eom );
        ulong ctl = fd_frag_meta_ctl( 0UL, som, eom, 0 );
        fd_stem_publish( stem, ctx->out_idx, TK_LINK_SIG_AGENT_REQUEST, chunk, sz, ctl, 0UL, 0UL );
        ctx->out_chunk = fd_dcache_compact_next( chunk, sz, ctx->out_chunk0, ctx->out_wmark );
        budget--;
        *charge_busy = 1;
        if( tk_mp_tx_done( &ctx->tx ) ) ctx->tx_active = 0;
    }
    stk_publish_counter( ctx->cnc, 0UL, ctx->scheduled );
}

static void
tkdisp_run_entry( fd_topo_t *      topo,
                  fd_topo_tile_t * tile ) {
    void * scratch = fd_topo_obj_laddr( topo, tile->tile_obj_id );
    tkdisp_ctx_t * ctx = STK_GET_CTX(tkdisp_ctx_t, scratch, TKDISP_CTX_ALIGN);

    ulong cnc_obj_id = tk_topo_find_tile_obj( topo, tile->id, "cnc" );
    if( FD_UNLIKELY( cnc_obj_id == ULONG_MAX ) )
        FD_LOG_ERR(( "tkdisp: CNC object not found for tile %lu", tile->id ));
    ctx->cnc = fd_topo_obj_laddr( topo, cnc_obj_id );

    tkdisp_run( topo, tile );

    tile->allow_shutdown = 1;
}

fd_topo_run_tile_t TK_DISP_RUN = {
    .name                     = TILE_ID_TKDISP,
    .keep_host_networking     = 0,
    .allow_connect            = 0,
    .allow_renameat           = 0,
    .rlimit_file_cnt          = 0,
    .rlimit_address_space     = 0,
    .rlimit_data              = 0,
    .rlimit_nproc             = 0,
    .for_tpool                = 0,
    .max_event_sz             = NULL,
    .populate_allowed_seccomp = NULL,
    .populate_allowed_fds     = NULL,
    .scratch_align            = tkdisp_scratch_align_tile,
    .scratch_footprint        = tkdisp_scratch_footprint_tile,
    .loose_footprint          = NULL,
    .privileged_init          = tkdisp_privileged_init,
    .unprivileged_init        = tkdisp_unprivileged_init,
    .run                      = tkdisp_run_entry,
    .rlimit_file_cnt_fn       = NULL,
};

STK_DEFINE_RUN_TILE_ACCESSORS(
    tk_get_disp,
    TK_DISP_RUN,
    tkdisp_tile_scratch_align,
    tkdisp_tile_scratch_footprint
)

/* ─── Scratch-base accessors (committed state only) ─── */

ulong
tkdisp_result_count( void * scratch ) {
    return STK_GET_CTX(tkdisp_ctx_t, scratch, TKDISP_CTX_ALIGN)->received;
}

ulong
tkdisp_scheduled( void * scratch ) {
    return STK_GET_CTX(tkdisp_ctx_t, scratch, TKDISP_CTX_ALIGN)->scheduled;
}

ulong
tkdisp_events_seen( void * scratch ) {
    return STK_GET_CTX(tkdisp_ctx_t, scratch, TKDISP_CTX_ALIGN)->events_seen;
}

static TkAgentResultMsg const *
tkdisp_result_at( void * scratch, ulong idx ) {
    tkdisp_ctx_t * ctx = STK_GET_CTX(tkdisp_ctx_t, scratch, TKDISP_CTX_ALIGN);
    if( FD_UNLIKELY( idx>=ctx->received ) )
        FD_LOG_ERR(( "tkdisp: result index %lu out of range (committed %lu)", idx, (ulong)ctx->received ));
    return &tkdisp_results_of( ctx )[idx];
}

/* One copy-out of a committed result; dst_sz must equal sizeof(TkAgentResultMsg)
   so a layout drift in the caller's translate-c view aborts instead of
   truncating. */
void
tkdisp_result_copy( void * scratch, ulong idx, void * dst, ulong dst_sz ) {
    if( FD_UNLIKELY( dst_sz!=sizeof(TkAgentResultMsg) ) )
        FD_LOG_ERR(( "tkdisp: result copy size %lu != %lu", dst_sz, (ulong)sizeof(TkAgentResultMsg) ));
    memcpy( dst, tkdisp_result_at( scratch, idx ), sizeof(TkAgentResultMsg) );
}
