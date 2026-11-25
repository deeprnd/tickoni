/* tk_disp_stem.c — fd_stem tile registered under the tkdisp tile id: the
 * agent dispatch scheduler of the event spine.
 *
 * Inputs: the spine's events from tkcase (TkEvent) and tkagnt's terminal
 * results.  Output: the agent request link to tkagnt.  For each event it
 * receives it sends ONE agent request, a single TkAgentRequestMsg fragment
 * (scope + prompt reference; prompt bytes never travel here):
 *
 *   agent request event   the event's own request (plan v2.NN rev 2, D5);
 *   payment event         the fixed template from the run configuration
 *                         (tkdisp_set_template), resolved decision O2: how a
 *                         payment should become an agent request is not yet
 *                         defined, so the tier, scope and prompt reference come
 *                         from the template, never from the event.
 *
 * Either way tkdisp stamps the request's run id (the event's source offset plus
 * one, so a terminal result correlates back to the event) and its trace id
 * (the event's).  It is blind to the agent<->model protocol: tkagnt resolves
 * the prompt and talks to tkmodl.  Requests go out one at a time, in event
 * order.  Terminal results are kept in a fixed ring for inspection from the
 * supervisor's scratch base and counted.
 *
 * Follows the fd_stem callback contract in stem_helpers.h:
 * - BEFORE_FRAG: a new event is left queued upstream (return -1) while the
 *   bounded request queue is full: lossless backpressure.
 * - DURING_FRAG: validate framing, size and sig; stage.  Stages only.
 * - AFTER_FRAG: append a result to the ring, or queue the event's request.
 * - AFTER_CREDIT: send the next queued request, at most STEM_BURST per
 *   iteration, so the credit reservation is exact, and only while fewer than
 *   TKDISP_MAX_INFLIGHT requests await their terminal result.
 *
 * Why the in-flight bound.  tkdisp and tkagnt form a loop (requests one way,
 * terminal results back), and fd_stem polls no input while any reliable
 * output has fewer than STEM_BURST credits.  Unbounded, tkagnt holding
 * requests back fills tkdisp's request link, tkdisp then stops reading
 * results, tkagnt's terminal link fills and tkagnt stops too: a credit
 * deadlock.  Every request ends in exactly one terminal result, so bounding
 * sent-minus-answered below both links' depths (checked at init) keeps credits
 * on both sides of the loop. 
 * - SHOULD_SHUTDOWN: event_count exhaustion (results received) + CNC HALT.
 */

#define _GNU_SOURCE

#include "firedancer.h"
#include "audit_schema.h"
#include "tickoni/c_abi/shim/stem_helpers.h"
#include "tickoni/c_abi/shim/stem_diag.h"
#include "tickoni/c_abi/topo_run/tk_disp_stem.h"

#include "disco/topo/fd_topo.h"
#include "util/wksp/fd_wksp.h"
#include "util/fd_util.h"

#include <string.h>
#include <stddef.h>

#define TKDISP_RESULT_CAPACITY 256
#define TKDISP_QUEUE_CAPACITY  64UL
#define TKDISP_STEM_BURST      1UL
#define TKDISP_MAX_INFLIGHT    16UL       /* requests sent and not yet answered */

typedef struct {
    uint64_t received;          /* committed terminal results */
    int      stage_valid;
    int      stage_is_result;   /* else an event */
    TkAgentResultMsg staged;
    TkEvent  stage_event;
    void *   cnc;
    stk_link_in_t in[2];        /* the event link and the terminal-result link */
    uint64_t event_count;
    int      input_exhausted;
    stk_diag_out_t diag;

    ulong    result_in;         /* input index of the terminal-result link */
    ulong    event_in;          /* input index of the event link */
    stk_link_out_t out;         /* agent requests to tkagnt */
    uint64_t scheduled;         /* requests sent */
    uint64_t answered;          /* terminal results received, ring full or not */
    uint64_t events_seen;
    TkAgentRequestMsg queue[TKDISP_QUEUE_CAPACITY];   /* requests awaiting a send */
    ulong    queue_head, queue_cnt;
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

/* The result ring sits directly after the aligned context.  The single
   definition of that offset: init uses it, and the accessors recompute it from
   the caller's scratch base (a cross-process read cannot trust a stored
   pointer). */
static inline TkAgentResultMsg *
tkdisp_results_of( tkdisp_ctx_t * ctx ) {
    return (TkAgentResultMsg *)fd_ulong_align_up( (ulong)ctx + sizeof(tkdisp_ctx_t),
                                                  alignof(TkAgentResultMsg) );
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
    return fd_ulong_align_up( footprint, tkdisp_scratch_align_tile() );
}

static uint64_t tkdisp_event_count_param;

/* The payment-event template (decision O2): one agent request, set once by the
   Zig child from the run configuration. */
static TkAgentRequestMsg tkdisp_template;
static int               tkdisp_template_set;

void
tkdisp_set_event_count( uint64_t event_count ) {
    tkdisp_event_count_param = event_count;
}

/* Installs the payment-event template.  Returns 0, or nonzero (and installs
   nothing) if it is not a well-formed agent request with a prompt reference. */
int
tkdisp_set_template( TkAgentRequestMsg const * req ) {
    if( !req )                                   return 1;
    if( req->version!=TK_AGENT_WIRE_VERSION )    return 2;
    if( req->prompt_ref.prompt_len==0U )         return 3;
    tkdisp_template     = *req;
    tkdisp_template_set = 1;
    return 0;
}

static void
tkdisp_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkdisp_ctx_t * ctx = STK_GET_CTX(tkdisp_ctx_t, scratch, TKDISP_CTX_ALIGN);
    memset( ctx, 0, sizeof(*ctx) );
    ctx->event_count = tkdisp_event_count_param;
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
    stk_diag_out_init( &ctx->diag, topo, tile, 1UL );

    if( FD_UNLIKELY( tile->in_cnt!=2UL || tile->out_cnt!=1UL ) )
        FD_LOG_ERR(( "tkdisp: expected two inputs (events, results) and one output, found %lu and %lu", tile->in_cnt, tile->out_cnt ));
    if( FD_UNLIKELY( !tkdisp_template_set ) )
        FD_LOG_ERR(( "tkdisp: the payment-event template was not set" ));

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
    fd_topo_link_t const * res_link = &topo->links[tile->in_link_id[ctx->result_in]];
    /* The in-flight bound must leave credits on both links of the loop. */
    if( FD_UNLIKELY( out_link->depth<=TKDISP_MAX_INFLIGHT || res_link->depth<=TKDISP_MAX_INFLIGHT ) )
        FD_LOG_ERR(( "tkdisp: request and result links need a depth above %lu, found %lu and %lu", TKDISP_MAX_INFLIGHT, out_link->depth, res_link->depth ));
    stk_link_out_init( &ctx->out, topo, tile, 0UL, (ulong)sizeof(TkAgentRequestMsg) );

    for( ulong i=0UL; i<tile->in_cnt; i++ ) {
        fd_topo_link_t const * in_link = &topo->links[tile->in_link_id[i]];
        if( FD_UNLIKELY( in_link->mtu>(ulong)TK_EVENT_LINK_MTU ) )
            FD_LOG_ERR(( "tkdisp: input %lu has an mtu %lu above %lu", i, in_link->mtu, (ulong)TK_EVENT_LINK_MTU ));
        ulong need = i==ctx->result_in ? sizeof(TkAgentResultMsg) : (ulong)TK_EVENT_SIZE;
        stk_link_in_init( &ctx->in[i], topo, tile, i, need );
    }
}

/* Lossless backpressure for events: a new event stays queued upstream while the
   bounded queue is full. */
static int
tkdisp_before_frag( tkdisp_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig ) {
    (void)seq; (void)sig;
    if( in_idx==ctx->event_in && ctx->queue_cnt>=TKDISP_QUEUE_CAPACITY ) return -1;
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
    stk_link_in_t const * in = &ctx->in[in_idx];
    if( FD_UNLIKELY( !stk_link_in_contains( in, chunk ) ) ) return;

    if( in_idx==ctx->result_in ) {
        if( sig!=TK_LINK_SIG_AGENT_RESULT ) return;
        if( !stk_validate_frag( sz, sizeof(TkAgentResultMsg), in->wksp ) ) return;
        memcpy( &ctx->staged, stk_link_in_laddr( in, chunk ), sizeof(TkAgentResultMsg) );
        if( ctx->staged.version != TK_AGENT_WIRE_VERSION ) return;
        ctx->stage_is_result = 1;
    } else {
        if( sig!=TK_LINK_SIG_EVENT ) return;
        if( !stk_validate_frag( sz, TK_EVENT_SIZE, in->wksp ) ) return;
        memcpy( &ctx->stage_event, stk_link_in_laddr( in, chunk ), TK_EVENT_SIZE );
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
        /* before_frag guaranteed room.  The request is the event's own for an
           agent request, else the template; tkdisp stamps only its run and
           trace ids. */
        TkEvent const * ev = &ctx->stage_event;
        ulong tail = (ctx->queue_head + ctx->queue_cnt) % TKDISP_QUEUE_CAPACITY;
        TkAgentRequestMsg * req = &ctx->queue[tail];
        *req = ev->kind==TK_EVENT_KIND_AGENT_REQUEST ? ev->body.agent_request : tkdisp_template;
        req->scope.run_id   = ev->source_offset + 1UL;
        memcpy( req->scope.trace_id, ev->trace_id, sizeof(req->scope.trace_id) );
        ctx->queue_cnt  += 1UL;
        ctx->events_seen += 1UL;
        return;
    }

    ctx->answered += 1UL;
    if( FD_UNLIKELY( ctx->received >= TKDISP_RESULT_CAPACITY ) ) {
        FD_LOG_WARNING(( "tkdisp: result ring full at %lu", (ulong)ctx->received ));
        return;
    }
    tkdisp_results_of( ctx )[ctx->received] = ctx->staged;
    ctx->received += 1;

    STK_EVENT_EXHAUSTED( ctx, ctx->event_count, ctx->received );
}

static void
tkdisp_after_credit( tkdisp_ctx_t *      ctx,
                     fd_stem_context_t * stem,
                     int *               opt_poll_in,
                     int *               charge_busy ) {
    (void)opt_poll_in;
    ulong budget = TKDISP_STEM_BURST;
    while( budget && ctx->queue_cnt && ctx->scheduled - ctx->answered < TKDISP_MAX_INFLIGHT ) {
        TkAgentRequestMsg const * req = &ctx->queue[ctx->queue_head];
        stk_link_out_publish( &ctx->out, stem, 0UL, TK_LINK_SIG_AGENT_REQUEST, req, sizeof(*req) );
        ctx->queue_head = (ctx->queue_head+1UL) % TKDISP_QUEUE_CAPACITY;
        ctx->queue_cnt -= 1UL;
        ctx->scheduled += 1UL;
        budget--;
        *charge_busy = 1;
    }
    stk_publish_counter( ctx->cnc, 0UL, ctx->scheduled );
    /* Unreliable diagnostic link: draws no credit, STEM_BURST stays 1. */
    stk_diag_publish( &ctx->diag, stem, ctx->event_in, 0UL, ctx->events_seen, 0UL, 0UL );
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
