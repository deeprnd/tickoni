/* tk_agent_stem.c — fd_stem agent-worker tile for tkagnt.
 *
 * tkagnt accepts agent requests, dispatches each to the tkmodl instance that
 * serves the tier it names, correlates the model's result, and delivers one
 * terminal result per accepted request.  It is proposal-first: it reaches no
 * provider, adapter or executor, and decides nothing about routing or about
 * what a result means -- those are Zig-owned (src/tickoni/tiles/agent/
 * decision.zig) and arrive through the two hooks in tk_agent_hooks.h, the one
 * approved C->Zig call path.  This file does bounded transport, correlation
 * and ordering only.
 *
 * One request, one model dispatch, one result: there is no cascade.
 *
 * Data path
 *   tkdisp --agent request--> tkagnt --model request--> tkmodl[tier k]
 *                                    <--model result---
 *                             tkagnt --audit record---> tkaudt
 *                             tkagnt --terminal result-> tkdisp
 *   An agent request is one fixed fragment (TkAgentRequestMsg): its scope and
 *   a prompt reference.  tkagnt resolves the prompt bytes from its
 *   content-addressed prompt table (installed before the tile runs, each
 *   prompt verified against its hash) and sends them to tkmodl.  Model request
 *   and result bodies are multipart fragment streams (tk_multipart_wire.h) and
 *   are acted on only after reassembly verified every byte.  Audit and
 *   terminal records are single-fragment and hash-and-metadata-only: no
 *   prompt, response or vector bytes.  Every record carries the request's
 *   trace id.
 *
 * Ordering and the commit barrier
 *   Each accepted request gets a contiguous admission ordinal, agent_seq.
 *   Agent audit records are published in admission order, so the committed
 *   sequence does not depend on which model answers first.  tkaudt stays a
 *   pure sink and publishes a committed-order watermark (an fseq); a run's
 *   terminal result is published only once the watermark has reached the run's
 *   agent_seq, i.e. once its audit record is appended and chained.
 *
 * Flow control
 *   - A new agent request is not accepted (BEFORE_FRAG returns -1, the
 *     fragment stays queued upstream) while there is no free request slot or
 *     run entry.  Nothing is dropped; the producer is back-pressured.
 *   - One request in flight per tkmodl instance: a run waits, in admission
 *     order, until its instance is free.
 *   - Every publication happens in AFTER_CREDIT, at most STEM_BURST per
 *     iteration, so the credit reservation is exact and a message larger than
 *     the link depth is sent over successive iterations.
 *
 * Failure and drain
 *   Every accepted request ends in exactly one terminal result, audited first:
 *   a denial at routing, a model denial, invalid content, a transport failure,
 *   a model that never answers (deadline), or an administrative drain.  On
 *   HALT the tile stops dispatching, fails what has not been sent, waits (up to
 *   a deadline) for in-flight results, and publishes every terminal result
 *   before it exits.
 */

#define _GNU_SOURCE

#include "firedancer.h"
#include "audit_schema.h"
#include "tk_multipart.h"
#include "tk_model_request.h"
#include "tickoni/c_abi/shim/stem_helpers.h"
#include "tickoni/c_abi/shim/stem_diag.h"
#include "tickoni/c_abi/topo_run/tk_agent_stem.h"

#include "disco/topo/fd_topo.h"
#include "util/wksp/fd_wksp.h"
#include "util/fd_util.h"

#include <string.h>
#include <stddef.h>

/* Defined in topob.c. */
extern ulong tk_topo_find_tile_obj( fd_topo_t const * topo, ulong tile_id, char const * obj_type );
extern ulong tk_topo_audit_watermark_obj( fd_topo_t const * topo );

/* ─── Bounds ─── */

#define TKAGNT_TIERS            ((ulong)TK_AGENT_TIER_COUNT)
#define TKAGNT_MAX_INS          (1UL+TKAGNT_TIERS)     /* request input + one result input per tier */
#define TKAGNT_MAX_OUTS         (TKAGNT_TIERS+3UL)     /* one request output per tier + audit + terminal + the idle tool link */
#define TKAGNT_SLOTS            4UL                    /* request bodies held while waiting to be sent */
#define TKAGNT_PENDING          64UL                   /* runs between admission and terminal result */
#define TKAGNT_STEM_BURST       4UL                    /* publications per iteration */
#define TKAGNT_NS_PER_MS        1000000LL
#define TKAGNT_PARTIAL_TIMEOUT_NS ((tk_ns_t)TK_MP_PARTIAL_TIMEOUT_MS*TKAGNT_NS_PER_MS)
#define TKAGNT_DEFAULT_MODEL_TIMEOUT_NS (10000LL*TKAGNT_NS_PER_MS)
#define TKAGNT_DRAIN_DEADLINE_NS        (10000LL*TKAGNT_NS_PER_MS)
#define TKAGNT_DRAIN_GRACE_NS           (5000LL*TKAGNT_NS_PER_MS)

/* Slot and reassembly buffers are one multipart message each. */
#define TKAGNT_MSG_BYTES        ((ulong)TK_MP_MAX_MESSAGE_BYTES)

enum {
    RUN_FREE = 0,
    RUN_ADMITTED,     /* waiting for its tkmodl instance */
    RUN_SENDING,      /* request fragments going out */
    RUN_AWAIT,        /* request sent; waiting for the model's result */
    RUN_RESOLVED,     /* outcome known; audit record not yet published */
    RUN_AUDITED,      /* audit record published; waiting for the watermark */
    RUN_DONE          /* terminal result published */
};

typedef struct {
    uint8_t   state;
    uint8_t   outcome;            /* TK_AGENT_OUT_* */
    uint8_t   tier;               /* tier ordinal being served, or TK_AGENT_TIER_NONE */
    uint8_t   request_type;
    uint8_t   content_type;
    int8_t    slot;               /* request body slot, or -1 */
    uint8_t   has_model_record;
    uint8_t   model_decision;
    uint8_t   confidence;
    uint8_t   recommended_tier;
    uint8_t   source_tier;
    uint8_t   _pad;
    uint32_t  response_len;
    uint32_t  total_tokens;
    uint64_t  agent_seq;
    uint64_t  run_id;
    uint64_t  prompt_hash;
    uint64_t  response_hash;
    uint64_t  envelope_hash;
    uint8_t   trace_id[TK_TRACE_ID_SZ];
    tk_ns_t   deadline;           /* AWAIT: when the model has taken too long */
    uint8_t   model_id[TKMODL_MODEL_ID_LEN];
    uint8_t   policy_version[TKMODL_POLICY_VERSION_LEN];
    uint8_t   failed_scope_dim[TKMODL_SCOPE_DIM_LEN];
} tkagnt_run_t;

typedef struct {
    int       used;
    ulong     len;
} tkagnt_slot_t;

typedef struct {
    /* Counters (CNC schema in tile_registry.zig: 0 dispatched, 1 results,
       2 denied, 3 tokens, 4 embeddings). */
    uint64_t  dispatched;
    uint64_t  results;
    uint64_t  denied;
    uint64_t  tokens;
    uint64_t  embeddings;
    uint64_t  mismatched;         /* results that matched no pending dispatch */
    uint64_t  transport_dropped;  /* malformed request/result streams */

    /* Admission.  agent_seq values are 1..admitted; a run lives in
       runs[agent_seq % TKAGNT_PENDING] until its terminal result is published. */
    uint64_t  admitted;
    uint64_t  audit_seq;          /* next run to publish an audit record for */
    uint64_t  term_seq;           /* next run to publish a terminal result for */
    uint64_t  terminal_done;
    tkagnt_run_t   runs[TKAGNT_PENDING];
    tkagnt_slot_t  slots[TKAGNT_SLOTS];

    /* Per-tier transmit cursor and flow state.  inst_busy covers the request
       being sent and the wait for its result. */
    tk_mp_tx_t tx[TK_AGENT_TIER_COUNT];
    int        tx_active[TK_AGENT_TIER_COUNT];
    int        inst_busy[TK_AGENT_TIER_COUNT];

    /* Topology binding, resolved at init from verified link endpoints. */
    uint16_t  configured_mask;
    ulong     req_in;
    ulong     model_out[TK_AGENT_TIER_COUNT];     /* ULONG_MAX when the tier is not configured */
    ulong     model_in[TK_AGENT_TIER_COUNT];
    int       in_tier[TKAGNT_MAX_INS];            /* tier of a result input, -1 for the request input */
    ulong     audit_out;
    ulong     term_out;
    ulong     in_cnt;
    ulong     out_cnt;

    /* Per-output cursors and per-input bounds (stem_helpers.h). */
    stk_link_out_t out[TKAGNT_MAX_OUTS];
    stk_link_in_t  in[TKAGNT_MAX_INS];

    /* The fragment DURING_FRAG staged for AFTER_FRAG: a multipart result
       fragment in `stage`, or a whole agent request in `stage_req`. */
    int       stage_valid;
    int       stage_is_req;
    TkAgentRequestMsg stage_req;
    ulong     stage_in;
    ulong     stage_sz;
    int       stage_som;
    int       stage_eom;
    uint8_t   stage[TK_MP_LINK_MTU];

    /* Reassembly, one stream per result input; buffers follow the context. */
    tk_mp_rx_t rx[TKAGNT_MAX_INS];
    uint8_t * rxbuf;              /* TKAGNT_MAX_INS * TKAGNT_MSG_BYTES */
    uint8_t * slotbuf;            /* TKAGNT_SLOTS * TKAGNT_MSG_BYTES */

    /* Committed-order watermark, read-only. */
    ulong *   watermark;

    /* Zig-owned decisions. */
    TkAgentHooks hooks;

    /* Lifecycle. */
    void *    cnc;
    stk_diag_out_t diag;
    uint64_t  event_count;
    int       input_exhausted;
    int       draining;
    tk_ns_t   drain_deadline;
} tkagnt_ctx_t;

#define TKAGNT_CTX_ALIGN alignof(tkagnt_ctx_t)

static void tkagnt_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tkagnt_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static int  tkagnt_before_frag( tkagnt_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig );
static void tkagnt_during_frag( tkagnt_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig,
                                ulong chunk, ulong sz, ulong ctl );
static void tkagnt_after_frag( tkagnt_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig,
                               ulong sz, ulong tsorig, ulong tspub, fd_stem_context_t * stem );
static void tkagnt_after_credit( tkagnt_ctx_t * ctx, fd_stem_context_t * stem, int * opt_poll_in, int * charge_busy );
static void tkagnt_run_entry( fd_topo_t * topo, fd_topo_tile_t * tile );

#define STEM_NAME                         tkagnt
#define STEM_BURST                        (TKAGNT_STEM_BURST)
#define STEM_LAZY                         ((long)10e6)
#define STEM_CALLBACK_CONTEXT_TYPE        tkagnt_ctx_t
#define STEM_CALLBACK_CONTEXT_ALIGN       TKAGNT_CTX_ALIGN
#define STEM_CALLBACK_DURING_HOUSEKEEPING(ctx) stk_cnc_liveness( (ctx)->cnc )
#define STEM_CALLBACK_BEFORE_FRAG         tkagnt_before_frag
#define STEM_CALLBACK_DURING_FRAG         tkagnt_during_frag
#define STEM_CALLBACK_AFTER_FRAG          tkagnt_after_frag
#define STEM_CALLBACK_AFTER_CREDIT        tkagnt_after_credit
/* Shutdown is reached only through the drain (HALT) or the event gate, both of
   which set input_exhausted after the last terminal result is published. */
#define STEM_CALLBACK_SHOULD_SHUTDOWN(ctx) ( (ctx)->input_exhausted )

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

/* ─── Scratch layout ───

   The message buffers follow the aligned context in the same scratch object;
   the footprint is fixed (it depends on neither the event count nor the
   configured tiers). */

static inline uint8_t *
tkagnt_rxbuf_of( tkagnt_ctx_t * ctx ) {
    return (uint8_t *)fd_ulong_align_up( (ulong)ctx + sizeof(tkagnt_ctx_t), 64UL );
}

static inline uint8_t *
tkagnt_slotbuf_of( tkagnt_ctx_t * ctx ) {
    return tkagnt_rxbuf_of( ctx ) + TKAGNT_MAX_INS*TKAGNT_MSG_BYTES;
}

static ulong
tkagnt_scratch_align_tile( void ) {
    return TKAGNT_CTX_ALIGN;
}

static ulong
tkagnt_scratch_footprint_tile( fd_topo_tile_t const * tile ) {
    (void)tile;
    ulong footprint = fd_ulong_align_up( sizeof(tkagnt_ctx_t), 64UL );
    footprint += (TKAGNT_MAX_INS+TKAGNT_SLOTS)*TKAGNT_MSG_BYTES;
    return fd_ulong_align_up( footprint, TKAGNT_CTX_ALIGN );
}

/* ─── Behavior configuration (set by the Zig child before the tile runs) ─── */

static uint64_t      tkagnt_event_count_param;

/* The prompt table: content-addressed prompts, installed by tkagnt_set_prompt
   before the tile runs.  A bounded per-process store, like tkmodl's capture
   store; an agent request names an entry by (prompt_hash, prompt_len). */
static uint8_t       tkagnt_prompt_store[TKAGNT_PROMPT_STORE_BYTES];
static ulong         tkagnt_prompt_used;
static ulong         tkagnt_prompt_cnt;
static struct { uint64_t hash; uint32_t len; ulong off; } tkagnt_prompts[TKAGNT_PROMPT_CAP];
static TkAgentHooks  tkagnt_hooks_param;
static int           tkagnt_hooks_set;
static int           tkagnt_route_set[TK_AGENT_TIER_COUNT];
static uint8_t       tkagnt_route_kind[TK_AGENT_TIER_COUNT];

void
tkagnt_set_event_count( uint64_t event_count ) {
    tkagnt_event_count_param = event_count;
}

/* Registers the Zig-owned decision hooks.  Returns 0 on success, nonzero if
   either hook is missing. */
int
tkagnt_set_hooks( TkAgentHooks const * hooks ) {
    if( !hooks || !hooks->route || !hooks->interpret ) return 1;
    tkagnt_hooks_param = *hooks;
    tkagnt_hooks_set   = 1;
    return 0;
}

/* Declares that the tier with ordinal `tier` is served by the tkmodl instance
   whose Firedancer kind_id is `kind_id`.  Returns 0 on success; nonzero for an
   unknown tier or a tier declared twice. */
int
tkagnt_set_route( uint8_t tier, uint8_t kind_id ) {
    if( tier>=TK_AGENT_TIER_COUNT )  return 1;
    if( tkagnt_route_set[tier] )     return 2;
    for( ulong t=0UL; t<TKAGNT_TIERS; t++ )
        if( tkagnt_route_set[t] && tkagnt_route_kind[t]==kind_id ) return 3;
    tkagnt_route_set[tier]  = 1;
    tkagnt_route_kind[tier] = kind_id;
    return 0;
}

/* Installs one prompt.  Returns 0, or nonzero and installs nothing: 1 empty or
   over TKAGNT_PROMPT_MAX_BYTES, 2 the bytes do not hash to `hash`, 3 the table
   or the store is full, 4 a prompt with that hash is already installed. */
int
tkagnt_set_prompt( uint64_t hash, uint8_t const * bytes, ulong len ) {
    if( !bytes || len==0UL || len>(ulong)TKAGNT_PROMPT_MAX_BYTES )      return 1;
    if( tk_mp_message_hash( bytes, len )!=hash )                      return 2;
    if( tkagnt_prompt_cnt>=(ulong)TKAGNT_PROMPT_CAP ||
        tkagnt_prompt_used+len>(ulong)TKAGNT_PROMPT_STORE_BYTES )      return 3;
    for( ulong i=0UL; i<tkagnt_prompt_cnt; i++ )
        if( tkagnt_prompts[i].hash==hash )                            return 4;
    memcpy( tkagnt_prompt_store+tkagnt_prompt_used, bytes, len );
    tkagnt_prompts[tkagnt_prompt_cnt].hash = hash;
    tkagnt_prompts[tkagnt_prompt_cnt].len  = (uint32_t)len;
    tkagnt_prompts[tkagnt_prompt_cnt].off  = tkagnt_prompt_used;
    tkagnt_prompt_cnt  += 1UL;
    tkagnt_prompt_used += len;
    return 0;
}

/* The installed prompt a reference names, or NULL. */
static uint8_t const *
tkagnt_prompt_lookup( TkPromptRef const * ref ) {
    for( ulong i=0UL; i<tkagnt_prompt_cnt; i++ )
        if( tkagnt_prompts[i].hash==ref->prompt_hash && tkagnt_prompts[i].len==ref->prompt_len )
            return tkagnt_prompt_store + tkagnt_prompts[i].off;
    return NULL;
}

/* ─── Helpers ─── */

static inline int
tkagnt_tier_configured( tkagnt_ctx_t const * ctx, ulong tier ) {
    return tier<TKAGNT_TIERS && ((ctx->configured_mask>>tier) & 1U);
}

static inline tkagnt_run_t *
tkagnt_run_at( tkagnt_ctx_t * ctx, uint64_t seq ) {
    return &ctx->runs[ seq % TKAGNT_PENDING ];
}

static inline uint8_t *
tkagnt_slot_buf( tkagnt_ctx_t * ctx, long slot ) {
    return ctx->slotbuf + (ulong)slot*TKAGNT_MSG_BYTES;
}

static inline long
tkagnt_free_slot( tkagnt_ctx_t const * ctx ) {
    for( ulong i=0UL; i<TKAGNT_SLOTS; i++ )
        if( !ctx->slots[i].used ) return (long)i;
    return -1L;
}

static inline int
tkagnt_has_run_room( tkagnt_ctx_t const * ctx ) {
    return ctx->admitted - ctx->terminal_done < TKAGNT_PENDING;
}

/* Marks a run's outcome and queues it for its audit record. */
static void
tkagnt_resolve( tkagnt_ctx_t * ctx, tkagnt_run_t * r, uint8_t outcome, int has_model_record ) {
    if( r->slot>=0 ) { ctx->slots[r->slot].used = 0; r->slot = -1; }
    r->outcome          = outcome;
    r->has_model_record = (uint8_t)has_model_record;
    r->state            = RUN_RESOLVED;
}

/* ─── Callbacks ─── */

static void
tkagnt_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkagnt_ctx_t * ctx = STK_GET_CTX(tkagnt_ctx_t, scratch, TKAGNT_CTX_ALIGN);

    /* Fail closed: an agent with no decision hooks would have to decide
       routing itself, which this file must never do. */
    if( FD_UNLIKELY( !tkagnt_hooks_set ) )
        FD_LOG_ERR(( "tkagnt: Zig decision hooks were not registered" ));

    memset( ctx, 0, sizeof(*ctx) );
    ctx->hooks       = tkagnt_hooks_param;
    ctx->event_count = tkagnt_event_count_param;
    ctx->rxbuf       = tkagnt_rxbuf_of( ctx );
    ctx->slotbuf     = tkagnt_slotbuf_of( ctx );
    ctx->audit_seq   = 1UL;
    ctx->term_seq    = 1UL;
    for( ulong t=0UL; t<TKAGNT_TIERS; t++ ) {
        ctx->model_out[t] = ULONG_MAX;
        ctx->model_in[t]  = ULONG_MAX;
    }
    for( ulong i=0UL; i<TKAGNT_MAX_INS; i++ ) ctx->in_tier[i] = -1;
}

/* The tile that produces `link_id`, or NULL. */
static fd_topo_tile_t const *
tkagnt_link_producer( fd_topo_t const * topo, ulong link_id ) {
    for( ulong t=0UL; t<topo->tile_cnt; t++ ) {
        fd_topo_tile_t const * other = &topo->tiles[t];
        for( ulong o=0UL; o<other->out_cnt; o++ )
            if( other->out_link_id[o]==link_id ) return other;
    }
    return NULL;
}

/* The tile that consumes `link_id`, or NULL. */
static fd_topo_tile_t const *
tkagnt_link_consumer( fd_topo_t const * topo, ulong link_id ) {
    for( ulong t=0UL; t<topo->tile_cnt; t++ ) {
        fd_topo_tile_t const * other = &topo->tiles[t];
        for( ulong i=0UL; i<other->in_cnt; i++ )
            if( other->in_link_id[i]==link_id ) return other;
    }
    return NULL;
}

static long
tkagnt_tier_of_kind( ulong kind_id ) {
    for( ulong t=0UL; t<TKAGNT_TIERS; t++ )
        if( tkagnt_route_set[t] && tkagnt_route_kind[t]==kind_id ) return (long)t;
    return -1L;
}

static void
tkagnt_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkagnt_ctx_t * ctx = STK_GET_CTX(tkagnt_ctx_t, scratch, TKAGNT_CTX_ALIGN);

    STK_UNPRIV_INIT(topo, tile, ctx);
    if( FD_UNLIKELY( !ctx->cnc ) )
        FD_LOG_ERR(( "tkagnt: CNC object not found for tile %lu", tile->id ));
    stk_diag_out_init( &ctx->diag, topo, tile, tile->out_cnt - 1UL );

    if( FD_UNLIKELY( tile->in_cnt<2UL || tile->in_cnt>TKAGNT_MAX_INS ) )
        FD_LOG_ERR(( "tkagnt: expected 2..%lu input links, found %lu", TKAGNT_MAX_INS, tile->in_cnt ));
    if( FD_UNLIKELY( tile->out_cnt<3UL || tile->out_cnt>TKAGNT_MAX_OUTS ) )
        FD_LOG_ERR(( "tkagnt: expected 3..%lu output links, found %lu", TKAGNT_MAX_OUTS, tile->out_cnt ));
    ctx->in_cnt  = tile->in_cnt;
    ctx->out_cnt = tile->out_cnt;

    /* Inputs: one result link per configured tier (bound by the producing
       tkmodl instance's kind_id), and exactly one request link. */
    ulong req_in = ULONG_MAX;
    for( ulong i=0UL; i<tile->in_cnt; i++ ) {
        fd_topo_tile_t const * producer = tkagnt_link_producer( topo, tile->in_link_id[i] );
        int from_model = producer && strcmp( producer->name, TILE_ID_TKMODL )==0;
        ulong need = from_model ? (ulong)TK_MP_LINK_MTU : sizeof(TkAgentRequestMsg);
        stk_link_in_init( &ctx->in[i], topo, tile, i, need );

        if( from_model ) {
            long tier = tkagnt_tier_of_kind( producer->kind_id );
            if( FD_UNLIKELY( tier<0 ) )
                FD_LOG_ERR(( "tkagnt: input %lu comes from tkmodl#%lu, which has no declared tier", i, producer->kind_id ));
            if( FD_UNLIKELY( ctx->model_in[tier]!=ULONG_MAX ) )
                FD_LOG_ERR(( "tkagnt: tier %ld has more than one result link", tier ));
            ctx->model_in[tier] = i;
            ctx->in_tier[i]     = (int)tier;
            tk_mp_rx_init( &ctx->rx[i], TK_MP_DIR_RESULT, ctx->rxbuf + i*TKAGNT_MSG_BYTES, TKAGNT_PARTIAL_TIMEOUT_NS );
        } else {
            if( FD_UNLIKELY( req_in!=ULONG_MAX ) )
                FD_LOG_ERR(( "tkagnt: more than one agent request input (%lu and %lu)", req_in, i ));
            req_in = i;     /* one fixed fragment per request: no reassembly */
        }
    }
    if( FD_UNLIKELY( req_in==ULONG_MAX ) )
        FD_LOG_ERR(( "tkagnt: no agent request input" ));
    ctx->req_in = req_in;

    /* Outputs: one request link per configured tier (bound by the consuming
       tkmodl instance), the audit link (tkaudt) and the terminal link (tkdisp). */
    ctx->audit_out = ULONG_MAX;
    ctx->term_out  = ULONG_MAX;
    ulong model_outs = 0UL;
    ulong tool_outs  = 0UL;
    for( ulong o=0UL; o<tile->out_cnt; o++ ) {
        fd_topo_tile_t const * consumer = tkagnt_link_consumer( topo, tile->out_link_id[o] );
        if( FD_UNLIKELY( !consumer ) )
            FD_LOG_ERR(( "tkagnt: output %lu has no consumer", o ));
        ulong need;
        if( strcmp( consumer->name, TILE_ID_TKMODL )==0 ) {
            long tier = tkagnt_tier_of_kind( consumer->kind_id );
            if( FD_UNLIKELY( tier<0 ) )
                FD_LOG_ERR(( "tkagnt: output %lu goes to tkmodl#%lu, which has no declared tier", o, consumer->kind_id ));
            if( FD_UNLIKELY( ctx->model_out[tier]!=ULONG_MAX ) )
                FD_LOG_ERR(( "tkagnt: tier %ld has more than one request link", tier ));
            ctx->model_out[tier] = o;
            model_outs++;
            need = (ulong)TK_MP_LINK_MTU;
        } else if( strcmp( consumer->name, TILE_ID_TKAUDT )==0 ) {
            if( FD_UNLIKELY( ctx->audit_out!=ULONG_MAX ) ) FD_LOG_ERR(( "tkagnt: more than one audit output" ));
            ctx->audit_out = o;
            need = sizeof(TkAgentAuditMsg);
        } else if( strcmp( consumer->name, TILE_ID_TKDISP )==0 ) {
            if( FD_UNLIKELY( ctx->term_out!=ULONG_MAX ) ) FD_LOG_ERR(( "tkagnt: more than one terminal-result output" ));
            ctx->term_out = o;
            need = sizeof(TkAgentResultMsg);
        } else if( strcmp( consumer->name, TILE_ID_TKTOOL )==0 ) {
            /* The tool broker link of the full workflow.  No tool call exists yet
               (the agent is one request, one model dispatch, one result), so
               nothing is ever published here; the link is declared, bound and
               left idle. */
            if( FD_UNLIKELY( tool_outs ) ) FD_LOG_ERR(( "tkagnt: more than one tool output" ));
            tool_outs++;
            continue;
        } else {
            FD_LOG_ERR(( "tkagnt: output %lu goes to unexpected tile %s", o, consumer->name ));
            return;
        }
        stk_link_out_init( &ctx->out[o], topo, tile, o, need );
    }
    if( FD_UNLIKELY( ctx->audit_out==ULONG_MAX ) ) FD_LOG_ERR(( "tkagnt: no audit output (tkaudt)" ));
    if( FD_UNLIKELY( ctx->term_out==ULONG_MAX ) )  FD_LOG_ERR(( "tkagnt: no terminal-result output (tkdisp)" ));

    /* Every configured tier has exactly one request link and one result link;
       an extra or missing link is a topology the contract does not describe. */
    ulong tiers = 0UL;
    for( ulong t=0UL; t<TKAGNT_TIERS; t++ ) {
        int has_out = ctx->model_out[t]!=ULONG_MAX;
        int has_in  = ctx->model_in[t]!=ULONG_MAX;
        if( FD_UNLIKELY( has_out!=has_in ) )
            FD_LOG_ERR(( "tkagnt: tier %lu needs both a request and a result link", t ));
        if( has_out ) { ctx->configured_mask = (uint16_t)(ctx->configured_mask | (1U<<t)); tiers++; }
    }
    if( FD_UNLIKELY( tiers==0UL || tile->in_cnt!=1UL+tiers || tile->out_cnt!=tiers+2UL+tool_outs || model_outs!=tiers ) )
        FD_LOG_ERR(( "tkagnt: link counts (in %lu, out %lu) do not match %lu configured tiers", tile->in_cnt, tile->out_cnt, tiers ));

    /* Read-only join of the committed-order watermark tkaudt publishes. */
    ulong wm_obj = tk_topo_audit_watermark_obj( topo );
    if( FD_UNLIKELY( wm_obj==ULONG_MAX ) )
        FD_LOG_ERR(( "tkagnt: the topology has no audit watermark" ));
    ctx->watermark = fd_fseq_join( fd_topo_obj_laddr( (fd_topo_t *)topo, wm_obj ) );
    if( FD_UNLIKELY( !ctx->watermark ) )
        FD_LOG_ERR(( "tkagnt: cannot join the audit watermark" ));

    FD_LOG_NOTICE(( "tkagnt: unprivileged init tiers=%lu mask=0x%x req_in=%lu audit_out=%lu term_out=%lu",
                    tiers, (uint)ctx->configured_mask, ctx->req_in, ctx->audit_out, ctx->term_out ));
}

/* Lossless backpressure for new agent requests.  A request is left queued
   upstream (return -1) while there is nowhere to put it; the slot and run
   entry checked here stay free until AFTER_FRAG admits it (this is the only
   input that admits requests). */
static int
tkagnt_before_frag( tkagnt_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig ) {
    (void)seq; (void)sig;
    if( in_idx!=ctx->req_in ) return 0;
    if( tkagnt_free_slot( ctx )<0 || !tkagnt_has_run_room( ctx ) ) return -1;
    return 0;
}

static void
tkagnt_during_frag( tkagnt_ctx_t * ctx,
                    ulong          in_idx,
                    ulong          seq,
                    ulong          sig,
                    ulong          chunk,
                    ulong          sz,
                    ulong          ctl ) {
    (void)seq;

    ctx->stage_valid = 0;

    if( in_idx>=ctx->in_cnt ) return;
    stk_link_in_t const * in = &ctx->in[in_idx];
    if( !sz || sz>(ulong)TK_MP_LINK_MTU || !in->wksp ) return;
    if( FD_UNLIKELY( !stk_link_in_contains( in, chunk ) ) ) return;

    /* What the link carries is fixed by who produces it; the sig must agree. */
    ulong want = ctx->in_tier[in_idx]>=0 ? TK_LINK_SIG_MODEL_RESULT : TK_LINK_SIG_AGENT_REQUEST;
    if( FD_UNLIKELY( sig!=want ) ) return;

    if( in_idx==ctx->req_in ) {
        /* One whole, fixed-size request per fragment; anything else is dropped. */
        ctx->stage_is_req = 1;
        ctx->stage_in     = in_idx;
        if( FD_UNLIKELY( sz!=sizeof(TkAgentRequestMsg) ||
                         !fd_frag_meta_ctl_som( ctl ) || !fd_frag_meta_ctl_eom( ctl ) ) ) {
            ctx->stage_sz    = 0UL;     /* AFTER_FRAG counts it as dropped */
            ctx->stage_valid = 1;
            return;
        }
        memcpy( &ctx->stage_req, stk_link_in_laddr( in, chunk ), sizeof(TkAgentRequestMsg) );
        ctx->stage_sz    = sz;
        ctx->stage_valid = 1;
        return;
    }
    ctx->stage_is_req = 0;

    /* Copy first, then judge the copy: the producer may overrun while we read,
       and fd_stem discards the fragment in that case. */
    memcpy( ctx->stage, stk_link_in_laddr( in, chunk ), sz );
    ctx->stage_in    = in_idx;
    ctx->stage_sz    = sz;
    ctx->stage_som   = fd_frag_meta_ctl_som( ctl );
    ctx->stage_eom   = fd_frag_meta_ctl_eom( ctl );
    ctx->stage_valid = 1;
}

/* ─── Hook queries ─── */

static TkAgentRouteDirective
tkagnt_route( tkagnt_ctx_t * ctx, uint8_t request_type, uint8_t requested_tier ) {
    TkAgentRouteQuery q;
    memset( &q, 0, sizeof(q) );
    q.configured_mask = ctx->configured_mask;
    q.request_type    = request_type;
    q.requested_tier  = requested_tier;
    return ctx->hooks.route( &q );
}

/* ─── Admission ─── */

/* A whole agent request is staged.  Accept it as the next run: assign its
   admission ordinal, resolve its prompt, ask the Zig router where it goes, and
   either stage its model request in a slot or resolve it as denied. */
static void
tkagnt_admit( tkagnt_ctx_t * ctx ) {
    TkAgentRequestMsg const * req = &ctx->stage_req;

    uint64_t seq = ++ctx->admitted;
    tkagnt_run_t * r = tkagnt_run_at( ctx, seq );
    memset( r, 0, sizeof(*r) );
    r->agent_seq        = seq;
    r->run_id           = req->scope.run_id;
    memcpy( r->trace_id, req->scope.trace_id, sizeof(r->trace_id) );
    r->slot             = -1;
    r->tier             = TK_AGENT_TIER_NONE;
    r->source_tier      = TK_AGENT_TIER_NONE;
    r->recommended_tier = TK_AGENT_TIER_NONE;

    /* A capacity or drain refusal is still an accepted request: it gets its
       own audited terminal result. */
    if( ctx->draining )                    { tkagnt_resolve( ctx, r, TK_AGENT_OUT_SHUTDOWN, 0 ); return; }

    if( req->version!=TK_AGENT_WIRE_VERSION || !tk_model_request_well_formed( &req->scope ) ) {
        tkagnt_resolve( ctx, r, TK_AGENT_OUT_DENY_INVALID_REQUEST, 0 );
        return;
    }
    memcpy( r->policy_version, req->scope.policy_version, sizeof(r->policy_version) );
    memcpy( r->model_id, req->scope.model_id, sizeof(r->model_id) );
    r->envelope_hash = tk_model_envelope_hash( req->scope.capability_envelope_id );
    r->request_type  = req->request_type;
    r->content_type  = req->request_type==TK_AGENT_REQ_EMBEDDING ? TK_MP_CT_EMBEDDING : TK_MP_CT_CHAT;

    /* The prompt the request names must be one the table holds, by hash and
       length; nothing else can stand in for it. */
    uint8_t const * prompt = tkagnt_prompt_lookup( &req->prompt_ref );
    if( !prompt ) {
        memset( r->failed_scope_dim, 0, sizeof(r->failed_scope_dim) );
        memcpy( r->failed_scope_dim, "prompt_ref", sizeof("prompt_ref")-1UL );
        tkagnt_resolve( ctx, r, TK_AGENT_OUT_DENY_INVALID_REQUEST, 0 );
        return;
    }

    /* Where does it go?  The router is Zig's; this file only checks the answer. */
    TkAgentRouteDirective d = tkagnt_route( ctx, req->request_type, req->requested_tier );
    if( d.verdict==TK_AGENT_ROUTE_DENY_ABSENT_TIER ) {
        r->tier = d.tier;
        tkagnt_resolve( ctx, r, TK_AGENT_OUT_DENY_ABSENT_TIER, 0 );
        return;
    }
    if( d.verdict!=TK_AGENT_ROUTE_DISPATCH || !tkagnt_tier_configured( ctx, d.tier ) ) {
        /* Unknown verdict or a tier that is not configured: fail closed. */
        tkagnt_resolve( ctx, r, TK_AGENT_OUT_DENY_INVALID_REQUEST, 0 );
        return;
    }
    r->tier = d.tier;

    long slot = tkagnt_free_slot( ctx );
    if( slot<0 ) { tkagnt_resolve( ctx, r, TK_AGENT_OUT_CAPACITY, 0 ); return; }

    /* The model request is the scope with the agent's ordinal as request_id and
       no declared prompt hash (tkmodl computes it from the bytes it receives),
       followed by the prompt. */
    ulong prompt_len = req->prompt_ref.prompt_len;
    ModelRequestMsg scope = req->scope;
    scope.request_id  = seq;
    scope.prompt_hash = 0UL;
    uint8_t * dst = tkagnt_slot_buf( ctx, slot );
    memcpy( dst, &scope, sizeof(scope) );
    memcpy( dst+sizeof(scope), prompt, prompt_len );
    ctx->slots[slot].used = 1;
    ctx->slots[slot].len  = sizeof(scope) + prompt_len;
    r->slot        = (int8_t)slot;
    r->prompt_hash = req->prompt_ref.prompt_hash;
    r->deadline    = req->scope.timeout_ms
                   ? (tk_ns_t)req->scope.timeout_ms*TKAGNT_NS_PER_MS
                   : TKAGNT_DEFAULT_MODEL_TIMEOUT_NS;     /* a duration until dispatch completes */
    r->state       = RUN_ADMITTED;
}

/* ─── Results ─── */

/* The oldest run awaiting a result from `tier`, or NULL. */
static tkagnt_run_t *
tkagnt_awaiting( tkagnt_ctx_t * ctx, ulong tier ) {
    for( uint64_t s=ctx->term_seq; s<=ctx->admitted; s++ ) {
        tkagnt_run_t * r = tkagnt_run_at( ctx, s );
        if( r->state==RUN_AWAIT && r->tier==tier ) return r;
    }
    return NULL;
}

/* A complete, verified result stream from `tier` is in rx[model_in[tier]]. */
static void
tkagnt_on_result( tkagnt_ctx_t * ctx, ulong tier ) {
    tk_mp_rx_t const * rx = &ctx->rx[ctx->model_in[tier]];
    uint8_t const * body = rx->buf;
    ulong           len  = rx->cur.total_len;

    /* A result must match the one dispatch pending on that instance: same
       ordinal, run and content type.  An unknown, duplicate or stale result
       cannot complete a run; it is counted and ignored. */
    tkagnt_run_t * r = tkagnt_awaiting( ctx, tier );
    if( !r || rx->cur.model_request_id!=r->agent_seq || rx->cur.run_id!=r->run_id ||
        rx->cur.content_type!=r->content_type || len<sizeof(ModelResultMsg) ) {
        ctx->mismatched += 1UL;
        return;
    }
    ModelResultMsg res;
    memcpy( &res, body, sizeof(res) );
    if( res.version!=TKMODL_WIRE_VERSION || res.request_id!=r->agent_seq || res.run_id!=r->run_id ||
        memcmp( res.model_id, r->model_id, sizeof(res.model_id) )!=0 ) {
        ctx->mismatched += 1UL;
        return;
    }

    uint8_t const * content     = body + sizeof(res);
    ulong           content_len = len - sizeof(res);
    ctx->inst_busy[tier] = 0;
    r->has_model_record  = 1;     /* tkmodl publishes its audit record before the result */
    r->model_decision    = res.decision;
    r->source_tier       = (uint8_t)tier;
    r->total_tokens      = res.total_tokens;
    memcpy( r->failed_scope_dim, res.failed_scope_dim, sizeof(r->failed_scope_dim) );
    ctx->results += 1UL;
    ctx->tokens  += res.total_tokens;

    /* The hashes tkmodl reports must be those of the bytes that arrived. */
    int allowed = res.decision==MODEL_ALLOW_REPLAY || res.decision==MODEL_ALLOW_LIVE;
    if( res.prompt_hash!=r->prompt_hash ) { tkagnt_resolve( ctx, r, TK_AGENT_OUT_RESULT_MISMATCH, 1 ); return; }
    if( allowed ) {
        if( content_len==0UL || tk_mp_message_hash( content, content_len )!=res.response_hash ) {
            tkagnt_resolve( ctx, r, TK_AGENT_OUT_TRANSPORT_FAILURE, 1 );
            return;
        }
        r->response_len  = (uint32_t)content_len;
        r->response_hash = res.response_hash;
    } else if( content_len!=0UL ) {
        tkagnt_resolve( ctx, r, TK_AGENT_OUT_TRANSPORT_FAILURE, 1 );
        return;
    }

    /* What the result means is Zig's decision. */
    TkAgentInterpretQuery q;
    memset( &q, 0, sizeof(q) );
    q.content        = content;
    q.content_len    = (uint32_t)content_len;
    q.request_type   = r->request_type;
    q.source_tier    = (uint8_t)tier;
    q.model_decision = res.decision;
    TkAgentInterpretDirective d = ctx->hooks.interpret( &q );

    uint8_t outcome;
    if( d.action==TK_AGENT_ACT_FINAL ) {
        outcome = TK_AGENT_OUT_OK;
        if( d.confidence>TK_AGENT_CONF_HIGH ||
            ( d.recommended_tier!=TK_AGENT_TIER_NONE && d.recommended_tier>=TK_AGENT_TIER_COUNT ) )
            outcome = TK_AGENT_OUT_INVALID_CONTENT;     /* a malformed directive fails closed */
        else {
            r->confidence       = d.confidence;
            r->recommended_tier = d.recommended_tier;
            if( r->request_type==TK_AGENT_REQ_EMBEDDING ) ctx->embeddings += 1UL;
        }
    } else if( d.action==TK_AGENT_ACT_FAIL ) {
        switch( d.why ) {
        case TK_AGENT_WHY_MODEL_DENIED:      outcome = TK_AGENT_OUT_MODEL_DENIED;      break;
        case TK_AGENT_WHY_INVALID_TIER:      outcome = TK_AGENT_OUT_INVALID_TIER;      break;
        case TK_AGENT_WHY_CONTENT_TOO_LARGE: outcome = TK_AGENT_OUT_CONTENT_TOO_LARGE; break;
        default:                             outcome = TK_AGENT_OUT_INVALID_CONTENT;   break;
        }
        r->confidence       = d.confidence;
        r->recommended_tier = d.recommended_tier<TK_AGENT_TIER_COUNT ? d.recommended_tier : TK_AGENT_TIER_NONE;
    } else {
        outcome = TK_AGENT_OUT_INVALID_CONTENT;
    }
    tkagnt_resolve( ctx, r, outcome, 1 );
}

/* A result stream from `tier` failed reassembly.  If the failed message is the
   pending dispatch, that run ends in a transport failure; otherwise it is
   stale or unknown and only counted. */
static void
tkagnt_on_result_failure( tkagnt_ctx_t * ctx, ulong tier ) {
    tk_mp_rx_t const * rx = &ctx->rx[ctx->model_in[tier]];
    ctx->transport_dropped += 1UL;
    tkagnt_run_t * r = tkagnt_awaiting( ctx, tier );
    if( !r || rx->fail.model_request_id!=r->agent_seq || rx->fail.run_id!=r->run_id ) return;
    ctx->inst_busy[tier] = 0;
    tkagnt_resolve( ctx, r, TK_AGENT_OUT_TRANSPORT_FAILURE, 1 );
}

static void
tkagnt_after_frag( tkagnt_ctx_t *      ctx,
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

    if( ctx->stage_is_req ) {
        /* A malformed request fragment was never accepted. */
        if( !ctx->stage_sz ) { ctx->transport_dropped += 1UL; return; }
        tkagnt_admit( ctx );
        return;
    }

    ulong in = ctx->stage_in;
    tk_mp_rx_t * rx = &ctx->rx[in];
    tk_ns_t now = (tk_ns_t)fd_log_wallclock_nanos();

    tk_mp_status_t st = tk_mp_rx_feed( rx, ctx->stage, ctx->stage_sz, ctx->stage_som, ctx->stage_eom, now );
    if( st==TK_MP_ERR_INTERLEAVED ) {
        /* The producer abandoned a message and started another. */
        tkagnt_on_result_failure( ctx, (ulong)ctx->in_tier[in] );
        st = tk_mp_rx_feed( rx, ctx->stage, ctx->stage_sz, ctx->stage_som, ctx->stage_eom, now );
    }

    if( st==TK_MP_COMPLETE ) {
        tkagnt_on_result( ctx, (ulong)ctx->in_tier[in] );
    } else if( (int)st>=(int)TK_MP_ERR_VERSION ) {
        /* A malformed stream completes nothing; a broken result ends the run
           it answered. */
        tkagnt_on_result_failure( ctx, (ulong)ctx->in_tier[in] );
    }
}

/* ─── Publication (AFTER_CREDIT only) ─── */

static void
tkagnt_publish_one( tkagnt_ctx_t * ctx, fd_stem_context_t * stem, ulong out, ulong sig,
                    void const * msg, ulong sz ) {
    stk_link_out_publish( &ctx->out[out], stem, out, sig, msg, sz );   /* single-fragment record */
}

static void
tkagnt_copy_text( uint8_t * dst, ulong dst_sz, char const * src ) {
    memset( dst, 0, dst_sz );
    ulong n = strlen( src );
    if( n>=dst_sz ) n = dst_sz-1UL;
    memcpy( dst, src, n );
}

/* The audit record for a resolved run: a proposal for a completed one, a
   denial for any other outcome.  Hashes and attribution only. */
static void
tkagnt_build_audit( tkagnt_run_t const * r, TkAgentAuditMsg * a ) {
    memset( a, 0, sizeof(*a) );
    a->version                  = TK_AGENT_WIRE_VERSION;
    a->has_model_record         = r->has_model_record;
    a->run_id                   = r->run_id;
    a->agent_seq                = r->agent_seq;
    a->capability_envelope_hash = r->envelope_hash;
    memcpy( a->trace_id, r->trace_id, sizeof(a->trace_id) );
    memcpy( a->policy_version, r->policy_version, sizeof(a->policy_version) );
    if( r->outcome==TK_AGENT_OUT_OK ) {
        a->record_type = RECORD_PROPOSAL;
        tkagnt_copy_text( a->payload.proposal.proposal_type, sizeof(a->payload.proposal.proposal_type), "agent_result" );
        a->payload.proposal.proposal_hash  = r->response_hash;
        a->payload.proposal.approval_state = 0;
    } else {
        a->record_type = RECORD_DENIAL;
        tkagnt_copy_text( a->payload.denial.action_class, sizeof(a->payload.denial.action_class), "agent_run" );
        a->payload.denial.reason_code = r->outcome;
        memcpy( a->payload.denial.failed_scope_dim, r->failed_scope_dim, sizeof(a->payload.denial.failed_scope_dim) );
    }
}

static void
tkagnt_build_result( tkagnt_run_t const * r, TkAgentResultMsg * m ) {
    memset( m, 0, sizeof(*m) );
    m->version          = TK_AGENT_WIRE_VERSION;
    m->outcome          = r->outcome;
    m->confidence       = r->confidence;
    m->recommended_tier = r->recommended_tier;
    m->source_tier      = r->source_tier;
    m->request_type     = r->request_type;
    m->model_decision   = r->model_decision;
    m->response_len     = r->response_len;
    m->total_tokens     = r->total_tokens;
    m->run_id           = r->run_id;
    m->agent_seq        = r->agent_seq;
    m->prompt_hash      = r->prompt_hash;
    m->response_hash    = r->response_hash;
    m->proposal_hash    = r->outcome==TK_AGENT_OUT_OK ? r->response_hash : 0UL;
    memcpy( m->trace_id, r->trace_id, sizeof(m->trace_id) );
    memcpy( m->model_id, r->model_id, sizeof(m->model_id) );
}

static void
tkagnt_after_credit( tkagnt_ctx_t *      ctx,
                     fd_stem_context_t * stem,
                     int *               opt_poll_in,
                     int *               charge_busy ) {
    tk_ns_t now = (tk_ns_t)fd_log_wallclock_nanos();
    ulong budget = TKAGNT_STEM_BURST;

    /* Partial streams that stall are dropped, not held forever. */
    for( ulong i=0UL; i<ctx->in_cnt; i++ ) {
        if( i==ctx->req_in ) continue;     /* requests are whole fragments */
        tk_mp_status_t st = tk_mp_rx_poll( &ctx->rx[i], now );
        if( st==TK_MP_ERR_TIMEOUT ) tkagnt_on_result_failure( ctx, (ulong)ctx->in_tier[i] );
    }

    /* Administrative drain: stop dispatching, fail what has not been sent. */
    if( !ctx->draining && ctx->cnc && fd_cnc_signal_query( (fd_cnc_t *)ctx->cnc )==FD_CNC_SIGNAL_HALT ) {
        ctx->draining       = 1;
        ctx->drain_deadline = now + TKAGNT_DRAIN_DEADLINE_NS;
    }
    if( ctx->draining ) {
        for( uint64_t s=ctx->term_seq; s<=ctx->admitted; s++ ) {
            tkagnt_run_t * r = tkagnt_run_at( ctx, s );
            if( r->state==RUN_ADMITTED ) tkagnt_resolve( ctx, r, TK_AGENT_OUT_SHUTDOWN, 0 );
            /* A dispatch still unanswered at the deadline is cancelled. */
            if( r->state==RUN_AWAIT && now>ctx->drain_deadline ) {
                ctx->inst_busy[r->tier] = 0;
                tkagnt_resolve( ctx, r, TK_AGENT_OUT_SHUTDOWN, 0 );
            }
        }
    }

    /* 1. Terminal results, in admission order, once the audit record is
          committed (the watermark has reached the run's ordinal). */
    while( budget && ctx->term_seq<ctx->audit_seq ) {
        tkagnt_run_t * r = tkagnt_run_at( ctx, ctx->term_seq );
        if( r->state!=RUN_AUDITED ) break;
        ulong wm = fd_fseq_query( ctx->watermark );
        if( wm==TK_AUDIT_WATERMARK_NONE || wm<r->agent_seq ) break;     /* not committed yet */
        TkAgentResultMsg m;
        tkagnt_build_result( r, &m );
        tkagnt_publish_one( ctx, stem, ctx->term_out, TK_LINK_SIG_AGENT_RESULT, &m, sizeof(m) );
        r->state = RUN_DONE;
        if( r->outcome!=TK_AGENT_OUT_OK ) ctx->denied += 1UL;
        ctx->terminal_done += 1UL;
        ctx->term_seq      += 1UL;
        budget--;
        *charge_busy = 1;
    }

    /* 2. Audit records, in admission order, for resolved runs.  Stops at the
          first run still in flight so the committed order is the admission
          order whatever order the models answer in. */
    while( budget && ctx->audit_seq<=ctx->admitted ) {
        tkagnt_run_t * r = tkagnt_run_at( ctx, ctx->audit_seq );
        if( r->state!=RUN_RESOLVED ) break;
        /* A model that never answered: the run's deadline passed. */
        TkAgentAuditMsg a;
        tkagnt_build_audit( r, &a );
        tkagnt_publish_one( ctx, stem, ctx->audit_out, TK_LINK_SIG_AGENT_AUDIT, &a, sizeof(a) );
        r->state = RUN_AUDITED;
        ctx->audit_seq += 1UL;
        budget--;
        *charge_busy = 1;
    }

    /* 3. Model deadlines. */
    for( uint64_t s=ctx->term_seq; s<=ctx->admitted; s++ ) {
        tkagnt_run_t * r = tkagnt_run_at( ctx, s );
        if( r->state==RUN_AWAIT && now>r->deadline ) {
            ctx->inst_busy[r->tier] = 0;
            tkagnt_resolve( ctx, r, TK_AGENT_OUT_MODEL_TIMEOUT, 0 );
        }
    }

    /* 4. Dispatch waiting runs to free instances, in admission order, then send
          request fragments with what budget is left. */
    if( !ctx->draining ) {
        for( uint64_t s=ctx->term_seq; s<=ctx->admitted; s++ ) {
            tkagnt_run_t * r = tkagnt_run_at( ctx, s );
            if( r->state!=RUN_ADMITTED || ctx->inst_busy[r->tier] ) continue;
            tk_ns_t dur = r->deadline;     /* the model-wait duration, stored at admission */
            if( tk_mp_tx_begin( &ctx->tx[r->tier], TK_MP_DIR_REQUEST, r->content_type, r->run_id, r->agent_seq,
                                tkagnt_slot_buf( ctx, r->slot ), ctx->slots[r->slot].len )!=0 ) {
                tkagnt_resolve( ctx, r, TK_AGENT_OUT_DENY_INVALID_REQUEST, 0 );
                continue;
            }
            r->deadline              = dur;
            ctx->inst_busy[r->tier]  = 1;
            ctx->tx_active[r->tier]  = 1;
            r->state                 = RUN_SENDING;
            ctx->dispatched         += 1UL;
        }
    }
    for( ulong t=0UL; t<TKAGNT_TIERS && budget; t++ ) {
        if( !ctx->tx_active[t] ) continue;
        while( budget && !tk_mp_tx_done( &ctx->tx[t] ) ) {
            ulong out = ctx->model_out[t];
            int som, eom;
            ulong sz = tk_mp_tx_frag( &ctx->tx[t], (uint8_t *)stk_link_out_laddr( &ctx->out[out] ), &som, &eom );
            stk_link_out_commit( &ctx->out[out], stem, out, TK_LINK_SIG_MODEL_REQUEST, sz, fd_frag_meta_ctl( 0UL, som, eom, 0 ) );
            budget--;
            *charge_busy = 1;
        }
        if( tk_mp_tx_done( &ctx->tx[t] ) ) {
            ctx->tx_active[t] = 0;
            /* The request is out: its slot is free and the model's clock starts. */
            for( uint64_t s=ctx->term_seq; s<=ctx->admitted; s++ ) {
                tkagnt_run_t * r = tkagnt_run_at( ctx, s );
                if( r->state==RUN_SENDING && r->tier==t ) {
                    if( r->slot>=0 ) { ctx->slots[r->slot].used = 0; r->slot = -1; }
                    r->deadline = now + r->deadline;
                    r->state    = RUN_AWAIT;
                }
            }
        }
    }

    /* Counters for the supervisor's snapshot (tile_registry.zig). */
    stk_publish_counter( ctx->cnc, 0UL, ctx->dispatched );
    stk_publish_counter( ctx->cnc, 1UL, ctx->results );
    stk_publish_counter( ctx->cnc, 2UL, ctx->denied );
    stk_publish_counter( ctx->cnc, 3UL, ctx->tokens );
    stk_publish_counter( ctx->cnc, 4UL, ctx->embeddings );
    /* Unreliable diagnostic link: draws no credit, STEM_BURST is unaffected. */
    stk_diag_publish( &ctx->diag, stem, ctx->req_in, 0UL, ctx->dispatched + ctx->denied,
                      ctx->mismatched + ctx->transport_dropped, 0UL );

    /* Shutdown.  Set only after the last publication above, so the stem
       cannot stop with an accepted run still owed a terminal result. */
    int all_done = ctx->term_seq>ctx->admitted && ctx->audit_seq>ctx->admitted;
    if( ctx->draining ) {
        if( all_done ) ctx->input_exhausted = 1;
        else if( now>ctx->drain_deadline+TKAGNT_DRAIN_GRACE_NS ) {
            /* The audit path did not catch up in time: stop rather than hang.
               Whatever is still owed a terminal result is reported by the
               counters (admitted vs terminal_done). */
            FD_LOG_WARNING(( "tkagnt: drain deadline passed with %lu terminal result(s) owed",
                             (ulong)(ctx->admitted - ctx->terminal_done) ));
            ctx->input_exhausted = 1;
        }
    } else if( ctx->event_count && ctx->terminal_done>=ctx->event_count && all_done ) {
        ctx->input_exhausted = 1;
    }

    /* SHOULD_SHUTDOWN is read at the top of the next iteration, but fd_stem
       would still poll one input fragment in this one.  A request admitted
       there is counted and resolved but never audited or published, so
       it would be accepted and owed a terminal result that never comes.  Leave
       the request unread instead: its producer is back-pressured. */
    if( ctx->input_exhausted ) *opt_poll_in = 0;
}

/* ─── Run entry point ─── */

static void
tkagnt_run_entry( fd_topo_t *      topo,
                  fd_topo_tile_t * tile ) {
    void * scratch = fd_topo_obj_laddr( topo, tile->tile_obj_id );
    tkagnt_ctx_t * ctx = STK_GET_CTX(tkagnt_ctx_t, scratch, TKAGNT_CTX_ALIGN);

    FD_LOG_DEBUG(( "tkagnt: run entry ctx=%p tile=%s:%lu", (void*)ctx, tile->name, tile->id ));

    ulong cnc_obj_id = tk_topo_find_tile_obj( topo, tile->id, "cnc" );
    if( FD_UNLIKELY( cnc_obj_id == ULONG_MAX ) )
        FD_LOG_ERR(( "tkagnt: CNC object not found for tile %lu", tile->id ));
    ctx->cnc = fd_topo_obj_laddr( topo, cnc_obj_id );

    tkagnt_run( topo, tile );

    tile->allow_shutdown = 1;
    FD_LOG_DEBUG(( "tkagnt: run exit ctx=%p admitted=%lu dispatched=%lu results=%lu denied=%lu",
                   (void*)ctx, ctx->admitted, ctx->dispatched, ctx->results, ctx->denied ));
}

fd_topo_run_tile_t TK_AGENT_RUN = {
    .name                     = TILE_ID_TKAGNT,
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
    .scratch_align            = tkagnt_scratch_align_tile,
    .scratch_footprint        = tkagnt_scratch_footprint_tile,
    .loose_footprint          = NULL,
    .privileged_init          = tkagnt_privileged_init,
    .unprivileged_init        = tkagnt_unprivileged_init,
    .run                      = tkagnt_run_entry,
    .rlimit_file_cnt_fn       = NULL,
};

STK_DEFINE_RUN_TILE_ACCESSORS(
    tk_get_agent,
    TK_AGENT_RUN,
    tkagnt_tile_scratch_align,
    tkagnt_tile_scratch_footprint
)

/* ─── Scratch-base accessors (for tests and the supervisor) ─── */

#define TKAGNT_CTX(scratch) STK_GET_CTX(tkagnt_ctx_t, scratch, TKAGNT_CTX_ALIGN)

ulong tkagnt_admitted( void * s )          { return TKAGNT_CTX(s)->admitted; }
ulong tkagnt_terminal_done( void * s )     { return TKAGNT_CTX(s)->terminal_done; }
ulong tkagnt_dispatched( void * s )        { return TKAGNT_CTX(s)->dispatched; }
ulong tkagnt_results( void * s )           { return TKAGNT_CTX(s)->results; }
ulong tkagnt_denied( void * s )            { return TKAGNT_CTX(s)->denied; }
ulong tkagnt_tokens( void * s )            { return TKAGNT_CTX(s)->tokens; }
ulong tkagnt_embeddings( void * s )        { return TKAGNT_CTX(s)->embeddings; }
ulong tkagnt_mismatched( void * s )        { return TKAGNT_CTX(s)->mismatched; }
ulong tkagnt_transport_dropped( void * s ) { return TKAGNT_CTX(s)->transport_dropped; }
