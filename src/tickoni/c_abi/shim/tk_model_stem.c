/* tk_model_stem.c — Stem fd_stem tile for tkmodl (fixture/replay only).

 * Scope: this tile is the governed model gateway's lifecycle, NOT a provider
 * transport.  It reaches no network and calls no HTTP backend.  A request is
 * governed with the validator.zig branch order, and an allowed replay request
 * is answered from a bounded, versioned fixture table and its captured content,
 * both loaded at init.  A live request is denied (MODEL_DENY_LIVE_PROVIDER_
 * DISABLED); a configuration that enables a live provider is rejected at
 * tkmodl_configure().
 *
 * Transport: the request link carries one logical message as a contiguous
 * multipart fragment stream (tk_multipart_wire.h), body = ModelRequestMsg +
 * prompt bytes.  The tile reassembles it, accepts it only after every byte and
 * the whole-message hash verify, computes the prompt hash from the bytes it
 * actually received (never trusting a caller-declared hash), and answers with a
 * multipart result, body = ModelResultMsg + response bytes.  A malformed or
 * incomplete stream produces no governance, no audit record and no result: it
 * is dropped and counted, and the requester's own deadline turns the missing
 * result into an audited terminal failure.  The audit link carries one
 * hash-and-metadata-only record and never any content.
 *
 * Follows the fd_stem callback contract in stem_helpers.h:
 * - DURING_FRAG: validate framing, copy the fragment out of the input dcache
 *   into the staged copy.  Stages only.
 * - AFTER_FRAG: feed the staged fragment to the reassembler; on a complete
 *   verified request, govern it, resolve the fixture and its content, publish
 *   the audit record and the first result fragments.
 * - AFTER_CREDIT: publish the remaining result fragments, one stem credit
 *   reservation at a time, and stop polling input while a result is being sent
 *   (one request in flight), so no message is lost or overwritten.
 * - SHOULD_SHUTDOWN: event_count exhaustion + CNC HALT, but never mid-result.
 *
 * Output links are identified by their consumer tile (tkaudt / tkagnt), not
 * by declaration order.
 */

#define _GNU_SOURCE

#include "firedancer.h"
#include "audit_schema.h"
#include "tk_multipart.h"
#include "tk_model_request.h"
#include "tickoni/c_abi/shim/stem_helpers.h"
#include "tickoni/c_abi/topo_run/tk_model_stem.h"

#include "disco/topo/fd_topo.h"
#include "util/wksp/fd_wksp.h"
#include "util/fd_util.h"
#include "ballet/siphash13/fd_siphash13.h"

#include <string.h>
#include <stddef.h>

/* ─── Context ─── */

/* Fixture content store (TKMODL_CONTENT_STORE_BYTES, audit_schema.h): the
   captured response bytes for the fixture table, outside the audit record.
   Process-local (each tkmodl runs in its own process), loaded once at init
   through tkmodl_set_fixture_content(). */

/* Result body = ModelResultMsg + content, so content is bounded by the
   multipart message ceiling less the header. */
#define TKMODL_CONTENT_MAX  ((ulong)TK_MP_MAX_MESSAGE_BYTES - sizeof(ModelResultMsg))

/* The reassembler times a partial request out after this long (ns). */
#define TKMODL_PARTIAL_TIMEOUT_NS  ((tk_ns_t)TK_MP_PARTIAL_TIMEOUT_MS*1000000LL)

/* Publications reserved per stem iteration: one audit record plus a bounded
   number of result fragments.  A larger result continues next iteration. */
#define TKMODL_STEM_BURST_FRAGS  4UL

typedef struct {
    /* Counters */
    uint64_t processed;     /* requests governed and answered */
    uint64_t allowed;
    uint64_t denied;
    uint64_t dropped;       /* requests discarded: transport error, bad body, id mismatch */

    /* Staged fragment (written in during_frag, fed in after_frag) */
    int      stage_valid;
    int      stage_som;
    int      stage_eom;
    ulong    stage_sz;
    uint8_t  stage[TK_MP_LINK_MTU];

    /* Request reassembly and result transmission.  rxbuf/txbuf are
       TK_MP_MAX_MESSAGE_BYTES each, in the tile scratch after this context. */
    tk_mp_rx_t rx;
    tk_mp_tx_t tx;
    int      tx_active;
    uint8_t * txbuf;

    /* Output cursors, indexed by role: 0 = audit (tkaudt), 1 = result (tkagnt). */
    ulong    audit_out_idx;
    ulong    result_out_idx;
    stk_link_out_t out[2];

    /* CNC reference for shutdown detection */
    void *   cnc;

    /* The request input (from tkagnt): its workspace and compact chunk bounds. */
    stk_link_in_t in;

    /* Event count gating */
    uint64_t event_count;
    int      input_exhausted;

    /* Configuration copy (governance limits + fixture table), fixed size. */
    TkModlRuntimeConfig config;
} tkmodl_ctx_t;

/* Forward declarations */
static void tkmodl_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tkmodl_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tkmodl_during_frag( tkmodl_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig,
                                ulong chunk, ulong sz, ulong ctl );
static void tkmodl_after_frag( tkmodl_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig,
                               ulong sz, ulong tsorig, ulong tspub, fd_stem_context_t * stem );
static void tkmodl_after_credit( tkmodl_ctx_t * ctx, fd_stem_context_t * stem, int * opt_poll_in, int * charge_busy );
static void tkmodl_run_entry( fd_topo_t * topo, fd_topo_tile_t * tile );

#define TKMODL_CTX_ALIGN alignof(tkmodl_ctx_t)

/* The most publications one loop iteration makes (an audit record plus result
   fragments, or result fragments alone): the credit gate reserves exactly that
   many slots per iteration. */
#define TKMODL_PUBLISH_PER_FRAG (1UL+TKMODL_STEM_BURST_FRAGS)

/* Generate a model-specific static stem specialization. */
#define STEM_NAME                         tkmodl
#define STEM_BURST                        (TKMODL_PUBLISH_PER_FRAG)
#define STEM_LAZY                         ((long)10e6)
#define STEM_CALLBACK_CONTEXT_TYPE        tkmodl_ctx_t
#define STEM_CALLBACK_CONTEXT_ALIGN       TKMODL_CTX_ALIGN
#define STEM_CALLBACK_DURING_HOUSEKEEPING(ctx) stk_cnc_liveness( (ctx)->cnc )
#define STEM_CALLBACK_DURING_FRAG         tkmodl_during_frag
#define STEM_CALLBACK_AFTER_FRAG          tkmodl_after_frag
#define STEM_CALLBACK_AFTER_CREDIT        tkmodl_after_credit
/* Never stop mid-result: an accepted request is answered in full first. */
#define STEM_CALLBACK_SHOULD_SHUTDOWN(ctx) \
  ( !(ctx)->tx_active && \
    ( (ctx)->input_exhausted || \
      ( (ctx)->cnc && fd_cnc_signal_query( (fd_cnc_t *)(ctx)->cnc ) == FD_CNC_SIGNAL_HALT ) ) )

#include "disco/stem/fd_stem.c"

#undef STEM_NAME
#undef STEM_CALLBACK_CONTEXT_TYPE
#undef STEM_CALLBACK_CONTEXT_ALIGN
#undef STEM_CALLBACK_DURING_HOUSEKEEPING
#undef STEM_CALLBACK_DURING_FRAG
#undef STEM_CALLBACK_AFTER_FRAG
#undef STEM_CALLBACK_AFTER_CREDIT
#undef STEM_CALLBACK_SHOULD_SHUTDOWN

/* ─── Scratch footprint and alignment ─── */

/* The reassembly and transmit buffers follow the aligned context in the same
   scratch object.  The single definition of that layout: init uses it, and the
   footprint is derived from it. */
static inline uint8_t *
tkmodl_rxbuf_of( tkmodl_ctx_t * ctx ) {
    return (uint8_t *)fd_ulong_align_up( (ulong)ctx + sizeof(tkmodl_ctx_t), 64UL );
}

static inline uint8_t *
tkmodl_txbuf_of( tkmodl_ctx_t * ctx ) {
    return tkmodl_rxbuf_of( ctx ) + TK_MP_MAX_MESSAGE_BYTES;
}

static ulong
tkmodl_scratch_align_tile( void ) {
    return TKMODL_CTX_ALIGN;
}

static ulong
tkmodl_scratch_footprint_tile( fd_topo_tile_t const * tile ) {
    (void)tile;
    /* Fixed: the context embeds the staged fragment and the bounded
       configuration, and the two message buffers are a constant size, so the
       footprint depends on neither event count nor the configured limits or
       fixtures. */
    ulong footprint = fd_ulong_align_up( sizeof(tkmodl_ctx_t), 64UL );
    footprint += 2UL*(ulong)TK_MP_MAX_MESSAGE_BYTES;
    return fd_ulong_align_up( footprint, TKMODL_CTX_ALIGN );
}

/* ─── Behavior configuration ─── */

static uint64_t            tkmodl_event_count_param;
static TkModlRuntimeConfig tkmodl_config_param;
static int                 tkmodl_config_configured;

/* Captured response content for the fixture table, indexed like
   config.fixtures[]. */
static uint8_t tkmodl_content_store[TKMODL_CONTENT_STORE_BYTES];
static ulong   tkmodl_content_used;
static ulong   tkmodl_content_off[TKMODL_FIXTURE_CAP];
static ulong   tkmodl_content_len[TKMODL_FIXTURE_CAP];
static int     tkmodl_content_present[TKMODL_FIXTURE_CAP];

void
tkmodl_set_event_count( uint64_t event_count ) {
    tkmodl_event_count_param = event_count;
}

int
tkmodl_configure( TkModlRuntimeConfig const * cfg ) {
    if( !cfg )                                          return TKMODL_CFG_NULL;
    if( cfg->magic != TKMODL_CONFIG_MAGIC )             return TKMODL_CFG_BAD_MAGIC;
    if( cfg->version != TKMODL_CONFIG_VERSION )         return TKMODL_CFG_BAD_VERSION;
    /* Fixture/replay only: a live provider is not reachable from this tile. */
    if( cfg->live_provider_enabled )                    return TKMODL_CFG_LIVE_PROVIDER;
    if( cfg->allowed_model_count > TKMODL_MAX_ALLOWED_MODELS ) return TKMODL_CFG_ALLOWLIST_BOUND;
    if( cfg->allowed_embedding_model_count > TKMODL_MAX_ALLOWED_MODELS ) return TKMODL_CFG_ALLOWLIST_BOUND;
    if( cfg->allowed_embedding_dimension_count > TKMODL_MAX_EMBEDDING_DIMENSIONS ) return TKMODL_CFG_ALLOWLIST_BOUND;
    if( cfg->fixture_count > TKMODL_FIXTURE_CAP )       return TKMODL_CFG_FIXTURE_BOUND;
    tkmodl_config_param      = *cfg;
    tkmodl_config_configured = 1;
    /* A new configuration invalidates any content loaded for the old one. */
    tkmodl_content_used = 0UL;
    memset( tkmodl_content_present, 0, sizeof(tkmodl_content_present) );
    return TKMODL_CFG_OK;
}

/* Installs the captured response bytes for the fixture whose key is `key`.
   Fail closed: the content must belong to a configured fixture, must hash (the
   canonical multipart whole-message hash) to that fixture's response_hash, and
   must fit the bounds.  Nothing is stored on error. */
int
tkmodl_set_fixture_content( uint64_t key, uint8_t const * bytes, uint32_t len ) {
    if( !tkmodl_config_configured || !bytes )  return TKMODL_CFG_CONTENT_NO_FIXTURE;
    for( ulong i=0UL; i<tkmodl_config_param.fixture_count; i++ ) {
        TkModlFixtureEntry const * f = &tkmodl_config_param.fixtures[i];
        if( f->key==0UL || f->key!=key ) continue;
        if( tkmodl_content_present[i] )                                   return TKMODL_CFG_CONTENT_DUPLICATE;
        if( len==0U || (ulong)len>TKMODL_CONTENT_MAX )                    return TKMODL_CFG_CONTENT_BOUND;
        if( tkmodl_content_used+(ulong)len>TKMODL_CONTENT_STORE_BYTES )   return TKMODL_CFG_CONTENT_BOUND;
        if( tk_mp_message_hash( bytes, len )!=f->response_hash )          return TKMODL_CFG_CONTENT_HASH;
        memcpy( tkmodl_content_store+tkmodl_content_used, bytes, len );
        tkmodl_content_off[i]     = tkmodl_content_used;
        tkmodl_content_len[i]     = len;
        tkmodl_content_present[i] = 1;
        tkmodl_content_used      += len;
        return TKMODL_CFG_OK;
    }
    return TKMODL_CFG_CONTENT_NO_FIXTURE;
}

/* ─── Pure helpers ─── */

int
tkmodl_request_well_formed( ModelRequestMsg const * req ) {
    return tk_model_request_well_formed( req );
}

static void
tkmodl_set_scope_dim( uint8_t * out, char const * name ) {
    if( !out ) return;
    memset( out, 0, TKMODL_SCOPE_DIM_LEN );
    ulong n = strlen( name );
    if( n >= TKMODL_SCOPE_DIM_LEN ) n = TKMODL_SCOPE_DIM_LEN - 1UL;
    memcpy( out, name, n );
}

/* Mirrors validator.zig:validateTkModlRequest branch order exactly for a chat
   request.  An embedding request (`is_embedding`) is governed the same way with
   two differences: its model is checked against the embedding allowlist, and
   its requested vector width must be non-zero and, when the instance restricts
   widths, one of the allowed ones (MODEL_DENY_EMBEDDING_DIMENSION) -- after the
   limits and before the live/replay checks.  Embedding governance is C-only;
   the retained Zig validator is the reference for chat. */
static uint8_t
tkmodl_validate_core( TkModlRuntimeConfig const * cfg,
                      ModelRequestMsg const *     req,
                      int                         is_embedding,
                      uint8_t *                   scope_dim_out ) {
    if( scope_dim_out ) memset( scope_dim_out, 0, TKMODL_SCOPE_DIM_LEN );

    /* Required scope fields — checked before all else. */
    if( req->model_id[0]==0 )               { tkmodl_set_scope_dim( scope_dim_out, "model_id" );               return MODEL_DENY_MISSING_SCOPE; }
    if( req->budget_id[0]==0 )              { tkmodl_set_scope_dim( scope_dim_out, "budget_id" );              return MODEL_DENY_MISSING_SCOPE; }
    if( req->policy_version[0]==0 )         { tkmodl_set_scope_dim( scope_dim_out, "policy_version" );         return MODEL_DENY_MISSING_SCOPE; }
    if( req->capability_envelope_id[0]==0 ) { tkmodl_set_scope_dim( scope_dim_out, "capability_envelope_id" ); return MODEL_DENY_MISSING_SCOPE; }
    if( req->capability[0]==0 )             { tkmodl_set_scope_dim( scope_dim_out, "capability" );             return MODEL_DENY_MISSING_SCOPE; }
    if( req->actor_role[0]==0 )             { tkmodl_set_scope_dim( scope_dim_out, "actor_role" );             return MODEL_DENY_MISSING_SCOPE; }
    if( req->workflow[0]==0 )               { tkmodl_set_scope_dim( scope_dim_out, "workflow" );               return MODEL_DENY_MISSING_SCOPE; }

    /* Model allowlist.  count == 0 means no restriction. */
    ulong n = is_embedding ? cfg->allowed_embedding_model_count : cfg->allowed_model_count;
    if( n > 0 ) {
        int allowed = 0;
        for( ulong i=0UL; i<n; i++ ) {
            uint8_t const * id = is_embedding ? cfg->allowed_embedding_model_ids[i] : cfg->allowed_model_ids[i];
            if( memcmp( req->model_id, id, TKMODL_MODEL_ID_LEN )==0 ) { allowed = 1; break; }
        }
        if( !allowed ) return MODEL_DENY_MODEL_NOT_ALLOWED;
    }

    /* Hard limits.  0 means no enforcement. */
    if( cfg->hard_max_output_tokens > 0 && req->max_output_tokens > cfg->hard_max_output_tokens )
        return MODEL_DENY_OUTPUT_LIMIT;
    if( cfg->hard_max_context_tokens > 0 && req->max_context_tokens > cfg->hard_max_context_tokens )
        return MODEL_DENY_CONTEXT_LIMIT;
    if( cfg->hard_max_retry_count > 0 && req->retry_limit > cfg->hard_max_retry_count )
        return MODEL_DENY_RETRY_LIMIT;

    /* Per-run budget: a single request cannot exceed the entire run budget. */
    if( cfg->per_run_token_budget > 0 && req->max_output_tokens > cfg->per_run_token_budget )
        return MODEL_DENY_BUDGET_EXHAUSTED;

    /* Embedding width: required, and within the instance's allowed set.  Never
       truncated or padded to fit. */
    if( is_embedding ) {
        if( req->embedding_dimensions==0U ) return MODEL_DENY_EMBEDDING_DIMENSION;
        if( cfg->allowed_embedding_dimension_count > 0 ) {
            int allowed = 0;
            for( ulong i=0UL; i<cfg->allowed_embedding_dimension_count; i++ )
                if( cfg->allowed_embedding_dimensions[i]==req->embedding_dimensions ) { allowed = 1; break; }
            if( !allowed ) return MODEL_DENY_EMBEDDING_DIMENSION;
        }
    }

    /* Live provider must be explicitly enabled for live-mode requests. */
    if( req->replay_mode == TKMODL_REPLAY_MODE_LIVE && !cfg->live_provider_enabled )
        return MODEL_DENY_LIVE_PROVIDER_DISABLED;

    /* Replay mode requires a non-zero substitution id. */
    if( req->replay_mode == TKMODL_REPLAY_MODE_REPLAY && req->replay_substitution_id == 0 )
        return MODEL_DENY_REPLAY_SUBSTITUTION_MISSING;

    return req->replay_mode == TKMODL_REPLAY_MODE_REPLAY ? MODEL_ALLOW_REPLAY : MODEL_ALLOW_LIVE;
}

uint8_t
tkmodl_validate( TkModlRuntimeConfig const * cfg,
                 ModelRequestMsg const *     req,
                 uint8_t *                   scope_dim_out ) {
    return tkmodl_validate_core( cfg, req, 0, scope_dim_out );
}

uint8_t
tkmodl_validate_embedding( TkModlRuntimeConfig const * cfg,
                           ModelRequestMsg const *     req,
                           uint8_t *                   scope_dim_out ) {
    return tkmodl_validate_core( cfg, req, 1, scope_dim_out );
}

/* Captured result for a replay request: the fixture whose key matches the
   request's substitution id AND whose captured prompt hash and model agree
   with the request.  A missing or mismatched capture is not substitutable.
   `req->prompt_hash` is the hash tkmodl computed from the prompt bytes it
   received. */
static TkModlFixtureEntry const *
tkmodl_find_fixture( TkModlRuntimeConfig const * cfg, ModelRequestMsg const * req, ulong * idx_out ) {
    for( ulong i=0UL; i<cfg->fixture_count; i++ ) {
        TkModlFixtureEntry const * f = &cfg->fixtures[i];
        if( f->key == 0 || f->key != req->replay_substitution_id ) continue;
        if( f->prompt_hash != req->prompt_hash ) return NULL;
        if( memcmp( f->model_id, req->model_id, TKMODL_MODEL_ID_LEN ) != 0 ) return NULL;
        *idx_out = i;
        return f;
    }
    return NULL;
}

/* ─── Scratch-base counter readers ─── */

ulong
tkmodl_ctx_processed( void * scratch ) {
    return STK_GET_CTX(tkmodl_ctx_t, scratch, TKMODL_CTX_ALIGN)->processed;
}

ulong
tkmodl_ctx_allowed( void * scratch ) {
    return STK_GET_CTX(tkmodl_ctx_t, scratch, TKMODL_CTX_ALIGN)->allowed;
}

ulong
tkmodl_ctx_denied( void * scratch ) {
    return STK_GET_CTX(tkmodl_ctx_t, scratch, TKMODL_CTX_ALIGN)->denied;
}

ulong
tkmodl_ctx_dropped( void * scratch ) {
    return STK_GET_CTX(tkmodl_ctx_t, scratch, TKMODL_CTX_ALIGN)->dropped;
}

/* ─── Callbacks ─── */

static void
tkmodl_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkmodl_ctx_t * ctx = STK_GET_CTX(tkmodl_ctx_t, scratch, TKMODL_CTX_ALIGN);

    /* Fail closed: a tkmodl process with no validated configuration would
       govern with unset limits and an empty fixture table. */
    if( FD_UNLIKELY( !tkmodl_config_configured ) )
        FD_LOG_ERR(( "tkmodl: runtime configuration was not set" ));

    memset( ctx, 0, sizeof(*ctx) );
    ctx->config      = tkmodl_config_param;
    ctx->event_count = tkmodl_event_count_param;
    ctx->txbuf       = tkmodl_txbuf_of( ctx );
    tk_mp_rx_init( &ctx->rx, TK_MP_DIR_REQUEST, tkmodl_rxbuf_of( ctx ), TKMODL_PARTIAL_TIMEOUT_NS );

    FD_LOG_NOTICE(( "tkmodl: privileged init ctx=%p fixtures=%u allowed_models=%u",
                    (void *)ctx,
                    (uint)ctx->config.fixture_count, (uint)ctx->config.allowed_model_count ));
}

/* Name of the first tile that consumes `link_id`, or NULL. */
static char const *
tkmodl_link_consumer( fd_topo_t const * topo, ulong link_id ) {
    for( ulong t=0UL; t<topo->tile_cnt; t++ ) {
        fd_topo_tile_t const * other = &topo->tiles[t];
        for( ulong i=0UL; i<other->in_cnt; i++ )
            if( other->in_link_id[i]==link_id ) return other->name;
    }
    return NULL;
}

static void
tkmodl_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkmodl_ctx_t * ctx = STK_GET_CTX(tkmodl_ctx_t, scratch, TKMODL_CTX_ALIGN);

    STK_UNPRIV_INIT(topo, tile, ctx);
    if( FD_UNLIKELY( !ctx->cnc ) )
        FD_LOG_ERR(( "tkmodl: CNC object not found for tile %lu", tile->id ));

    /* One request link in; one audit link (tkaudt) and one result link
       (tkagnt) out.  Anything else is a topology the contract does not
       describe.  Validate before indexing the link arrays. */
    if( FD_UNLIKELY( tile->in_cnt != 1UL ) )
        FD_LOG_ERR(( "tkmodl: expected exactly one input link, found %lu", tile->in_cnt ));
    if( FD_UNLIKELY( tile->out_cnt != 2UL ) )
        FD_LOG_ERR(( "tkmodl: expected exactly two output links, found %lu", tile->out_cnt ));
    stk_link_in_init( &ctx->in, topo, tile, 0UL, (ulong)TK_MP_LINK_MTU );

    /* Bind outputs by consumer identity, not declaration order. */
    ulong audit_idx = ULONG_MAX, result_idx = ULONG_MAX;
    for( ulong o=0UL; o<2UL; o++ ) {
        char const * consumer = tkmodl_link_consumer( topo, tile->out_link_id[o] );
        if( consumer && strcmp( consumer, TILE_ID_TKAUDT )==0 ) audit_idx = o;
        else if( consumer && strcmp( consumer, TILE_ID_TKAGNT )==0 ) result_idx = o;
    }
    if( FD_UNLIKELY( audit_idx==ULONG_MAX || result_idx==ULONG_MAX ) )
        FD_LOG_ERR(( "tkmodl: outputs must be exactly one tkaudt (audit) and one tkagnt (result) link" ));
    ctx->audit_out_idx  = audit_idx;
    ctx->result_out_idx = result_idx;

    ulong const need[2] = { sizeof(ModelAuditMsg), (ulong)TK_MP_LINK_MTU };
    ulong const outs[2] = { audit_idx, result_idx };
    for( ulong r=0UL; r<2UL; r++ ) stk_link_out_init( &ctx->out[r], topo, tile, outs[r], need[r] );

    FD_LOG_NOTICE(( "tkmodl: unprivileged init tile_id=%lu cnc=%p audit_out=%lu result_out=%lu",
                    tile->id, ctx->cnc, ctx->audit_out_idx, ctx->result_out_idx ));
}

static void
tkmodl_during_frag( tkmodl_ctx_t * ctx,
                    ulong          in_idx,
                    ulong          seq,
                    ulong          sig,
                    ulong          chunk,
                    ulong          sz,
                    ulong          ctl ) {
    (void)in_idx; (void)seq; (void)sig;

    ctx->stage_valid = 0;

    /* A multipart fragment is a header and at least one payload byte, up to the
       link MTU.  Exact-size checks belong to the reassembler, which sees the
       header. */
    if( !sz || sz>(ulong)TK_MP_LINK_MTU || !ctx->in.wksp )
        return;

    /* Chunk bounds: [chunk0, wmark] of the input dcache, workspace-relative. */
    if( FD_UNLIKELY( !stk_link_in_contains( &ctx->in, chunk ) ) )
        return;

    /* Copy first, then judge the copy: the producer may overrun while we
       read, and fd_stem discards the fragment in that case. */
    memcpy( ctx->stage, stk_link_in_laddr( &ctx->in, chunk ), sz );
    ctx->stage_sz    = sz;
    ctx->stage_som   = fd_frag_meta_ctl_som( ctl );
    ctx->stage_eom   = fd_frag_meta_ctl_eom( ctl );
    ctx->stage_valid = 1;
}

static void
tkmodl_publish_audit( tkmodl_ctx_t *      ctx,
                      fd_stem_context_t * stem,
                      ModelAuditMsg const * audit ) {
    stk_link_out_publish( &ctx->out[0], stem, ctx->audit_out_idx, (ulong)audit->record_type, audit, sizeof(*audit) );
}

/* Publishes up to `budget` result fragments from the transmit cursor.  The
   cursor advances only with each publish; the caller must not publish more
   than the credits the stem reserved for this iteration. */
static ulong
tkmodl_emit( tkmodl_ctx_t * ctx, fd_stem_context_t * stem, ulong budget ) {
    ulong n = 0UL;
    while( n<budget && !tk_mp_tx_done( &ctx->tx ) ) {
        int som, eom;
        ulong sz = tk_mp_tx_frag( &ctx->tx, (uint8_t *)stk_link_out_laddr( &ctx->out[1] ), &som, &eom );
        stk_link_out_commit( &ctx->out[1], stem, ctx->result_out_idx, TK_LINK_SIG_MODEL_RESULT, sz, fd_frag_meta_ctl( 0UL, som, eom, 0 ) );
        n++;
    }
    if( tk_mp_tx_done( &ctx->tx ) ) ctx->tx_active = 0;
    return n;
}

/* A verified, complete request body is in ctx->rx.buf.  Govern it, resolve the
   capture, publish the audit record and start the result. */
static void
tkmodl_handle_request( tkmodl_ctx_t * ctx, fd_stem_context_t * stem ) {
    uint8_t const * body = ctx->rx.buf;
    ulong           len  = ctx->rx.cur.total_len;

    /* The body is a ModelRequestMsg followed by the prompt. */
    if( len < sizeof(ModelRequestMsg) ) { ctx->dropped += 1UL; return; }
    ModelRequestMsg req;
    memcpy( &req, body, sizeof(req) );
    if( !tk_model_request_well_formed( &req ) ) { ctx->dropped += 1UL; return; }
    /* The identity inside the body must be the identity the stream was framed
       under, or the framing is not the request it claims to carry. */
    if( req.request_id!=ctx->rx.cur.model_request_id || req.run_id!=ctx->rx.cur.run_id ) {
        ctx->dropped += 1UL;
        return;
    }
    uint8_t const * prompt     = body + sizeof(req);
    ulong           prompt_len = len - sizeof(req);

    /* Never trust a caller-declared hash: it is computed from the bytes that
       crossed this boundary. */
    req.prompt_hash = tk_mp_message_hash( prompt, prompt_len );

    uint8_t scope_dim[TKMODL_SCOPE_DIM_LEN];
    int const is_embedding = ctx->rx.cur.content_type==TK_MP_CT_EMBEDDING;
    uint8_t decision = tkmodl_validate_core( &ctx->config, &req, is_embedding, scope_dim );

    TkModlFixtureEntry const * fixture = NULL;
    ulong fixture_idx = 0UL;
    if( decision == MODEL_ALLOW_REPLAY ) {
        fixture = tkmodl_find_fixture( &ctx->config, &req, &fixture_idx );
        /* A fixture without its captured content is not substitutable. */
        if( !fixture || !tkmodl_content_present[fixture_idx] ) {
            fixture  = NULL;
            decision = MODEL_DENY_REPLAY_SUBSTITUTION_MISSING;
        } else if( is_embedding && tkmodl_content_len[fixture_idx]!=(ulong)req.embedding_dimensions*4UL ) {
            /* The capture is a single vector; it must be exactly the width asked
               for, never truncated or padded to fit. */
            fixture  = NULL;
            decision = MODEL_DENY_EMBEDDING_DIMENSION;
        }
    } else if( decision == MODEL_ALLOW_LIVE ) {
        /* Unreachable (the configuration rejects a live provider), but never
           serve a live request from a fixture/replay tile. */
        decision = MODEL_DENY_LIVE_PROVIDER_DISABLED;
    }
    int const allowed = ( decision == MODEL_ALLOW_REPLAY );

    /* Result body: ModelResultMsg, then the captured response bytes. */
    ModelResultMsg result;
    memset( &result, 0, sizeof(result) );
    result.version                = TKMODL_WIRE_VERSION;
    result.decision               = decision;
    result.request_id             = req.request_id;
    result.run_id                 = req.run_id;
    result.prompt_hash            = req.prompt_hash;
    result.replay_substitution_id = req.replay_substitution_id;
    memcpy( result.model_id, req.model_id, sizeof(result.model_id) );
    memcpy( result.failed_scope_dim, scope_dim, sizeof(result.failed_scope_dim) );
    ulong content_len = 0UL;
    if( allowed ) {
        result.response_hash     = fixture->response_hash;
        result.prompt_tokens     = fixture->prompt_tokens;
        result.completion_tokens = fixture->completion_tokens;
        result.total_tokens      = fixture->total_tokens;
        result.latency_ms        = fixture->latency_ms;
        content_len = tkmodl_content_len[fixture_idx];
    }
    memcpy( ctx->txbuf, &result, sizeof(result) );
    if( content_len )
        memcpy( ctx->txbuf+sizeof(result), tkmodl_content_store+tkmodl_content_off[fixture_idx], content_len );

    if( tk_mp_tx_begin( &ctx->tx, TK_MP_DIR_RESULT, ctx->rx.cur.content_type,
                        req.run_id, req.request_id, ctx->txbuf, sizeof(result)+content_len )!=0 ) {
        ctx->dropped += 1UL;
        return;
    }

    /* Audit record: a model_call for an allowed request, a denial otherwise.
       Hashes and attribution only; no prompt, response or vector bytes. */
    ModelAuditMsg audit;
    memset( &audit, 0, sizeof(audit) );
    audit.version                  = TKMODL_WIRE_VERSION;
    audit.run_id                   = req.run_id;
    audit.request_id               = req.request_id;
    memcpy( audit.trace_id, req.trace_id, sizeof(audit.trace_id) );
    audit.capability_envelope_hash = tk_model_envelope_hash( req.capability_envelope_id );
    memcpy( audit.policy_version, req.policy_version, sizeof(audit.policy_version) );
    if( allowed ) {
        audit.record_type = RECORD_MODEL_CALL;
        WireModelCallPayload * p = &audit.payload.model_call;
        memcpy( p->model_id, req.model_id, sizeof(p->model_id) );
        p->prompt_hash            = req.prompt_hash;
        p->response_hash          = fixture->response_hash;
        p->token_estimate         = fixture->total_tokens;
        p->retry_count            = 0;
        memcpy( p->actor_role, req.actor_role, sizeof(p->actor_role) );
        memcpy( p->workflow, req.workflow, sizeof(p->workflow) );
        p->policy_decision_id     = req.policy_decision_id;
        p->replay_substitution_id = req.replay_substitution_id;
    } else {
        audit.record_type = RECORD_DENIAL;
        WireDenialPayload * p = &audit.payload.denial;
        memcpy( p->action_class, req.capability, sizeof(p->action_class) );
        p->reason_code = decision;
        memcpy( p->failed_scope_dim, scope_dim, sizeof(p->failed_scope_dim) );
    }

    /* The audit record goes out first, then the result.  If the process dies
       between them the requester sees no result and times out into an audited
       terminal failure; it never sees a result that was not audited. */
    tkmodl_publish_audit( ctx, stem, &audit );
    ctx->tx_active = 1;
    tkmodl_emit( ctx, stem, TKMODL_STEM_BURST_FRAGS );

    ctx->processed += 1;
    if( allowed ) ctx->allowed += 1; else ctx->denied += 1;

    /* CNC slot schema from tile_registry.zig: app[0]=allowed, app[1]=denied. */
    stk_publish_counter( ctx->cnc, 0UL, ctx->allowed );
    stk_publish_counter( ctx->cnc, 1UL, ctx->denied );

    /* Gate on processed: allowed and denied both count toward completion.  The
       shutdown condition also waits for the result to finish sending. */
    STK_EVENT_EXHAUSTED( ctx, ctx->event_count, ctx->processed );
}

static void
tkmodl_after_frag( tkmodl_ctx_t *      ctx,
                   ulong               in_idx,
                   ulong               seq,
                   ulong               sig,
                   ulong               sz,
                   ulong               tsorig,
                   ulong               tspub,
                   fd_stem_context_t * stem ) {
    (void)in_idx; (void)seq; (void)sig; (void)sz; (void)tsorig; (void)tspub;

    if( !ctx->stage_valid )
        return;
    ctx->stage_valid = 0;

    tk_ns_t now = (tk_ns_t)fd_log_wallclock_nanos();
    tk_mp_status_t st = tk_mp_rx_feed( &ctx->rx, ctx->stage, ctx->stage_sz, ctx->stage_som, ctx->stage_eom, now );
    if( st==TK_MP_ERR_INTERLEAVED ) {
        /* The producer abandoned a message and started another: count the
           abandoned one, then feed this same fragment as the new start. */
        ctx->dropped += 1UL;
        st = tk_mp_rx_feed( &ctx->rx, ctx->stage, ctx->stage_sz, ctx->stage_som, ctx->stage_eom, now );
    }
    if( st==TK_MP_COMPLETE ) {
        tkmodl_handle_request( ctx, stem );
    } else if( (int)st>=(int)TK_MP_ERR_VERSION ) {
        /* A malformed stream is dropped whole: nothing is governed, audited or
           answered for it. */
        ctx->dropped += 1UL;
    }
}

static void
tkmodl_after_credit( tkmodl_ctx_t *      ctx,
                     fd_stem_context_t * stem,
                     int *               opt_poll_in,
                     int *               charge_busy ) {
    /* A partial request that stalls is dropped, not held forever. */
    if( tk_mp_rx_poll( &ctx->rx, (tk_ns_t)fd_log_wallclock_nanos() )==TK_MP_ERR_TIMEOUT )
        ctx->dropped += 1UL;

    if( ctx->tx_active ) {
        /* One request in flight: do not take new input while a result is still
           being sent, so the transmit buffer is never reused under it. */
        *opt_poll_in = 0;
        if( tkmodl_emit( ctx, stem, TKMODL_STEM_BURST_FRAGS )>0UL ) *charge_busy = 1;
    }
}

/* ─── Run entry point ─── */

static void
tkmodl_run_entry( fd_topo_t *      topo,
                  fd_topo_tile_t * tile ) {
    void * scratch = fd_topo_obj_laddr( topo, tile->tile_obj_id );
    tkmodl_ctx_t * ctx = STK_GET_CTX(tkmodl_ctx_t, scratch, TKMODL_CTX_ALIGN);

    ulong cnc_obj_id = tk_topo_find_tile_obj( topo, tile->id, "cnc" );
    if( FD_UNLIKELY( cnc_obj_id == ULONG_MAX ) )
        FD_LOG_ERR(( "tkmodl: CNC object not found for tile %lu", tile->id ));
    ctx->cnc = fd_topo_obj_laddr( topo, cnc_obj_id );

    tkmodl_run( topo, tile );  /* stem_run loop */

    tile->allow_shutdown = 1;
}

/* ─── fd_topo_run_tile_t ─── */

fd_topo_run_tile_t TK_MODEL_RUN = {
    .name                     = TILE_ID_TKMODL,
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
    .scratch_align            = tkmodl_scratch_align_tile,
    .scratch_footprint        = tkmodl_scratch_footprint_tile,
    .loose_footprint          = NULL,
    .privileged_init          = tkmodl_privileged_init,
    .unprivileged_init        = tkmodl_unprivileged_init,
    .run                      = tkmodl_run_entry,
    .rlimit_file_cnt_fn       = NULL,
};

STK_DEFINE_RUN_TILE_ACCESSORS(
    tk_get_model,
    TK_MODEL_RUN,
    tkmodl_tile_scratch_align,
    tkmodl_tile_scratch_footprint
)
