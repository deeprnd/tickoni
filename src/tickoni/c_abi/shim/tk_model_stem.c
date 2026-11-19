/* tk_model_stem.c — Stem fd_stem tile for tkmodl (fixture/replay only).

 * Scope: this tile is the governed model gateway's lifecycle, NOT a provider
 * transport.  It reaches no network and calls no HTTP backend.  A request is
 * governed with the validator.zig branch order, and an allowed replay request
 * is answered from a bounded, versioned fixture table loaded at init.  A live
 * request is denied (MODEL_DENY_LIVE_PROVIDER_DISABLED); a configuration that
 * enables a live provider is rejected at tkmodl_configure().
 *
 * Follows the fd_stem callback contract in stem_helpers.h:
 * - DURING_FRAG: validate framing and wire shape, copy the request out of the
 *   input dcache into the staged copy.  Stages only — no governance, no
 *   counters, no progress, no publish.
 * - AFTER_FRAG: govern the staged request, resolve the fixture, publish one
 *   audit record (tkaudt) and one result (tkagnt), bump allowed/denied and
 *   processed, publish both CNC slots, then apply the event gate.  Both
 *   publications are made here, from the same commit, so a request is never
 *   audited without being answered or answered without being audited.
 * - AFTER_CREDIT: not defined — tkmodl has no fragment-independent work.
 * - SHOULD_SHUTDOWN: event_count exhaustion + CNC HALT.
 *
 * Output links are identified by their consumer tile (tkaudt / tkagnt), not
 * by declaration order.
 */

#define _GNU_SOURCE

#include "firedancer.h"
#include "audit_schema.h"
#include "tickoni/c_abi/shim/stem_helpers.h"
#include "tickoni/c_abi/topo_run/tk_model_stem.h"

#include "disco/topo/fd_topo.h"
#include "util/wksp/fd_wksp.h"
#include "util/fd_util.h"
#include "ballet/siphash13/fd_siphash13.h"

#include <string.h>
#include <stddef.h>

/* ─── Context ─── */
typedef struct {
    /* Counters */
    uint64_t processed;
    uint64_t allowed;
    uint64_t denied;

    /* Staging state (written in during_frag, committed in after_frag) */
    int      stage_valid;
    ModelRequestMsg staged_request;

    /* Output cursors, indexed by role: 0 = audit (tkaudt), 1 = result (tkagnt). */
    ulong    audit_out_idx;
    ulong    result_out_idx;
    void *   out_wksp[2];
    ulong    out_chunk0[2];
    ulong    out_wmark[2];
    ulong    out_chunk[2];

    /* CNC reference for shutdown detection */
    void *   cnc;

    /* Workspace pointer for input dcache reads */
    void *   wksp;

    /* Input dcache compact chunk bounds, workspace-relative. */
    ulong    in_chunk0;
    ulong    in_wmark;

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
static void tkmodl_run_entry( fd_topo_t * topo, fd_topo_tile_t * tile );

#define TKMODL_CTX_ALIGN alignof(tkmodl_ctx_t)

/* Two publications per commit (audit + result): the credit gate must reserve
   exactly that many slots per loop iteration. */
#define TKMODL_PUBLISH_PER_FRAG 2UL

/* Generate a model-specific static stem specialization. */
#define STEM_NAME                         tkmodl
#define STEM_BURST                        (TKMODL_PUBLISH_PER_FRAG)
#define STEM_LAZY                         ((long)10e6)
#define STEM_CALLBACK_CONTEXT_TYPE        tkmodl_ctx_t
#define STEM_CALLBACK_CONTEXT_ALIGN       TKMODL_CTX_ALIGN
#define STEM_CALLBACK_DURING_FRAG         tkmodl_during_frag
#define STEM_CALLBACK_AFTER_FRAG          tkmodl_after_frag
#define STEM_CALLBACK_SHOULD_SHUTDOWN(ctx) \
  ( (ctx)->input_exhausted || \
    ( (ctx)->cnc && fd_cnc_signal_query( (fd_cnc_t *)(ctx)->cnc ) == FD_CNC_SIGNAL_HALT ) )

#include "disco/stem/fd_stem.c"

#undef STEM_NAME
#undef STEM_CALLBACK_CONTEXT_TYPE
#undef STEM_CALLBACK_CONTEXT_ALIGN
#undef STEM_CALLBACK_DURING_FRAG
#undef STEM_CALLBACK_AFTER_FRAG
#undef STEM_CALLBACK_SHOULD_SHUTDOWN

/* ─── Scratch footprint and alignment ─── */

static ulong
tkmodl_scratch_align_tile( void ) {
    return TKMODL_CTX_ALIGN;
}

static ulong
tkmodl_scratch_footprint_tile( fd_topo_tile_t const * tile ) {
    (void)tile;
    /* Fixed: the context embeds the staged request and the bounded
       configuration, so the footprint depends on neither event count nor the
       configured limits or fixtures. */
    return fd_ulong_align_up( sizeof(tkmodl_ctx_t), TKMODL_CTX_ALIGN );
}

/* ─── Behavior configuration ─── */

static uint64_t            tkmodl_event_count_param;
static TkModlRuntimeConfig tkmodl_config_param;
static int                 tkmodl_config_configured;

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
    if( cfg->fixture_count > TKMODL_FIXTURE_CAP )       return TKMODL_CFG_FIXTURE_BOUND;
    tkmodl_config_param      = *cfg;
    tkmodl_config_configured = 1;
    return TKMODL_CFG_OK;
}

/* ─── Pure helpers ─── */

/* A fixed-width string field is well formed if it is NUL terminated inside
   the field (so a value is at most len-1 bytes). */
static int
tkmodl_field_terminated( uint8_t const * field, ulong len ) {
    return field[len-1UL] == 0;
}

int
tkmodl_request_well_formed( ModelRequestMsg const * req ) {
    if( req->version != TKMODL_WIRE_VERSION )                         return 0;
    if( req->replay_mode != TKMODL_REPLAY_MODE_LIVE &&
        req->replay_mode != TKMODL_REPLAY_MODE_REPLAY )               return 0;
    if( !tkmodl_field_terminated( req->model_id,               TKMODL_MODEL_ID_LEN ) )       return 0;
    if( !tkmodl_field_terminated( req->actor_role,             TKMODL_ROLE_LEN ) )           return 0;
    if( !tkmodl_field_terminated( req->workflow,               TKMODL_WORKFLOW_LEN ) )       return 0;
    if( !tkmodl_field_terminated( req->capability,             TKMODL_CAPABILITY_LEN ) )     return 0;
    if( !tkmodl_field_terminated( req->capability_envelope_id, TKMODL_ENVELOPE_LEN ) )       return 0;
    if( !tkmodl_field_terminated( req->policy_version,         TKMODL_POLICY_VERSION_LEN ) ) return 0;
    if( !tkmodl_field_terminated( req->budget_id,              TKMODL_BUDGET_LEN ) )         return 0;
    return 1;
}

static void
tkmodl_set_scope_dim( uint8_t * out, char const * name ) {
    if( !out ) return;
    memset( out, 0, TKMODL_SCOPE_DIM_LEN );
    ulong n = strlen( name );
    if( n >= TKMODL_SCOPE_DIM_LEN ) n = TKMODL_SCOPE_DIM_LEN - 1UL;
    memcpy( out, name, n );
}

/* Mirrors validator.zig:validateTkModlRequest branch order exactly. */
uint8_t
tkmodl_validate( TkModlRuntimeConfig const * cfg,
                 ModelRequestMsg const *     req,
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
    if( cfg->allowed_model_count > 0 ) {
        int allowed = 0;
        for( ulong i=0UL; i<cfg->allowed_model_count; i++ ) {
            if( memcmp( req->model_id, cfg->allowed_model_ids[i], TKMODL_MODEL_ID_LEN )==0 ) { allowed = 1; break; }
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

    /* Live provider must be explicitly enabled for live-mode requests. */
    if( req->replay_mode == TKMODL_REPLAY_MODE_LIVE && !cfg->live_provider_enabled )
        return MODEL_DENY_LIVE_PROVIDER_DISABLED;

    /* Replay mode requires a non-zero substitution id. */
    if( req->replay_mode == TKMODL_REPLAY_MODE_REPLAY && req->replay_substitution_id == 0 )
        return MODEL_DENY_REPLAY_SUBSTITUTION_MISSING;

    return req->replay_mode == TKMODL_REPLAY_MODE_REPLAY ? MODEL_ALLOW_REPLAY : MODEL_ALLOW_LIVE;
}

/* Captured result for a replay request: the fixture whose key matches the
   request's substitution id AND whose captured prompt hash and model agree
   with the request.  A missing or mismatched capture is not substitutable. */
static TkModlFixtureEntry const *
tkmodl_find_fixture( TkModlRuntimeConfig const * cfg, ModelRequestMsg const * req ) {
    for( ulong i=0UL; i<cfg->fixture_count; i++ ) {
        TkModlFixtureEntry const * f = &cfg->fixtures[i];
        if( f->key == 0 || f->key != req->replay_substitution_id ) continue;
        if( f->prompt_hash != req->prompt_hash ) return NULL;
        if( memcmp( f->model_id, req->model_id, TKMODL_MODEL_ID_LEN ) != 0 ) return NULL;
        return f;
    }
    return NULL;
}

/* Stable 64-bit digest of the capability envelope id, carried in the audit
   header so every model record is bound to the envelope it ran under. */
static uint64_t
tkmodl_envelope_hash( uint8_t const * envelope_id ) {
    fd_siphash13_t sip[1];
    fd_siphash13_init( sip, AUDIT_HASH_K0, AUDIT_HASH_K1 );
    fd_siphash13_append( sip, envelope_id, strlen( (char const *)envelope_id ) );
    return fd_siphash13_fini( sip );
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
    ctx->wksp        = stk_derive_wksp( topo, tile, 0 );

    FD_LOG_NOTICE(( "tkmodl: privileged init ctx=%p wksp=%p fixtures=%u allowed_models=%u",
                    (void *)ctx, ctx->wksp,
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
    if( FD_UNLIKELY( !ctx->wksp ) )
        FD_LOG_ERR(( "tkmodl: input workspace is not joined" ));

    fd_topo_link_t const * in_link = &topo->links[tile->in_link_id[0]];
    if( FD_UNLIKELY( !in_link->dcache || in_link->mtu < sizeof(ModelRequestMsg) ) )
        FD_LOG_ERR(( "tkmodl: invalid input dcache or mtu %lu (need %lu)",
                     in_link->mtu, (ulong)sizeof(ModelRequestMsg) ));
    ctx->in_chunk0 = fd_dcache_compact_chunk0( ctx->wksp, in_link->dcache );
    ctx->in_wmark  = fd_dcache_compact_wmark( ctx->wksp, in_link->dcache, in_link->mtu );

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

    ulong const need[2] = { sizeof(ModelAuditMsg), sizeof(ModelResultMsg) };
    ulong const outs[2] = { audit_idx, result_idx };
    for( ulong r=0UL; r<2UL; r++ ) {
        fd_topo_link_t const * out_link = &topo->links[tile->out_link_id[outs[r]]];
        if( FD_UNLIKELY( !out_link->dcache || out_link->mtu < need[r] ) )
            FD_LOG_ERR(( "tkmodl: invalid output dcache or mtu %lu (need %lu)", out_link->mtu, need[r] ));
        ctx->out_wksp[r] = fd_topo_obj_wksp_base( topo, out_link->dcache_obj_id );
        if( FD_UNLIKELY( !ctx->out_wksp[r] ) )
            FD_LOG_ERR(( "tkmodl: output workspace is not joined" ));
        ctx->out_chunk0[r] = fd_dcache_compact_chunk0( ctx->out_wksp[r], out_link->dcache );
        ctx->out_wmark[r]  = fd_dcache_compact_wmark( ctx->out_wksp[r], out_link->dcache, out_link->mtu );
        ctx->out_chunk[r]  = ctx->out_chunk0[r];
    }

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
    (void)in_idx; (void)seq; (void)sig; (void)ctl;

    ctx->stage_valid = 0;

    if( !stk_validate_frag( sz, sizeof(ModelRequestMsg), ctx->wksp ) )
        return;

    /* Chunk bounds: [in_chunk0, in_wmark], workspace-relative. */
    if( FD_UNLIKELY( chunk < ctx->in_chunk0 || chunk > ctx->in_wmark ) )
        return;

    /* Copy first, then judge the copy: the producer may overrun while we
       read, and fd_stem discards the fragment in that case. */
    memcpy( &ctx->staged_request, stk_chunk_to_gaddr( ctx->wksp, chunk ), sizeof(ModelRequestMsg) );
    if( !tkmodl_request_well_formed( &ctx->staged_request ) )
        return;

    ctx->stage_valid = 1;
}

static void
tkmodl_publish( tkmodl_ctx_t *       ctx,
                fd_stem_context_t *  stem,
                ulong                role,    /* 0 audit, 1 result */
                ulong                out_idx,
                ulong                sig,
                void const *         msg,
                ulong                sz ) {
    ulong chunk = ctx->out_chunk[role];
    memcpy( fd_chunk_to_laddr( ctx->out_wksp[role], chunk ), msg, sz );
    /* (stem, out_idx, sig, chunk, sz, ctl, tsorig, tspub) */
    fd_stem_publish( stem, out_idx, sig, chunk, sz, 0UL, 0UL, 0UL );
    ctx->out_chunk[role] = fd_dcache_compact_next( chunk, sz, ctx->out_chunk0[role], ctx->out_wmark[role] );
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

    ModelRequestMsg const * req = &ctx->staged_request;

    uint8_t scope_dim[TKMODL_SCOPE_DIM_LEN];
    uint8_t decision = tkmodl_validate( &ctx->config, req, scope_dim );

    TkModlFixtureEntry const * fixture = NULL;
    if( decision == MODEL_ALLOW_REPLAY ) {
        fixture = tkmodl_find_fixture( &ctx->config, req );
        if( !fixture ) decision = MODEL_DENY_REPLAY_SUBSTITUTION_MISSING;
    } else if( decision == MODEL_ALLOW_LIVE ) {
        /* Unreachable (the configuration rejects a live provider), but never
           serve a live request from a fixture/replay tile. */
        decision = MODEL_DENY_LIVE_PROVIDER_DISABLED;
    }
    int const allowed = ( decision == MODEL_ALLOW_REPLAY );

    /* Result for the requester. */
    ModelResultMsg result;
    memset( &result, 0, sizeof(result) );
    result.version                = TKMODL_WIRE_VERSION;
    result.decision               = decision;
    result.request_id             = req->request_id;
    result.run_id                 = req->run_id;
    result.prompt_hash            = req->prompt_hash;
    result.replay_substitution_id = req->replay_substitution_id;
    memcpy( result.model_id, req->model_id, sizeof(result.model_id) );
    memcpy( result.failed_scope_dim, scope_dim, sizeof(result.failed_scope_dim) );
    if( allowed ) {
        result.response_hash     = fixture->response_hash;
        result.prompt_tokens     = fixture->prompt_tokens;
        result.completion_tokens = fixture->completion_tokens;
        result.total_tokens      = fixture->total_tokens;
        result.latency_ms        = fixture->latency_ms;
    }

    /* Audit record: a model_call for an allowed request, a denial otherwise. */
    ModelAuditMsg audit;
    memset( &audit, 0, sizeof(audit) );
    audit.version                  = TKMODL_WIRE_VERSION;
    audit.run_id                   = req->run_id;
    audit.request_id               = req->request_id;
    audit.capability_envelope_hash = tkmodl_envelope_hash( req->capability_envelope_id );
    memcpy( audit.policy_version, req->policy_version, sizeof(audit.policy_version) );
    if( allowed ) {
        audit.record_type = RECORD_MODEL_CALL;
        WireModelCallPayload * p = &audit.payload.model_call;
        memcpy( p->model_id, req->model_id, sizeof(p->model_id) );
        p->prompt_hash            = req->prompt_hash;
        p->response_hash          = fixture->response_hash;
        p->token_estimate         = fixture->total_tokens;
        p->retry_count            = 0;
        memcpy( p->actor_role, req->actor_role, sizeof(p->actor_role) );
        memcpy( p->workflow, req->workflow, sizeof(p->workflow) );
        p->policy_decision_id     = req->policy_decision_id;
        p->replay_substitution_id = req->replay_substitution_id;
    } else {
        audit.record_type = RECORD_DENIAL;
        WireDenialPayload * p = &audit.payload.denial;
        memcpy( p->action_class, req->capability, sizeof(p->action_class) );
        p->reason_code = decision;
        memcpy( p->failed_scope_dim, scope_dim, sizeof(p->failed_scope_dim) );
    }

    tkmodl_publish( ctx, stem, 0UL, ctx->audit_out_idx,  (ulong)audit.record_type, &audit,  sizeof(audit) );
    tkmodl_publish( ctx, stem, 1UL, ctx->result_out_idx, TK_LINK_SIG_PAYMENT,      &result, sizeof(result) );

    ctx->processed += 1;
    if( allowed ) ctx->allowed += 1; else ctx->denied += 1;

    /* CNC slot schema from tile_registry.zig: app[0]=allowed, app[1]=denied. */
    stk_publish_counter( ctx->cnc, 0UL, ctx->allowed );
    stk_publish_counter( ctx->cnc, 1UL, ctx->denied );

    /* Gate on processed: allowed and denied both count toward completion. */
    STK_EVENT_EXHAUSTED( ctx, ctx->event_count, ctx->processed );
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
