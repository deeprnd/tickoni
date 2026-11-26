/* test_tkcase_after_frag.c — the case router contract of tkcase.

   Compiles the real tile source into the test and drives the real static
   tkcase_during_frag / tkcase_after_frag.  A plain buffer stands in for the
   workspace that holds the input and output dcaches, and a fd_stem_context_t
   over three real mcaches (tkpoly, tkdisp, tkaudt) stands in for fd_stem, so
   every publish is observable as an mcache entry plus the bytes at its chunk.

   Proves:
   1. The first event opens the case: a nonzero case id, state active, and the
      scope the event names (an agent request's workflow, actor and account; a
      payment's account).  A RECORD_CASE_CREATION record goes to tkaudt, ahead
      of the event, with the case id, the event's offset and trace, and the
      payload basket_id = case id with zero counts.
   2. Every event is stamped with the case id and forwarded, otherwise
      unchanged except pipeline_hops + 1, to tkpoly and to tkdisp.
   3. The capsule holds every event in arrival order, as forwarded.
   4. The event that exhausts the event count closes the case: a
      RECORD_CASE_COMPLETION record after that event, with the event count,
      state completed, and the shutdown gate set.  A one-event run opens and
      closes on the same event (two audit publishes in one iteration: the
      reason STEM_BURST is 2).  Without an event count the case stays open.
   5. DURING_FRAG stages only, clears a stale stage first, and rejects a wrong
      sig, a wrong size and a chunk outside the input's range; AFTER_FRAG with
      nothing staged publishes and commits nothing.
   6. Two runs draw different case ids (a case id is generated, not derived).
*/

#define _GNU_SOURCE

#include "../../c_abi/shim/tk_case_stem.c"

#include "tango/mcache/fd_mcache.h"

#include <stdio.h>

#define CHUNK_BYTES   ((ulong)FD_CHUNK_ALIGN)
#define IN_CHUNK0     ((ulong)2)
#define IN_WMARK      ((ulong)18)
#define OUT_DEPTH     64UL
#define BUF_CHUNKS    ((ulong)512)
#define CAPSULE_CAP   16UL

static uint8_t g_buf[ BUF_CHUNKS * 64UL ] __attribute__((aligned(64)));
static uint8_t g_mcache_mem[ TKCASE_OUT_CNT ][ FD_MCACHE_FOOTPRINT( OUT_DEPTH, 0UL ) ] __attribute__((aligned(FD_MCACHE_ALIGN)));
static TkEvent g_capsule[ CAPSULE_CAP ];

/* Each output's dcache range, disjoint from the input's and from each other. */
static ulong const OUT_CHUNK0[ TKCASE_OUT_CNT ] = {  40UL, 160UL, 280UL };
static ulong const OUT_WMARK [ TKCASE_OUT_CNT ] = { 140UL, 260UL, 380UL };

typedef struct {
    fd_frag_meta_t *  mcaches[ TKCASE_OUT_CNT ];
    ulong             seqs   [ TKCASE_OUT_CNT ];
    ulong             depths [ TKCASE_OUT_CNT ];
    ulong             cr_avail[ TKCASE_OUT_CNT ];
    ulong             min_cr_avail;
    int               out_reliable[ TKCASE_OUT_CNT ];
    fd_stem_context_t stem;
} fake_stem_t;

static int g_failed = 0;
#define CHECK(cond, msg) do { if( !(cond) ) { fprintf( stderr, "FAIL: %s (%s:%d)\n", msg, __FILE__, __LINE__ ); g_failed = 1; } } while(0)

static void
fake_stem_init( fake_stem_t * f ) {
    memset( f, 0, sizeof(*f) );
    for( ulong o=0UL; o<(ulong)TKCASE_OUT_CNT; o++ ) {
        f->mcaches[o]      = fd_mcache_join( fd_mcache_new( g_mcache_mem[o], OUT_DEPTH, 0UL, 0UL ) );
        f->depths[o]       = OUT_DEPTH;
        f->cr_avail[o]     = OUT_DEPTH;
        f->out_reliable[o] = 1;
    }
    f->min_cr_avail             = OUT_DEPTH;
    f->stem.mcaches             = f->mcaches;
    f->stem.seqs                = f->seqs;
    f->stem.depths              = f->depths;
    f->stem.cr_avail            = f->cr_avail;
    f->stem.min_cr_avail        = &f->min_cr_avail;
    f->stem.cr_decrement_amount = 1UL;
    f->stem.out_reliable        = f->out_reliable;
}

/* A context as privileged_init and unprivileged_init leave it, over the test
   buffer.  `seed` stands in for the tick count privileged_init seeds from. */
static void
ctx_init( tkcase_ctx_t * ctx, uint64_t event_count, uint seed ) {
    memset( ctx, 0, sizeof(*ctx) );
    memset( g_buf, 0, sizeof(g_buf) );
    memset( g_capsule, 0, sizeof(g_capsule) );
    FD_TEST( fd_rng_join( fd_rng_new( ctx->rng, seed, 0UL ) ) );
    ctx->event_count = event_count;
    ctx->capsule_cap = CAPSULE_CAP;
    ctx->capsule     = g_capsule;
    ctx->in.wksp     = g_buf;
    ctx->in.chunk0   = IN_CHUNK0;
    ctx->in.wmark    = IN_WMARK;
    for( ulong o=0UL; o<(ulong)TKCASE_OUT_CNT; o++ ) {
        ctx->out[o].wksp   = g_buf;
        ctx->out[o].chunk0 = OUT_CHUNK0[o];
        ctx->out[o].wmark  = OUT_WMARK[o];
        ctx->out[o].chunk  = OUT_CHUNK0[o];
    }
}

static TkEvent
agent_event( uint64_t offset ) {
    TkEvent ev;
    memset( &ev, 0, sizeof(ev) );
    ev.version       = TK_EVENT_WIRE_VERSION;
    ev.kind          = TK_EVENT_KIND_AGENT_REQUEST;
    ev.source        = TK_EVENT_SOURCE_TKGATE;
    ev.pipeline_hops = 3;
    ev.trace_id[0]   = (uint8_t)(0x40 + offset);
    ev.idempotency_key = 1000UL + offset;
    ev.source_offset = offset;
    ev.event_hash    = 0xabc0UL + offset;
    ev.body.agent_request.scope.actor_id   = 2001UL;
    ev.body.agent_request.scope.account_id = 3001UL;
    memcpy( ev.body.agent_request.scope.workflow, "trading_control", 15 );
    return ev;
}

static TkEvent
payment_event( uint64_t offset ) {
    TkEvent ev = agent_event( offset );
    memset( &ev.body, 0, sizeof(ev.body) );
    ev.kind = TK_EVENT_KIND_PAYMENT;
    ev.body.payment.account_id   = 77U;
    ev.body.payment.amount_cents = 2000;
    return ev;
}

/* Places `ev` in the input dcache and runs it through DURING_FRAG and
   AFTER_FRAG, as fd_stem does for an intact fragment. */
static void
feed( tkcase_ctx_t * ctx, fake_stem_t * f, TkEvent const * ev ) {
    ulong chunk = IN_CHUNK0;
    memcpy( g_buf + chunk*CHUNK_BYTES, ev, sizeof(*ev) );
    tkcase_during_frag( ctx, 0UL, 0UL, TK_LINK_SIG_EVENT, chunk, TK_EVENT_SIZE, 0UL );
    tkcase_after_frag( ctx, 0UL, 0UL, TK_LINK_SIG_EVENT, TK_EVENT_SIZE, 0UL, 0UL, &f->stem );
}

/* The i-th fragment published on output o: its metadata and its bytes. */
static fd_frag_meta_t const *
published( fake_stem_t const * f, ulong o, ulong i ) {
    return f->mcaches[o] + fd_mcache_line_idx( i, OUT_DEPTH );
}

static void const *
published_bytes( fake_stem_t const * f, ulong o, ulong i ) {
    return g_buf + published( f, o, i )->chunk * CHUNK_BYTES;
}

static int
case_record_is( fake_stem_t const * f, ulong i, uint8_t record_type, uint64_t case_id,
                uint64_t offset, uint64_t event_count ) {
    fd_frag_meta_t const * meta = published( f, TKCASE_OUT_AUDIT, i );
    if( meta->sig!=TK_LINK_SIG_CASE_AUDIT || meta->sz!=sizeof(TkCaseAuditMsg) ) return 0;
    TkCaseAuditMsg const * m = published_bytes( f, TKCASE_OUT_AUDIT, i );
    return m->version==TK_CASE_WIRE_VERSION && m->record_type==record_type && m->case_id==case_id &&
           m->source_offset==offset && m->event_count==event_count &&
           m->trace_id[0]==(uint8_t)(0x40 + offset) &&
           m->payload.basket_id==case_id && m->payload.instrument_count==0 &&
           m->payload.rejected_count==0 && m->payload.total_allocated_cents==0;
}

static void
test_first_event_opens_the_case( void ) {
    tkcase_ctx_t ctx; fake_stem_t f; fake_stem_init( &f ); ctx_init( &ctx, 3UL, 11U );
    TkEvent ev = agent_event( 0 );
    feed( &ctx, &f, &ev );
    CHECK( ctx.scope.state==TK_CASE_STATE_ACTIVE, "the first event opens the case" );
    CHECK( ctx.scope.case_id!=0UL, "the case id is nonzero" );
    CHECK( ctx.scope.actor_id==2001UL && ctx.scope.account_id==3001UL, "the scope takes the agent request's actor and account" );
    CHECK( !memcmp( ctx.scope.workflow, "trading_control", 15 ), "the scope takes the agent request's workflow" );
    CHECK( ctx.scope.first_source_offset==0UL && ctx.scope.event_count==1UL, "the scope counts the opening event" );
    CHECK( f.seqs[TKCASE_OUT_AUDIT]==1UL, "exactly one audit record after one event" );
    CHECK( case_record_is( &f, 0UL, RECORD_CASE_CREATION, ctx.scope.case_id, 0UL, 1UL ), "a creation record with the case and the event's offset and trace" );
    CHECK( ctx.case_audit_emitted==1UL && ctx.input_exhausted==0, "the case is open, the run goes on" );

    tkcase_ctx_t p; fake_stem_t g; fake_stem_init( &g ); ctx_init( &p, 0UL, 12U );
    TkEvent pay = payment_event( 0 );
    feed( &p, &g, &pay );
    CHECK( p.scope.account_id==77UL && p.scope.actor_id==0UL && p.scope.workflow[0]==0, "a payment names only its account" );
}

static void
test_every_event_is_attached_and_forwarded_to_both_outputs( void ) {
    tkcase_ctx_t ctx; fake_stem_t f; fake_stem_init( &f ); ctx_init( &ctx, 0UL, 21U );
    for( uint64_t i=0UL; i<4UL; i++ ) {
        TkEvent ev = agent_event( i );
        feed( &ctx, &f, &ev );
    }
    uint64_t case_id = ctx.scope.case_id;
    CHECK( ctx.consumed==4UL && ctx.forwarded==8UL, "four events, eight forwarded fragments" );
    CHECK( f.seqs[TKCASE_OUT_POLY]==4UL && f.seqs[TKCASE_OUT_DISP]==4UL, "each event goes once to tkpoly and once to tkdisp" );
    for( ulong o=TKCASE_OUT_POLY; o<=TKCASE_OUT_DISP; o++ ) {
        for( uint64_t i=0UL; i<4UL; i++ ) {
            fd_frag_meta_t const * meta = published( &f, o, i );
            CHECK( meta->sig==TK_LINK_SIG_EVENT && meta->sz==TK_EVENT_SIZE, "a whole TkEvent fragment" );
            CHECK( meta->chunk>=OUT_CHUNK0[o] && meta->chunk<=OUT_WMARK[o], "written into its own output's dcache" );
            TkEvent want = agent_event( i );
            want.case_id       = case_id;
            want.pipeline_hops = (uint8_t)(want.pipeline_hops + 1);
            CHECK( !memcmp( published_bytes( &f, o, i ), &want, sizeof(want) ), "the event, stamped with the case id and one more hop, otherwise unchanged" );
        }
    }
    CHECK( ctx.capsule_count==4UL, "the capsule holds every event" );
    for( uint64_t i=0UL; i<4UL; i++ ) {
        CHECK( g_capsule[i].source_offset==i && g_capsule[i].case_id==case_id, "the capsule is in arrival order and stamped" );
        CHECK( !memcmp( &g_capsule[i], published_bytes( &f, TKCASE_OUT_POLY, i ), sizeof(TkEvent) ), "a capsule entry is the event as forwarded" );
    }
    CHECK( f.seqs[TKCASE_OUT_AUDIT]==1UL && ctx.scope.state==TK_CASE_STATE_ACTIVE, "without an event count the case stays open" );
    CHECK( ctx.scope.event_count==4UL && ctx.scope.last_source_offset==3UL, "the scope tracks the latest event" );
}

static void
test_the_last_event_closes_the_case( void ) {
    tkcase_ctx_t ctx; fake_stem_t f; fake_stem_init( &f ); ctx_init( &ctx, 3UL, 31U );
    for( uint64_t i=0UL; i<3UL; i++ ) {
        TkEvent ev = agent_event( i );
        feed( &ctx, &f, &ev );
        if( i<2UL ) CHECK( ctx.input_exhausted==0 && ctx.scope.state==TK_CASE_STATE_ACTIVE, "the case stays open before the last event" );
    }
    CHECK( ctx.scope.state==TK_CASE_STATE_COMPLETED, "the last event closes the case" );
    CHECK( ctx.input_exhausted==1, "and sets the shutdown gate" );
    CHECK( f.seqs[TKCASE_OUT_AUDIT]==2UL && ctx.case_audit_emitted==2UL, "two lifecycle records in all" );
    CHECK( case_record_is( &f, 1UL, RECORD_CASE_COMPLETION, ctx.scope.case_id, 2UL, 3UL ), "a completion record with the last event's offset and the event count" );
    CHECK( f.seqs[TKCASE_OUT_POLY]==3UL && f.seqs[TKCASE_OUT_DISP]==3UL, "the last event is still forwarded" );

    /* One event: opened and closed on the same event, two audit publishes in
       one iteration. */
    tkcase_ctx_t one; fake_stem_t g; fake_stem_init( &g ); ctx_init( &one, 1UL, 32U );
    TkEvent ev = agent_event( 0 );
    feed( &one, &g, &ev );
    CHECK( g.seqs[TKCASE_OUT_AUDIT]==2UL, "creation and completion in one iteration" );
    CHECK( case_record_is( &g, 0UL, RECORD_CASE_CREATION,   one.scope.case_id, 0UL, 1UL ), "creation first" );
    CHECK( case_record_is( &g, 1UL, RECORD_CASE_COMPLETION, one.scope.case_id, 0UL, 1UL ), "then completion" );
    CHECK( g.cr_avail[TKCASE_OUT_AUDIT]==OUT_DEPTH-2UL && g.cr_avail[TKCASE_OUT_POLY]==OUT_DEPTH-1UL,
           "two credits on the audit link, one on each event link: within STEM_BURST" );
}

static void
test_during_frag_stages_only_and_rejects_bad_fragments( void ) {
    tkcase_ctx_t ctx; fake_stem_t f; fake_stem_init( &f ); ctx_init( &ctx, 0UL, 41U );
    TkEvent ev = agent_event( 0 );
    memcpy( g_buf + IN_CHUNK0*CHUNK_BYTES, &ev, sizeof(ev) );

    tkcase_during_frag( &ctx, 0UL, 0UL, TK_LINK_SIG_EVENT, IN_CHUNK0, TK_EVENT_SIZE, 0UL );
    CHECK( ctx.stage_valid==1, "a well-formed event is staged" );
    CHECK( ctx.consumed==0UL && ctx.scope.state==TK_CASE_STATE_NONE && ctx.capsule_count==0UL &&
           f.seqs[0]==0UL && f.seqs[1]==0UL && f.seqs[2]==0UL, "staging commits and publishes nothing" );

    /* The abandoned-fragment case: an invalid fragment after a valid,
       never-committed one leaves nothing to commit. */
    tkcase_during_frag( &ctx, 0UL, 0UL, TK_LINK_SIG_EVENT, IN_WMARK+1UL, TK_EVENT_SIZE, 0UL );
    CHECK( ctx.stage_valid==0, "a chunk above the input range clears the stale stage" );
    tkcase_after_frag( &ctx, 0UL, 0UL, 0UL, 0UL, 0UL, 0UL, &f.stem );
    CHECK( ctx.consumed==0UL && f.seqs[0]==0UL && f.seqs[2]==0UL, "AFTER_FRAG with nothing staged commits nothing" );

    tkcase_during_frag( &ctx, 0UL, 0UL, TK_LINK_SIG_EVENT, IN_CHUNK0-1UL, TK_EVENT_SIZE, 0UL );
    CHECK( ctx.stage_valid==0, "a chunk below the input range is rejected" );
    tkcase_during_frag( &ctx, 0UL, 0UL, TK_LINK_SIG_CASE_AUDIT, IN_CHUNK0, TK_EVENT_SIZE, 0UL );
    CHECK( ctx.stage_valid==0, "a fragment that is not an event is rejected" );
    tkcase_during_frag( &ctx, 0UL, 0UL, TK_LINK_SIG_EVENT, IN_CHUNK0, TK_EVENT_SIZE-1UL, 0UL );
    CHECK( ctx.stage_valid==0, "a short event is rejected" );
    tkcase_during_frag( &ctx, 0UL, 0UL, TK_LINK_SIG_EVENT, IN_CHUNK0, 0UL, 0UL );
    CHECK( ctx.stage_valid==0, "an empty fragment is rejected" );
    tkcase_during_frag( &ctx, 0UL, 0UL, TK_LINK_SIG_EVENT, IN_WMARK, TK_EVENT_SIZE, 0UL );
    CHECK( ctx.stage_valid==1, "the input range is inclusive at its watermark" );
}

static void
test_case_ids_are_generated_per_run( void ) {
    tkcase_ctx_t a; fake_stem_t f; fake_stem_init( &f ); ctx_init( &a, 0UL, 51U );
    TkEvent ev = agent_event( 0 );
    feed( &a, &f, &ev );
    uint64_t first = a.scope.case_id;
    tkcase_ctx_t b; fake_stem_t g; fake_stem_init( &g ); ctx_init( &b, 0UL, 52U );
    feed( &b, &g, &ev );
    CHECK( first!=0UL && b.scope.case_id!=0UL && first!=b.scope.case_id, "the same event opens a different case in another run" );
}

int
main( void ) {
    test_first_event_opens_the_case();
    test_every_event_is_attached_and_forwarded_to_both_outputs();
    test_the_last_event_closes_the_case();
    test_during_frag_stages_only_and_rejects_bad_fragments();
    test_case_ids_are_generated_per_run();
    if( g_failed ) { fprintf( stderr, "tkcase AFTER_FRAG tests FAILED\n" ); return 1; }
    printf( "all tkcase AFTER_FRAG tests passed\n" );
    return 0;
}
