/* test_tkagnt_correlation.c — admission, correlation and failure handling of
   the tkagnt agent worker.

   Compiles the real tile source into the test and drives the real static
   tkagnt_before_frag / tkagnt_during_frag / tkagnt_after_frag with whole
   agent-request fragments and with multipart result streams built by the real
   sender.  Everything the tile decides in those
   callbacks mutates state only (publication is AFTER_CREDIT), so no live stem
   is needed.  The Zig decision hooks are replaced by two C stubs that obey the
   same contract (tk_agent_hooks.h).

   Proves:
   1. A whole agent request is admitted as the next ordinal: the model request
      staged for it is the scope with request_id == ordinal, no declared prompt
      hash, and the bytes of the prompt its reference names, from the prompt
      table.  The run keeps the request's trace id.
   2. A request naming an absent tier, a prompt the table does not hold, a
      malformed request, and a router verdict outside the contract each end in
      a resolved run with the right outcome and no model record to wait for;
      none stages a request.
   3. A request fragment of the wrong size, or not a whole message, admits
      nothing and is counted.
   4. New requests are held back (before_frag == -1) exactly while there is no
      free slot or run entry.
   5. A result completes the one pending dispatch on its instance and no other:
      an unknown, duplicate, stale, wrong-instance or wrong-model result is
      counted and ignored and cannot complete a run.
   6. The hashes in a result must match the bytes that arrived: a corrupt
      response or a prompt hash that is not the agent's own fails the run.
   7. A denied model result carries no content; one that does is a transport
      failure.  A malformed directive from the interpreter fails closed.
   8. A result stream that fails reassembly ends the run it answered.
*/

#define _GNU_SOURCE

#include "../../c_abi/shim/tk_agent_stem.c"

#include <stdio.h>

#define CHUNK_BYTES ((ulong)FD_CHUNK_ALIGN)

static int g_failed = 0;
#define CHECK(cond, msg) do { if( !(cond) ) { fprintf( stderr, "FAIL: %s (%s:%d)\n", msg, __FILE__, __LINE__ ); g_failed = 1; } } while(0)

/* ─── Hook stubs obeying tk_agent_hooks.h ─── */

static int g_bad_directive;        /* make interpret return a malformed directive */

static TkAgentRouteDirective
stub_route( TkAgentRouteQuery const * q ) {
    TkAgentRouteDirective d; memset( &d, 0, sizeof(d) );
    d.verdict = TK_AGENT_ROUTE_DENY_INVALID; d.tier = TK_AGENT_TIER_NONE;
    if( q->request_type!=TK_AGENT_REQ_CHAT && q->request_type!=TK_AGENT_REQ_EMBEDDING ) return d;
    if( q->requested_tier>=TK_AGENT_TIER_COUNT ) return d;
    d.tier = q->requested_tier;
    d.verdict = ((q->configured_mask>>q->requested_tier)&1U) ? TK_AGENT_ROUTE_DISPATCH : TK_AGENT_ROUTE_DENY_ABSENT_TIER;
    if( g_bad_directive==2 ) { d.verdict = TK_AGENT_ROUTE_DISPATCH; d.tier = 10; }   /* a tier that is not configured */
    if( g_bad_directive==3 ) { d.verdict = 99; }                                      /* an unknown verdict */
    return d;
}

static TkAgentInterpretDirective
stub_interpret( TkAgentInterpretQuery const * q ) {
    TkAgentInterpretDirective d; memset( &d, 0, sizeof(d) );
    d.recommended_tier = TK_AGENT_TIER_NONE;
    if( q->model_decision!=MODEL_ALLOW_REPLAY && q->model_decision!=MODEL_ALLOW_LIVE ) {
        d.action = TK_AGENT_ACT_FAIL; d.why = TK_AGENT_WHY_MODEL_DENIED; return d;
    }
    d.action = TK_AGENT_ACT_FINAL;
    if( g_bad_directive==1 ) d.confidence = 77;     /* outside TK_AGENT_CONF_* */
    return d;
}

/* ─── Fixture: a context bound to tiers low (6) and medium (7) ─── */

#define TIER_LOW    6
#define TIER_MEDIUM 7

static uint8_t g_rx[ TKAGNT_MAX_INS * TK_MP_MAX_MESSAGE_BYTES ];
static uint8_t g_slots[ TKAGNT_SLOTS * TK_MP_MAX_MESSAGE_BYTES ];
static uint8_t g_msg[ TK_MP_MAX_MESSAGE_BYTES ];
static tkagnt_ctx_t g_ctx;

static void
ctx_init( tkagnt_ctx_t * ctx ) {
    memset( ctx, 0, sizeof(*ctx) );
    ctx->hooks.route     = stub_route;
    ctx->hooks.interpret = stub_interpret;
    ctx->rxbuf   = g_rx;
    ctx->slotbuf = g_slots;
    ctx->audit_seq = 1UL;
    ctx->term_seq  = 1UL;
    ctx->in_cnt  = 3UL;           /* request, result[low], result[medium] */
    ctx->out_cnt = 4UL;
    ctx->req_in  = 0UL;
    for( ulong t=0UL; t<TKAGNT_TIERS; t++ ) { ctx->model_in[t] = ULONG_MAX; ctx->model_out[t] = ULONG_MAX; }
    ctx->model_in [TIER_LOW]    = 1UL; ctx->model_out[TIER_LOW]    = 0UL;
    ctx->model_in [TIER_MEDIUM] = 2UL; ctx->model_out[TIER_MEDIUM] = 1UL;
    ctx->configured_mask = (uint16_t)((1U<<TIER_LOW)|(1U<<TIER_MEDIUM));
    for( ulong i=0UL; i<TKAGNT_MAX_INS; i++ ) ctx->in_tier[i] = -1;
    ctx->in_tier[1] = TIER_LOW; ctx->in_tier[2] = TIER_MEDIUM;
    tk_mp_rx_init( &ctx->rx[1], TK_MP_DIR_RESULT,  g_rx + 1UL*TK_MP_MAX_MESSAGE_BYTES, TKAGNT_PARTIAL_TIMEOUT_NS );
    tk_mp_rx_init( &ctx->rx[2], TK_MP_DIR_RESULT,  g_rx + 2UL*TK_MP_MAX_MESSAGE_BYTES, TKAGNT_PARTIAL_TIMEOUT_NS );
    g_bad_directive = 0;
}

/* Feeds one fragment to the tile the way fd_stem would: staged by DURING_FRAG's
   result, committed by AFTER_FRAG.  The stage is set directly, since the dcache
   is not under test here. */
static void
deliver( tkagnt_ctx_t * ctx, ulong in_idx, uint8_t const * frag, ulong sz, int som, int eom ) {
    memcpy( ctx->stage, frag, sz );
    ctx->stage_is_req = 0;
    ctx->stage_in = in_idx; ctx->stage_sz = sz; ctx->stage_som = som; ctx->stage_eom = eom;
    ctx->stage_valid = 1;
    tkagnt_after_frag( ctx, in_idx, 0UL, 0UL, sz, 0UL, 0UL, NULL );
}

/* Sends a whole logical message as the sender would, optionally skipping the
   fragment index `skip` (or corrupting `corrupt`'s payload) to build a bad stream. */
static void
send_message( tkagnt_ctx_t * ctx, ulong in_idx, uint8_t dir, uint8_t ct, uint64_t run_id, uint64_t req_id,
              uint8_t const * msg, ulong len, long skip, long corrupt ) {
    tk_mp_tx_t tx;
    CHECK( tk_mp_tx_begin( &tx, dir, ct, run_id, req_id, msg, len )==0, "begin" );
    uint8_t frag[ TK_MP_LINK_MTU ]; int som, eom; long idx = 0;
    while( !tk_mp_tx_done( &tx ) ) {
        ulong sz = tk_mp_tx_frag( &tx, frag, &som, &eom );
        if( idx!=skip ) {
            if( idx==corrupt ) frag[ TK_MP_HDR_SZ+1 ] ^= 0x5a;
            deliver( ctx, in_idx, frag, sz, som, eom );
        }
        idx++;
    }
}

/* Deterministic prompt bytes of `len`. */
static void
fill_prompt( uint8_t * out, ulong len ) {
    for( ulong i=0UL; i<len; i++ ) out[i] = (uint8_t)(i*7UL+3UL);
}

/* Installs the prompt of `len` in the tile's table (once per length). */
static void
install_prompt( ulong len ) {
    fill_prompt( g_msg, len );
    int rc = tkagnt_set_prompt( tk_mp_message_hash( g_msg, len ), g_msg, len );
    CHECK( rc==0 || rc==4, "the prompt is installed" );
}

/* One agent request whose reference names the prompt of `prompt_len`. */
static TkAgentRequestMsg
build_request( uint64_t run_id, uint8_t request_type, uint8_t tier, ulong prompt_len ) {
    TkAgentRequestMsg h; memset( &h, 0, sizeof(h) );
    h.version = TK_AGENT_WIRE_VERSION; h.request_type = request_type; h.requested_tier = tier;
    fill_prompt( g_msg, prompt_len );
    h.prompt_ref.prompt_hash = tk_mp_message_hash( g_msg, prompt_len );
    h.prompt_ref.prompt_len  = (uint32_t)prompt_len;
    h.scope.version = TKMODL_WIRE_VERSION; h.scope.replay_mode = TKMODL_REPLAY_MODE_REPLAY;
    h.scope.run_id = run_id; h.scope.trace_id = 1000UL + run_id; h.scope.replay_substitution_id = 1000UL;
    h.scope.timeout_ms = 5000U;
    strcpy( (char *)h.scope.model_id, "fixture.model" );
    strcpy( (char *)h.scope.actor_role, "ops_reviewer" );
    strcpy( (char *)h.scope.workflow, "trading_control" );
    strcpy( (char *)h.scope.capability, "trading_order.propose" );
    strcpy( (char *)h.scope.capability_envelope_id, "capenv.fixture" );
    strcpy( (char *)h.scope.policy_version, "v1" );
    strcpy( (char *)h.scope.budget_id, "budget.fixture" );
    return h;
}

/* Feeds one whole request to the tile the way fd_stem would. */
static void
deliver_request( tkagnt_ctx_t * ctx, TkAgentRequestMsg const * req ) {
    ctx->stage_req    = *req;
    ctx->stage_is_req = 1;
    ctx->stage_in     = ctx->req_in;
    ctx->stage_sz     = sizeof(*req);
    ctx->stage_valid  = 1;
    tkagnt_after_frag( ctx, ctx->req_in, 0UL, 0UL, sizeof(*req), 0UL, 0UL, NULL );
}

static void
admit( tkagnt_ctx_t * ctx, uint64_t run_id, uint8_t tier, ulong prompt_len ) {
    install_prompt( prompt_len );
    TkAgentRequestMsg req = build_request( run_id, TK_AGENT_REQ_CHAT, tier, prompt_len );
    deliver_request( ctx, &req );
}

/* Result body: ModelResultMsg + content. */
static ulong
build_result( uint8_t * out, tkagnt_run_t const * r, uint8_t decision, uint8_t const * content, ulong clen ) {
    ModelResultMsg m; memset( &m, 0, sizeof(m) );
    m.version = TKMODL_WIRE_VERSION; m.decision = decision;
    m.request_id = r->agent_seq; m.run_id = r->run_id; m.prompt_hash = r->prompt_hash;
    m.total_tokens = 42U;
    memcpy( m.model_id, r->model_id, sizeof(m.model_id) );
    if( decision==MODEL_ALLOW_REPLAY && clen ) m.response_hash = tk_mp_message_hash( content, clen );
    memcpy( out, &m, sizeof(m) );
    if( clen ) memcpy( out+sizeof(m), content, clen );
    return sizeof(m)+clen;
}

/* Moves an admitted run to AWAIT, as dispatch would. */
static void
mark_dispatched( tkagnt_ctx_t * ctx, uint64_t seq ) {
    tkagnt_run_t * r = tkagnt_run_at( ctx, seq );
    if( r->slot>=0 ) { ctx->slots[r->slot].used = 0; r->slot = -1; }
    r->state = RUN_AWAIT;
    ctx->inst_busy[r->tier] = 1;
}

static void
send_result( tkagnt_ctx_t * ctx, ulong tier, tkagnt_run_t const * r, uint8_t decision,
             uint8_t const * content, ulong clen, long skip, long corrupt ) {
    ulong len = build_result( g_msg, r, decision, content, clen );
    ulong in_idx = ctx->model_in[tier];
    send_message( ctx, in_idx, TK_MP_DIR_RESULT, TK_MP_CT_CHAT, r->run_id, r->agent_seq, g_msg, len, skip, corrupt );
}

static uint8_t g_content[ 3UL*TK_MP_FRAG_PAYLOAD_MAX+77UL ];

static void
test_admission_stages_the_model_request( void ) {
    tkagnt_ctx_t * ctx = &g_ctx; ctx_init( ctx );
    ulong prompt_len = 3UL*TK_MP_FRAG_PAYLOAD_MAX + 5UL;     /* a model request spanning four fragments */
    admit( ctx, 11UL, TIER_LOW, prompt_len );

    CHECK( ctx->admitted==1UL, "the request is admitted as ordinal 1" );
    tkagnt_run_t * r = tkagnt_run_at( ctx, 1UL );
    CHECK( r->state==RUN_ADMITTED && r->tier==TIER_LOW && r->agent_seq==1UL && r->run_id==11UL, "run state and identity" );
    CHECK( r->trace_id==1011UL, "the run keeps the request's trace id" );
    CHECK( r->slot==0 && ctx->slots[0].used && ctx->slots[0].len==sizeof(ModelRequestMsg)+prompt_len, "a slot holds the model request" );

    ModelRequestMsg scope; memcpy( &scope, g_slots, sizeof(scope) );
    CHECK( scope.request_id==1UL, "request_id is the admission ordinal" );
    CHECK( scope.prompt_hash==0UL, "no declared prompt hash is passed on" );
    CHECK( scope.run_id==11UL && scope.trace_id==1011UL && scope.replay_substitution_id==1000UL, "scope is carried through" );
    int prompt_ok = 1;
    for( ulong i=0UL; i<prompt_len; i++ ) if( g_slots[sizeof(scope)+i]!=(uint8_t)(i*7UL+3UL) ) { prompt_ok = 0; break; }
    CHECK( prompt_ok, "the prompt bytes come verbatim from the prompt table" );
    CHECK( r->prompt_hash==tk_mp_message_hash( g_slots+sizeof(scope), prompt_len ), "the run's prompt hash is that of the bytes sent" );
    CHECK( ctx->transport_dropped==0UL, "nothing dropped" );
}

static void
test_denials_resolve_without_a_model_record( void ) {
    tkagnt_ctx_t * ctx = &g_ctx; ctx_init( ctx );
    install_prompt( 10UL );

    admit( ctx, 1UL, 8 /* high: not configured */, 10UL );
    tkagnt_run_t * r = tkagnt_run_at( ctx, 1UL );
    CHECK( r->state==RUN_RESOLVED && r->outcome==TK_AGENT_OUT_DENY_ABSENT_TIER && r->has_model_record==0, "an absent tier is denied at routing" );
    CHECK( r->slot==-1 && !ctx->slots[0].used, "a denied request stages nothing" );

    /* A chat request that names no tier. */
    TkAgentRequestMsg req = build_request( 2UL, TK_AGENT_REQ_CHAT, TK_AGENT_TIER_NONE, 10UL );
    deliver_request( ctx, &req );
    r = tkagnt_run_at( ctx, 2UL );
    CHECK( r->state==RUN_RESOLVED && r->outcome==TK_AGENT_OUT_DENY_INVALID_REQUEST, "an unnamed tier is an invalid request" );

    /* Unterminated string field in the scope. */
    req = build_request( 3UL, TK_AGENT_REQ_CHAT, TIER_LOW, 10UL );
    memset( req.scope.budget_id, 'x', TKMODL_BUDGET_LEN );
    deliver_request( ctx, &req );
    CHECK( tkagnt_run_at( ctx, 3UL )->outcome==TK_AGENT_OUT_DENY_INVALID_REQUEST, "a malformed scope is an invalid request" );

    /* A prompt reference the table does not hold: by hash, and by length. */
    req = build_request( 4UL, TK_AGENT_REQ_CHAT, TIER_LOW, 10UL );
    req.prompt_ref.prompt_hash ^= 1UL;
    deliver_request( ctx, &req );
    r = tkagnt_run_at( ctx, 4UL );
    CHECK( r->outcome==TK_AGENT_OUT_DENY_INVALID_REQUEST && r->slot==-1, "an unknown prompt hash is an invalid request" );
    CHECK( strcmp( (char const *)r->failed_scope_dim, "prompt_ref" )==0, "the denial names the prompt reference" );
    req = build_request( 5UL, TK_AGENT_REQ_CHAT, TIER_LOW, 10UL );
    req.prompt_ref.prompt_len = 11U;
    deliver_request( ctx, &req );
    CHECK( tkagnt_run_at( ctx, 5UL )->outcome==TK_AGENT_OUT_DENY_INVALID_REQUEST, "a known hash with the wrong length is an invalid request" );

    /* A request of another agent wire version. */
    req = build_request( 6UL, TK_AGENT_REQ_CHAT, TIER_LOW, 10UL );
    req.version = (uint16_t)(TK_AGENT_WIRE_VERSION+1);
    deliver_request( ctx, &req );
    CHECK( tkagnt_run_at( ctx, 6UL )->outcome==TK_AGENT_OUT_DENY_INVALID_REQUEST, "another wire version is an invalid request" );

    CHECK( ctx->admitted==6UL, "every accepted request got an ordinal" );
    for( uint64_t s=1UL; s<=6UL; s++ ) CHECK( tkagnt_run_at( ctx, s )->has_model_record==0, "none expects a model record" );
    CHECK( !ctx->slots[0].used, "and none holds a slot" );
}

static void
test_router_verdicts_outside_the_contract_fail_closed( void ) {
    tkagnt_ctx_t * ctx = &g_ctx;
    for( int mode=2; mode<=3; mode++ ) {
        ctx_init( ctx );
        g_bad_directive = mode;
        admit( ctx, 1UL, TIER_LOW, 10UL );
        tkagnt_run_t * r = tkagnt_run_at( ctx, 1UL );
        CHECK( r->state==RUN_RESOLVED && r->outcome==TK_AGENT_OUT_DENY_INVALID_REQUEST, "a directive for an unconfigured tier or unknown verdict fails closed" );
        CHECK( r->slot==-1, "and stages nothing" );
    }
}

/* ─── DURING_FRAG ───

   A plain buffer stands in for the shared workspace: chunk c is at byte c*64. */
static uint8_t g_wksp[ 400UL*64UL ] __attribute__((aligned(64)));
#define IN_CHUNK0 2UL
#define IN_WMARK  200UL

static void
wksp_init( tkagnt_ctx_t * ctx ) {
    memset( g_wksp, 0, sizeof(g_wksp) );
    ctx->wksp = g_wksp;
    for( ulong i=0UL; i<ctx->in_cnt; i++ ) { ctx->in_chunk0[i] = IN_CHUNK0; ctx->in_wmark[i] = IN_WMARK; }
}

static void
test_a_malformed_request_fragment_admits_nothing( void ) {
    tkagnt_ctx_t * ctx = &g_ctx; ctx_init( ctx ); wksp_init( ctx );
    install_prompt( 10UL );
    TkAgentRequestMsg req = build_request( 1UL, TK_AGENT_REQ_CHAT, TIER_LOW, 10UL );
    memcpy( g_wksp + IN_CHUNK0*CHUNK_BYTES, &req, sizeof(req) );
    ulong whole = fd_frag_meta_ctl( 0UL, 1, 1, 0 );

    struct { char const * name; ulong sz; ulong ctl; } bad[] = {
        { "one byte short",         sizeof(req)-1UL, whole },
        { "one byte long",          sizeof(req)+1UL, whole },
        { "not the end of message", sizeof(req),     fd_frag_meta_ctl( 0UL, 1, 0, 0 ) },
        { "not the start",          sizeof(req),     fd_frag_meta_ctl( 0UL, 0, 1, 0 ) },
    };
    for( ulong i=0UL; i<sizeof(bad)/sizeof(bad[0]); i++ ) {
        tkagnt_during_frag( ctx, 0UL, 0UL, TK_LINK_SIG_AGENT_REQUEST, IN_CHUNK0, bad[i].sz, bad[i].ctl );
        tkagnt_after_frag( ctx, 0UL, 0UL, 0UL, 0UL, 0UL, 0UL, NULL );
        if( ctx->admitted!=0UL ) fprintf( stderr, "case failed: %s\n", bad[i].name );
        CHECK( ctx->admitted==0UL && ctx->transport_dropped==i+1UL, "a malformed request fragment admits nothing and is counted" );
    }
    /* A whole request afterwards is admitted. */
    tkagnt_during_frag( ctx, 0UL, 0UL, TK_LINK_SIG_AGENT_REQUEST, IN_CHUNK0, sizeof(req), whole );
    tkagnt_after_frag( ctx, 0UL, 0UL, 0UL, 0UL, 0UL, 0UL, NULL );
    CHECK( ctx->admitted==1UL && tkagnt_run_at( ctx, 1UL )->state==RUN_ADMITTED, "the next whole request is admitted" );
}

static void
test_new_requests_are_held_back_when_there_is_no_room( void ) {
    tkagnt_ctx_t * ctx = &g_ctx; ctx_init( ctx );
    CHECK( tkagnt_before_frag( ctx, 0UL, 0UL, 0UL )==0, "room: a new request is taken" );
    for( ulong i=0UL; i<TKAGNT_SLOTS; i++ ) ctx->slots[i].used = 1;
    CHECK( tkagnt_before_frag( ctx, 0UL, 0UL, 0UL )==-1, "no free slot: a new request is held back" );
    CHECK( tkagnt_before_frag( ctx, 1UL, 0UL, 0UL )==0, "results are never held back" );
    ctx->slots[0].used = 0;
    CHECK( tkagnt_before_frag( ctx, 0UL, 0UL, 0UL )==0, "a slot frees room again" );
    ctx->admitted = TKAGNT_PENDING; ctx->terminal_done = 0UL;
    CHECK( tkagnt_before_frag( ctx, 0UL, 0UL, 0UL )==-1, "no run entry: a new request is held back" );
}

static tkagnt_run_t *
admitted_and_dispatched( tkagnt_ctx_t * ctx, uint64_t run_id, uint8_t tier ) {
    admit( ctx, run_id, tier, 50UL );
    uint64_t seq = ctx->admitted;
    mark_dispatched( ctx, seq );
    return tkagnt_run_at( ctx, seq );
}

static void
test_a_result_completes_only_the_pending_dispatch( void ) {
    tkagnt_ctx_t * ctx = &g_ctx; ctx_init( ctx );
    tkagnt_run_t * r = admitted_and_dispatched( ctx, 21UL, TIER_LOW );
    for( ulong i=0UL; i<sizeof(g_content); i++ ) g_content[i] = (uint8_t)(i*13UL);
    ulong clen = 2UL*TK_MP_FRAG_PAYLOAD_MAX + 9UL;       /* a multi-fragment response */

    /* Wrong instance: the right ids on the medium tier's link. */
    send_result( ctx, TIER_MEDIUM, r, MODEL_ALLOW_REPLAY, g_content, clen, -1, -1 );
    CHECK( ctx->mismatched==1UL && r->state==RUN_AWAIT, "a result from the wrong instance completes nothing" );

    /* Unknown request id. */
    tkagnt_run_t fake = *r; fake.agent_seq = 99UL;
    send_result( ctx, TIER_LOW, &fake, MODEL_ALLOW_REPLAY, g_content, clen, -1, -1 );
    CHECK( ctx->mismatched==2UL && r->state==RUN_AWAIT, "an unknown request id completes nothing" );

    /* Wrong model id. */
    fake = *r; memset( fake.model_id, 0, sizeof(fake.model_id) ); strcpy( (char *)fake.model_id, "other.model" );
    send_result( ctx, TIER_LOW, &fake, MODEL_ALLOW_REPLAY, g_content, clen, -1, -1 );
    CHECK( ctx->mismatched==3UL && r->state==RUN_AWAIT, "a result for the wrong model completes nothing" );

    /* The real result completes it, once. */
    send_result( ctx, TIER_LOW, r, MODEL_ALLOW_REPLAY, g_content, clen, -1, -1 );
    CHECK( r->state==RUN_RESOLVED && r->outcome==TK_AGENT_OUT_OK && r->has_model_record==1, "the matching result resolves the run" );
    CHECK( r->source_tier==TIER_LOW && r->response_len==clen && r->total_tokens==42U, "attributed to the instance that served it" );
    CHECK( r->response_hash==tk_mp_message_hash( g_content, clen ), "response hash is of the bytes that arrived" );
    CHECK( ctx->inst_busy[TIER_LOW]==0 && ctx->results==1UL, "the instance is free and the result counted" );

    /* A duplicate and a stale result are ignored. */
    send_result( ctx, TIER_LOW, r, MODEL_ALLOW_REPLAY, g_content, clen, -1, -1 );
    CHECK( ctx->mismatched==4UL && ctx->results==1UL && r->state==RUN_RESOLVED, "a duplicate result is ignored" );
}

static void
test_result_hashes_must_match_the_bytes( void ) {
    tkagnt_ctx_t * ctx = &g_ctx; ctx_init( ctx );
    for( ulong i=0UL; i<sizeof(g_content); i++ ) g_content[i] = (uint8_t)(i*3UL+1UL);
    ulong clen = 1000UL;

    /* The declared response hash does not match the bytes: build a result whose
       declared hash is for different content. */
    tkagnt_run_t * r = admitted_and_dispatched( ctx, 1UL, TIER_LOW );
    ulong len = build_result( g_msg, r, MODEL_ALLOW_REPLAY, g_content, clen );
    ModelResultMsg m; memcpy( &m, g_msg, sizeof(m) ); m.response_hash ^= 1UL; memcpy( g_msg, &m, sizeof(m) );
    send_message( ctx, 1UL, TK_MP_DIR_RESULT, TK_MP_CT_CHAT, r->run_id, r->agent_seq, g_msg, len, -1, -1 );
    CHECK( r->state==RUN_RESOLVED && r->outcome==TK_AGENT_OUT_TRANSPORT_FAILURE && r->has_model_record==1, "a response that does not hash to the declared hash is a transport failure" );

    /* A prompt hash that is not the agent's own. */
    r = admitted_and_dispatched( ctx, 2UL, TIER_LOW );
    len = build_result( g_msg, r, MODEL_ALLOW_REPLAY, g_content, clen );
    memcpy( &m, g_msg, sizeof(m) ); m.prompt_hash ^= 1UL; memcpy( g_msg, &m, sizeof(m) );
    send_message( ctx, 1UL, TK_MP_DIR_RESULT, TK_MP_CT_CHAT, r->run_id, r->agent_seq, g_msg, len, -1, -1 );
    CHECK( r->outcome==TK_AGENT_OUT_RESULT_MISMATCH, "a prompt hash that is not the agent's own fails the run" );

    /* An allowed result with no content. */
    r = admitted_and_dispatched( ctx, 3UL, TIER_LOW );
    send_result( ctx, TIER_LOW, r, MODEL_ALLOW_REPLAY, g_content, 0UL, -1, -1 );
    CHECK( r->outcome==TK_AGENT_OUT_TRANSPORT_FAILURE, "an allowed result must carry content" );
}

static void
test_denied_results_and_bad_directives( void ) {
    tkagnt_ctx_t * ctx = &g_ctx; ctx_init( ctx );
    for( ulong i=0UL; i<64UL; i++ ) g_content[i] = (uint8_t)i;

    tkagnt_run_t * r = admitted_and_dispatched( ctx, 1UL, TIER_LOW );
    send_result( ctx, TIER_LOW, r, MODEL_DENY_MODEL_NOT_ALLOWED, g_content, 0UL, -1, -1 );
    CHECK( r->state==RUN_RESOLVED && r->outcome==TK_AGENT_OUT_MODEL_DENIED && r->has_model_record==1 && r->response_len==0U,
           "a denied result is a terminal model denial with a model record and no content" );

    r = admitted_and_dispatched( ctx, 2UL, TIER_LOW );
    send_result( ctx, TIER_LOW, r, MODEL_DENY_MODEL_NOT_ALLOWED, g_content, 64UL, -1, -1 );
    CHECK( r->outcome==TK_AGENT_OUT_TRANSPORT_FAILURE, "a denied result that carries content is a transport failure" );

    g_bad_directive = 1;
    r = admitted_and_dispatched( ctx, 3UL, TIER_LOW );
    send_result( ctx, TIER_LOW, r, MODEL_ALLOW_REPLAY, g_content, 64UL, -1, -1 );
    CHECK( r->outcome==TK_AGENT_OUT_INVALID_CONTENT, "a malformed interpreter directive fails closed" );
}

static void
test_a_failed_result_stream_ends_the_run_it_answered( void ) {
    tkagnt_ctx_t * ctx = &g_ctx; ctx_init( ctx );
    for( ulong i=0UL; i<sizeof(g_content); i++ ) g_content[i] = (uint8_t)i;
    ulong clen = 2UL*TK_MP_FRAG_PAYLOAD_MAX;

    tkagnt_run_t * r = admitted_and_dispatched( ctx, 1UL, TIER_LOW );
    send_result( ctx, TIER_LOW, r, MODEL_ALLOW_REPLAY, g_content, clen, 1, -1 );   /* a fragment is lost */
    CHECK( r->state==RUN_RESOLVED && r->outcome==TK_AGENT_OUT_TRANSPORT_FAILURE && r->has_model_record==1, "a result stream with a gap ends its run in a transport failure" );
    CHECK( ctx->inst_busy[TIER_LOW]==0 && ctx->results==0UL, "the instance is free and no result was counted" );

    r = admitted_and_dispatched( ctx, 2UL, TIER_LOW );
    send_result( ctx, TIER_LOW, r, MODEL_ALLOW_REPLAY, g_content, clen, -1, 0 );   /* corrupt payload */
    CHECK( r->outcome==TK_AGENT_OUT_TRANSPORT_FAILURE, "a corrupt result stream ends its run in a transport failure" );

    /* A failed stream for a message no run is waiting on is only counted. */
    uint64_t before = ctx->transport_dropped;
    tkagnt_run_t ghost; memset( &ghost, 0, sizeof(ghost) ); ghost.agent_seq = 77UL; ghost.run_id = 77UL;
    send_result( ctx, TIER_LOW, &ghost, MODEL_ALLOW_REPLAY, g_content, clen, 1, -1 );
    CHECK( ctx->transport_dropped>before, "a stray failed stream is counted" );
    CHECK( tkagnt_run_at( ctx, 2UL )->outcome==TK_AGENT_OUT_TRANSPORT_FAILURE, "and does not touch other runs" );
}

static void
test_during_frag_stages_only_what_the_link_may_carry( void ) {
    tkagnt_ctx_t * ctx = &g_ctx; ctx_init( ctx ); wksp_init( ctx );
    TkAgentRequestMsg req = build_request( 7UL, TK_AGENT_REQ_CHAT, TIER_LOW, 10UL );
    memcpy( g_wksp + IN_CHUNK0*CHUNK_BYTES, &req, sizeof(req) );
    ulong sz    = sizeof(req);
    ulong whole = fd_frag_meta_ctl( 0UL, 1, 1, 0 );

    tkagnt_during_frag( ctx, 0UL, 0UL, TK_LINK_SIG_AGENT_REQUEST, IN_CHUNK0, sz, whole );
    CHECK( ctx->stage_valid==1 && ctx->stage_is_req==1 && ctx->stage_in==0UL && ctx->stage_sz==sz, "a whole request is staged" );
    CHECK( ctx->stage_req.scope.run_id==7UL, "the staged request is a copy of the fragment" );
    CHECK( ctx->admitted==0UL, "staging changes nothing else" );

    /* The abandoned-fragment case: fd_stem skips AFTER_FRAG when the producer
       overran the reader, so a stale stage must not survive into the next
       AFTER_FRAG.  Any invalid next fragment clears it first. */
    tkagnt_during_frag( ctx, 0UL, 0UL, TK_LINK_SIG_AGENT_REQUEST, IN_WMARK+1UL, sz, whole );
    CHECK( ctx->stage_valid==0, "an invalid fragment clears a stale staged one" );
    tkagnt_after_frag( ctx, 0UL, 0UL, 0UL, 0UL, 0UL, 0UL, NULL );
    CHECK( ctx->admitted==0UL && ctx->transport_dropped==0UL, "AFTER_FRAG after an abandoned fragment feeds nothing" );

    struct { char const * name; ulong in_idx; ulong sig; ulong chunk; ulong sz; } bad[] = {
        { "wrong sig for the request input",  0UL, TK_LINK_SIG_MODEL_RESULT,  IN_CHUNK0,     sz },
        { "request sig on a result input",    1UL, TK_LINK_SIG_AGENT_REQUEST, IN_CHUNK0,     sz },
        { "empty fragment",                   0UL, TK_LINK_SIG_AGENT_REQUEST, IN_CHUNK0,     0UL },
        { "over the link MTU",                0UL, TK_LINK_SIG_AGENT_REQUEST, IN_CHUNK0,     (ulong)TK_MP_LINK_MTU+1UL },
        { "chunk below the input's range",    0UL, TK_LINK_SIG_AGENT_REQUEST, IN_CHUNK0-1UL, sz },
        { "input index beyond in_cnt",        3UL, TK_LINK_SIG_AGENT_REQUEST, IN_CHUNK0,     sz },
    };
    for( ulong i=0UL; i<sizeof(bad)/sizeof(bad[0]); i++ ) {
        tkagnt_during_frag( ctx, 0UL, 0UL, TK_LINK_SIG_AGENT_REQUEST, IN_CHUNK0, sz, whole );   /* a valid stage to be cleared */
        tkagnt_during_frag( ctx, bad[i].in_idx, 0UL, bad[i].sig, bad[i].chunk, bad[i].sz, whole );
        if( ctx->stage_valid!=0 ) fprintf( stderr, "case failed: %s\n", bad[i].name );
        CHECK( ctx->stage_valid==0, "an invalid fragment must not be staged" );
    }
}

int
main( void ) {
    test_during_frag_stages_only_what_the_link_may_carry();
    test_admission_stages_the_model_request();
    test_denials_resolve_without_a_model_record();
    test_router_verdicts_outside_the_contract_fail_closed();
    test_a_malformed_request_fragment_admits_nothing();
    test_new_requests_are_held_back_when_there_is_no_room();
    test_a_result_completes_only_the_pending_dispatch();
    test_result_hashes_must_match_the_bytes();
    test_denied_results_and_bad_directives();
    test_a_failed_result_stream_ends_the_run_it_answered();
    if( g_failed ) { fprintf( stderr, "tkagnt correlation tests FAILED\n" ); return 1; }
    printf( "all tkagnt correlation tests passed\n" );
    return 0;
}
