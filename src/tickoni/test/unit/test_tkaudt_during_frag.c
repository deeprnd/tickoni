/* test_tkaudt_during_frag.c — multi-input DURING_FRAG contract for tkaudt.

   Compiles the real tile source into the test and drives the real static
   tk_audit_during_frag / tk_audit_after_frag.  tkaudt is a fan-in sink: a
   payment-pipeline link and one model-audit link per tkmodl instance all feed
   it, and fd_stem tells it which input a fragment arrived on (in_idx).  Each
   input has its OWN dcache chunk range, so a chunk that is valid for one input
   can lie outside another's.  A plain buffer stands in for the shared
   workspace (every input here sits in one explicitly shared workspace; tile
   init rejects any input that does not).

   Proves:
   1. A well-formed payment record on input 0 and a model-audit record on
      input 1 are each staged, with no counter or chain change.
   2. A chunk inside input 0's range but fed on input 1 (and the reverse) is
      rejected: the range check uses the fragment's own input.
   3. Both bounds of each input's range are inclusive; one past either bound is
      rejected.
   4. An input index at or beyond in_cnt is rejected.
   5. DURING_FRAG clears stage_valid FIRST: an invalid fragment after a valid,
      never-committed one (the abandoned-fragment case) leaves nothing for
      AFTER_FRAG to commit.
   6. AFTER_FRAG with nothing staged commits nothing.
   7. Ordered mode (an agent input present): the committed sequence is, for each
      admission ordinal in order, the model record then the agent record,
      whatever order the model records arrived in; an agent record waits for its
      model record and for nothing else; the watermark advances only after the
      agent record is appended; late, duplicate and out-of-order records are
      refused rather than reordered.
   8. Event order (a payment input as well): the chain is one sequence in event
      order, payment record, model record, agent record, for event 1 and then
      event 2 and so on, whatever order the records reach tkaudt in.  A payment
      record is held back upstream (BEFORE_FRAG -1) until the previous event's
      agent record is committed, and an agent record waits for its own event's
      payment record.  Without both a payment chain and agent runs, nothing is
      held back.
*/

#define _GNU_SOURCE

#include "../../c_abi/shim/tk_audit_stem.c"

#include <stdio.h>

#define CHUNK_BYTES   ((ulong)FD_CHUNK_ALIGN)
#define IN0_CHUNK0    ((ulong)2)
#define IN0_WMARK     ((ulong)10)
#define IN1_CHUNK0    ((ulong)24)
#define IN1_WMARK     ((ulong)32)
#define BUF_CHUNKS    ((ulong)64)

static uint8_t    g_buf[ 64UL * 64UL ] __attribute__((aligned(64)));
static AuditEvent g_records[ 16 ];
static uint8_t    g_fseq[ 256 ] __attribute__((aligned(128)));

static void
ctx_init( tk_audit_ctx_t * ctx ) {
    memset( ctx, 0, sizeof(*ctx) );
    memset( g_buf, 0, sizeof(g_buf) );
    memset( g_records, 0, sizeof(g_records) );
    ctx->wksp          = g_buf;
    ctx->audit_records = g_records;
    ctx->in_cnt        = 2UL;
    ctx->in_chunk0[0]  = IN0_CHUNK0;
    ctx->in_wmark[0]   = IN0_WMARK;
    ctx->in_chunk0[1]  = IN1_CHUNK0;
    ctx->in_wmark[1]   = IN1_WMARK;
}

/* Everything DURING_FRAG must never change, as one comparison. */
typedef struct {
    uint64_t audit_count, audited, prev_hash;
    int32_t  input_exhausted;
} snapshot_t;

static snapshot_t
snap( tk_audit_ctx_t const * c ) {
    snapshot_t s = { c->audit_count, c->audited, c->prev_hash, c->input_exhausted };
    return s;
}

static int
unchanged( tk_audit_ctx_t const * c, snapshot_t const * s ) {
    return c->audit_count==s->audit_count && c->audited==s->audited &&
           c->prev_hash==s->prev_hash && c->input_exhausted==s->input_exhausted;
}

static int g_failed = 0;
#define CHECK(cond, msg) do { if( !(cond) ) { fprintf( stderr, "FAIL: %s (%s:%d)\n", msg, __FILE__, __LINE__ ); g_failed = 1; } } while(0)

static void
place_payment( ulong chunk ) {
    memset( g_buf + chunk*CHUNK_BYTES, 0, PAYMENT_MSG_SIZE );
}

static void
place_model_audit( ulong chunk ) {
    ModelAuditMsg m;
    memset( &m, 0, sizeof(m) );
    m.version     = TKMODL_WIRE_VERSION;
    m.record_type = RECORD_MODEL_CALL;
    m.run_id      = 7;
    m.request_id  = 9;
    memcpy( g_buf + chunk*CHUNK_BYTES, &m, sizeof(m) );
}

static void
frag_payment( tk_audit_ctx_t * ctx, ulong in_idx, ulong chunk ) {
    tk_audit_during_frag( ctx, in_idx, 0UL, TK_LINK_SIG_PAYMENT, chunk, PAYMENT_MSG_SIZE, 0UL );
}

static void
frag_model( tk_audit_ctx_t * ctx, ulong in_idx, ulong chunk ) {
    tk_audit_during_frag( ctx, in_idx, 0UL, TK_LINK_SIG_MODEL_CALL, chunk, sizeof(ModelAuditMsg), 0UL );
}

static void
test_each_input_stages_its_own_record( void ) {
    tk_audit_ctx_t ctx; ctx_init( &ctx );
    snapshot_t s = snap( &ctx );

    place_payment( IN0_CHUNK0 );
    frag_payment( &ctx, 0UL, IN0_CHUNK0 );
    CHECK( ctx.stage_valid==1, "payment record on input 0 must be staged" );
    CHECK( unchanged( &ctx, &s ), "staging a payment record must not touch the chain or counters" );

    ctx.stage_valid = 0;
    ctx.in_role[1] = TKAUDT_ROLE_MODEL;
    place_model_audit( IN1_CHUNK0 );
    frag_model( &ctx, 1UL, IN1_CHUNK0 );
    CHECK( ctx.stage_valid==1, "model-audit record on input 1 must be staged" );
    CHECK( ctx.stage.header.run_id==7 && ctx.stage.header.source_offset==9,
           "staged record must be built from the model-audit fragment" );
    CHECK( unchanged( &ctx, &s ), "staging a model-audit record must not touch the chain or counters" );
}

static void
test_chunk_range_is_per_input( void ) {
    /* Chunk 5 is inside input 0's range [2,10] but outside input 1's [24,32];
       chunk 28 is the reverse.  A shared range (the old behavior: none at all)
       would accept both. */
    struct { char const * name; ulong in_idx; ulong chunk; int expect_staged; } cases[] = {
        { "input 0, chunk in its own range",          0UL, 5UL,             1 },
        { "input 1, chunk in its own range",          1UL, 28UL,            1 },
        { "input 1, chunk in input 0's range",        1UL, 5UL,             0 },
        { "input 0, chunk in input 1's range",        0UL, 28UL,            0 },
        { "input 0, chunk == in_chunk0 (inclusive)",  0UL, IN0_CHUNK0,      1 },
        { "input 0, chunk == in_wmark (inclusive)",   0UL, IN0_WMARK,       1 },
        { "input 0, chunk below in_chunk0",           0UL, IN0_CHUNK0-1UL,  0 },
        { "input 0, chunk above in_wmark",            0UL, IN0_WMARK+1UL,   0 },
        { "input 1, chunk == in_chunk0 (inclusive)",  1UL, IN1_CHUNK0,      1 },
        { "input 1, chunk == in_wmark (inclusive)",   1UL, IN1_WMARK,       1 },
        { "input 1, chunk below in_chunk0",           1UL, IN1_CHUNK0-1UL,  0 },
        { "input 1, chunk above in_wmark",            1UL, IN1_WMARK+1UL,   0 },
    };
    for( ulong i=0UL; i<sizeof(cases)/sizeof(cases[0]); i++ ) {
        tk_audit_ctx_t ctx; ctx_init( &ctx );
        snapshot_t s = snap( &ctx );
        place_payment( cases[i].chunk );
        frag_payment( &ctx, cases[i].in_idx, cases[i].chunk );
        if( ctx.stage_valid != cases[i].expect_staged )
            fprintf( stderr, "case failed: %s\n", cases[i].name );
        CHECK( ctx.stage_valid==cases[i].expect_staged, "staging verdict must follow the fragment's own input range" );
        CHECK( unchanged( &ctx, &s ), "DURING_FRAG must change no chain or counter state" );
    }
}

static void
test_input_index_beyond_in_cnt_is_rejected( void ) {
    tk_audit_ctx_t ctx; ctx_init( &ctx );
    place_payment( IN0_CHUNK0 );
    snapshot_t s = snap( &ctx );
    frag_payment( &ctx, 2UL, IN0_CHUNK0 );     /* in_cnt is 2: valid indexes are 0 and 1 */
    CHECK( ctx.stage_valid==0, "an input index at in_cnt must be rejected" );
    frag_payment( &ctx, 255UL, IN0_CHUNK0 );
    CHECK( ctx.stage_valid==0, "an input index far beyond in_cnt must be rejected" );
    CHECK( unchanged( &ctx, &s ), "a rejected input index must change no state" );
}

/* The abandoned-fragment case: fd_stem skips AFTER_FRAG when the producer
   overran the reader, so a stale stage_valid would let the NEXT AFTER_FRAG
   commit a record built from an abandoned read. */
static void
test_stale_stage_is_cleared_first( void ) {
    tk_audit_ctx_t ctx; ctx_init( &ctx );
    place_payment( IN0_CHUNK0 );
    frag_payment( &ctx, 0UL, IN0_CHUNK0 );     /* staged, never committed */
    CHECK( ctx.stage_valid==1, "precondition: staged" );

    frag_payment( &ctx, 1UL, 5UL );            /* next fragment is out of input 1's range */
    CHECK( ctx.stage_valid==0, "an invalid fragment must clear a stale staged record" );

    snapshot_t s = snap( &ctx );
    tk_audit_after_frag( &ctx, 1UL, 0UL, 0UL, 0UL, 0UL, 0UL, NULL );
    CHECK( unchanged( &ctx, &s ), "AFTER_FRAG after an abandoned fragment must commit nothing" );
}

static void
test_after_frag_with_nothing_staged( void ) {
    tk_audit_ctx_t ctx; ctx_init( &ctx );
    snapshot_t s = snap( &ctx );
    tk_audit_after_frag( &ctx, 0UL, 0UL, 0UL, 0UL, 0UL, 0UL, NULL );
    CHECK( unchanged( &ctx, &s ), "AFTER_FRAG with nothing staged must commit nothing" );
}


/* ─── Ordered mode ─── */

#define ROLE_MODEL_IN  1UL
#define ROLE_AGENT_IN  2UL
#define ORD_CHUNK_M    ((ulong)3)
#define ORD_CHUNK_A    ((ulong)5)

static void
ordered_ctx_init( tk_audit_ctx_t * ctx ) {
    ctx_init( ctx );
    ctx->in_cnt                 = 3UL;
    ctx->in_chunk0[2]           = IN0_CHUNK0;
    ctx->in_wmark[2]            = IN0_WMARK;
    ctx->in_chunk0[0]           = IN0_CHUNK0;     /* all three inputs share one range here */
    ctx->in_wmark[0]            = IN0_WMARK;
    ctx->in_chunk0[1]           = IN0_CHUNK0;
    ctx->in_wmark[1]            = IN0_WMARK;
    ctx->in_role[0]             = TKAUDT_ROLE_PAYMENT;
    ctx->in_role[1]             = TKAUDT_ROLE_MODEL;
    ctx->in_role[2]             = TKAUDT_ROLE_AGENT;
    ctx->ordered                = 1;
    ctx->next_agent_seq         = 1UL;
    memset( g_fseq, 0, sizeof(g_fseq) );
    fd_fseq_new( g_fseq, ULONG_MAX );
    ctx->watermark              = fd_fseq_join( g_fseq );
}

static void
commit_frag( tk_audit_ctx_t * ctx, ulong in_idx, ulong sig, ulong sz ) {
    tk_audit_during_frag( ctx, in_idx, 0UL, sig, ORD_CHUNK_M, sz, 0UL );
    tk_audit_after_frag( ctx, in_idx, 0UL, sig, sz, 0UL, 0UL, NULL );
}

static void
feed_model( tk_audit_ctx_t * ctx, uint64_t seq ) {
    ModelAuditMsg m;
    memset( &m, 0, sizeof(m) );
    m.version     = TKMODL_WIRE_VERSION;
    m.record_type = RECORD_MODEL_CALL;
    m.run_id      = 100UL+seq;
    m.request_id  = seq;
    memcpy( g_buf + ORD_CHUNK_M*CHUNK_BYTES, &m, sizeof(m) );
    commit_frag( ctx, ROLE_MODEL_IN, TK_LINK_SIG_MODEL_CALL, sizeof(m) );
}

static void
feed_agent( tk_audit_ctx_t * ctx, uint64_t seq, int has_model ) {
    TkAgentAuditMsg a;
    memset( &a, 0, sizeof(a) );
    a.version          = TK_AGENT_WIRE_VERSION;
    a.record_type      = RECORD_PROPOSAL;
    a.has_model_record = (uint8_t)has_model;
    a.run_id           = 100UL+seq;
    a.agent_seq        = seq;
    a.payload.proposal.proposal_hash = 1000UL+seq;
    memcpy( g_buf + ORD_CHUNK_M*CHUNK_BYTES, &a, sizeof(a) );
    commit_frag( ctx, ROLE_AGENT_IN, TK_LINK_SIG_AGENT_AUDIT, sizeof(a) );
}

/* The committed sequence as (source_offset, record_type) pairs. */
static int
committed_is( tk_audit_ctx_t const * ctx, ulong n, uint64_t const * seqs, uint8_t const * types ) {
    if( ctx->audit_count!=n ) return 0;
    for( ulong i=0UL; i<n; i++ )
        if( ctx->audit_records[i].header.source_offset!=seqs[i] || ctx->audit_records[i].record_type!=types[i] ) return 0;
    return 1;
}

static void
test_ordered_commit_is_independent_of_model_arrival( void ) {
    uint64_t const seqs[]  = { 1, 1, 2, 2, 3, 3 };
    uint8_t  const types[] = { RECORD_MODEL_CALL, RECORD_PROPOSAL, RECORD_MODEL_CALL, RECORD_PROPOSAL, RECORD_MODEL_CALL, RECORD_PROPOSAL };

    /* Every arrival order of the three model records, with the agent records
       (always in admission order) interleaved at several points. */
    static int const perms[6][3] = { {1,2,3},{1,3,2},{2,1,3},{2,3,1},{3,1,2},{3,2,1} };
    for( int pi=0; pi<6; pi++ ) {
        for( int agents_first=0; agents_first<3; agents_first++ ) {
            tk_audit_ctx_t ctx; ordered_ctx_init( &ctx );
            if( agents_first==1 ) { feed_agent( &ctx, 1, 1 ); feed_agent( &ctx, 2, 1 ); feed_agent( &ctx, 3, 1 ); }
            for( int k=0; k<3; k++ ) feed_model( &ctx, (uint64_t)perms[pi][k] );
            if( agents_first==0 ) { feed_agent( &ctx, 1, 1 ); feed_agent( &ctx, 2, 1 ); feed_agent( &ctx, 3, 1 ); }
            if( agents_first==2 ) { /* agents interleaved between model arrivals is covered by 0 and 1 */
                tk_audit_ctx_t ctx2; ordered_ctx_init( &ctx2 );
                feed_model( &ctx2, (uint64_t)perms[pi][0] ); feed_agent( &ctx2, 1, 1 );
                feed_model( &ctx2, (uint64_t)perms[pi][1] ); feed_agent( &ctx2, 2, 1 );
                feed_model( &ctx2, (uint64_t)perms[pi][2] ); feed_agent( &ctx2, 3, 1 );
                CHECK( committed_is( &ctx2, 6UL, seqs, types ), "interleaved arrival must commit in admission order" );
                CHECK( fd_fseq_query( ctx2.watermark )==3UL, "watermark reaches the last committed ordinal" );
                continue;
            }
            CHECK( committed_is( &ctx, 6UL, seqs, types ), "committed sequence must not depend on model arrival order" );
            CHECK( ctx.agent_committed==3UL && ctx.model_held_cnt==0UL && ctx.agent_held_cnt==0UL, "nothing is left held" );
            CHECK( ctx.rejected==0UL, "no record is refused in a valid stream" );
            CHECK( fd_fseq_query( ctx.watermark )==3UL, "watermark reaches the last committed ordinal" );

            /* The chain is linked and the hashes are a function of the sequence alone. */
            for( ulong i=1UL; i<ctx.audit_count; i++ )
                CHECK( ctx.audit_records[i].header.prev_hash==ctx.audit_records[i-1UL].header.record_hash, "hash chain is contiguous" );
        }
    }
}

static void
test_chain_is_identical_across_arrival_orders( void ) {
    uint64_t last_hash[2] = {0,0};
    for( int variant=0; variant<2; variant++ ) {
        tk_audit_ctx_t ctx; ordered_ctx_init( &ctx );
        if( variant==0 ) { feed_model( &ctx, 1 ); feed_model( &ctx, 2 ); }
        else             { feed_model( &ctx, 2 ); feed_model( &ctx, 1 ); }
        feed_agent( &ctx, 1, 1 ); feed_agent( &ctx, 2, 1 );
        last_hash[variant] = ctx.prev_hash;
        CHECK( ctx.audit_count==4UL, "four records committed" );
    }
    CHECK( last_hash[0]==last_hash[1] && last_hash[0]!=0UL, "the chain head must be identical for either arrival order" );
}

static void
test_watermark_follows_the_commit( void ) {
    tk_audit_ctx_t ctx; ordered_ctx_init( &ctx );
    CHECK( fd_fseq_query( ctx.watermark )==ULONG_MAX, "nothing committed yet" );
    feed_agent( &ctx, 1, 1 );                 /* waits for its model record */
    CHECK( ctx.audit_count==0UL && ctx.agent_held_cnt==1UL, "the agent record is held" );
    CHECK( fd_fseq_query( ctx.watermark )==ULONG_MAX, "the watermark must not advance before the commit" );
    feed_model( &ctx, 1 );
    CHECK( ctx.audit_count==2UL && fd_fseq_query( ctx.watermark )==1UL, "commit, then watermark" );
}

static void
test_agent_record_without_model_does_not_wait( void ) {
    /* A run denied at routing has no model record: its agent record commits
       alone, and the next ordinal is unaffected. */
    tk_audit_ctx_t ctx; ordered_ctx_init( &ctx );
    feed_agent( &ctx, 1, 0 );
    CHECK( ctx.audit_count==1UL && ctx.agent_committed==1UL, "a record with no model record commits alone" );
    CHECK( fd_fseq_query( ctx.watermark )==1UL, "watermark advanced" );
    feed_model( &ctx, 2 ); feed_agent( &ctx, 2, 1 );
    CHECK( ctx.audit_count==3UL, "the next ordinal commits normally" );
}

static void
test_late_duplicate_and_out_of_order_are_refused( void ) {
    tk_audit_ctx_t ctx; ordered_ctx_init( &ctx );
    feed_agent( &ctx, 1, 0 );                 /* ordinal 1 committed with no model record */
    feed_model( &ctx, 1 );                    /* ... so a model record for 1 is late */
    CHECK( ctx.rejected==1UL && ctx.model_held_cnt==0UL, "a late model record is refused" );

    feed_model( &ctx, 2 ); feed_model( &ctx, 2 );   /* duplicate */
    CHECK( ctx.rejected==2UL && ctx.model_held_cnt==1UL, "a duplicate model record is refused" );

    feed_agent( &ctx, 5, 0 );                 /* ordinal 2 is next; 5 skips ahead */
    CHECK( ctx.rejected==3UL && ctx.agent_held_cnt==0UL, "an out-of-order agent record is refused, not reordered" );
    feed_agent( &ctx, 1, 0 );                 /* replay of a committed ordinal */
    CHECK( ctx.rejected==4UL, "a replayed agent record is refused" );
    CHECK( ctx.audit_count==1UL, "refusals commit nothing" );
}

static void
test_hold_bound_is_enforced( void ) {
    tk_audit_ctx_t ctx; ordered_ctx_init( &ctx );
    for( uint64_t i=1; i<=TKAUDT_HOLD; i++ ) feed_model( &ctx, 1000UL+i );   /* ordinals far ahead: held */
    CHECK( ctx.model_held_cnt==TKAUDT_HOLD, "the model hold fills to its bound" );
    feed_model( &ctx, 2000UL );
    CHECK( ctx.model_held_cnt==TKAUDT_HOLD && ctx.rejected==1UL, "one past the bound is refused, never dropped silently" );
}

static void
test_unordered_mode_commits_on_arrival( void ) {
    /* No agent input: payment and model records commit as they arrive. */
    tk_audit_ctx_t ctx; ctx_init( &ctx );
    ctx.in_role[1] = TKAUDT_ROLE_MODEL;
    place_payment( IN0_CHUNK0 );
    tk_audit_during_frag( &ctx, 0UL, 0UL, TK_LINK_SIG_PAYMENT, IN0_CHUNK0, PAYMENT_MSG_SIZE, 0UL );
    tk_audit_after_frag( &ctx, 0UL, 0UL, 0UL, 0UL, 0UL, 0UL, NULL );
    CHECK( ctx.audit_count==1UL && ctx.audited==1UL, "a payment record commits on arrival" );
    place_model_audit( IN1_CHUNK0 );
    frag_model( &ctx, 1UL, IN1_CHUNK0 );
    tk_audit_after_frag( &ctx, 1UL, 0UL, 0UL, 0UL, 0UL, 0UL, NULL );
    CHECK( ctx.audit_count==2UL && ctx.audit_records[1].record_type==RECORD_MODEL_CALL, "a model record commits on arrival" );
}

/* ─── Event order ─── */

static void
event_ordered_ctx_init( tk_audit_ctx_t * ctx ) {
    ordered_ctx_init( ctx );
    ctx->has_payment_input = 1;
}

/* The n-th payment record (event offset n-1), committed on the payment input
   the way fd_stem would deliver it: only if BEFORE_FRAG lets it through. */
static int
feed_payment( tk_audit_ctx_t * ctx, uint64_t n ) {
    if( tk_audit_before_frag( ctx, 0UL, 0UL, TK_LINK_SIG_PAYMENT )!=0 ) return 0;
    PaymentMessage p;
    memset( &p, 0, sizeof(p) );
    p.raw.source_offset = n-1UL;
    memcpy( g_buf + ORD_CHUNK_M*CHUNK_BYTES, &p, sizeof(p) );
    commit_frag( ctx, 0UL, TK_LINK_SIG_PAYMENT, PAYMENT_MSG_SIZE );
    return 1;
}

static int
event_order_is( tk_audit_ctx_t const * ctx ) {
    /* P1 (offset 0), M1, A1, P2 (offset 1), M2, A2. */
    uint64_t const seqs[]  = { 0, 1, 1, 1, 2, 2 };
    uint8_t  const types[] = { RECORD_POLICY_DECISION, RECORD_MODEL_CALL, RECORD_PROPOSAL,
                               RECORD_POLICY_DECISION, RECORD_MODEL_CALL, RECORD_PROPOSAL };
    return committed_is( ctx, 6UL, seqs, types );
}

static void
test_event_order_is_independent_of_arrival( void ) {
    uint64_t heads[3] = {0,0,0};

    /* S1: the records of each event in their natural order. */
    {
        tk_audit_ctx_t ctx; event_ordered_ctx_init( &ctx );
        CHECK( feed_payment( &ctx, 1 ), "the first payment record is taken" );
        feed_model( &ctx, 1 ); feed_agent( &ctx, 1, 1 );
        CHECK( feed_payment( &ctx, 2 ), "the second payment record is taken once agent 1 is committed" );
        feed_model( &ctx, 2 ); feed_agent( &ctx, 2, 1 );
        CHECK( event_order_is( &ctx ), "natural arrival commits in event order" );
        heads[0] = ctx.prev_hash;
    }
    /* S2: each event's agent and model records before its payment record. */
    {
        tk_audit_ctx_t ctx; event_ordered_ctx_init( &ctx );
        feed_agent( &ctx, 1, 1 ); feed_model( &ctx, 1 );
        CHECK( ctx.audit_count==0UL, "an agent record waits for its event's payment record" );
        CHECK( feed_payment( &ctx, 1 ), "payment 1 is taken" );
        CHECK( ctx.audit_count==3UL, "payment 1 releases the model and agent records behind it" );
        feed_agent( &ctx, 2, 1 ); feed_model( &ctx, 2 );
        CHECK( feed_payment( &ctx, 2 ), "payment 2 is taken" );
        CHECK( event_order_is( &ctx ), "agent-first arrival commits in event order" );
        heads[1] = ctx.prev_hash;
    }
    /* S3: both events' model and agent records queued ahead of any payment record. */
    {
        tk_audit_ctx_t ctx; event_ordered_ctx_init( &ctx );
        feed_model( &ctx, 1 ); feed_model( &ctx, 2 );
        feed_agent( &ctx, 1, 1 ); feed_agent( &ctx, 2, 1 );
        CHECK( ctx.audit_count==0UL && ctx.agent_held_cnt==2UL, "both agent records are held" );
        CHECK( feed_payment( &ctx, 1 ), "payment 1 is taken" );
        CHECK( ctx.audit_count==3UL && ctx.agent_held_cnt==1UL, "only event 1 is released: event 2 waits for its payment record" );
        CHECK( feed_payment( &ctx, 2 ), "payment 2 is taken" );
        CHECK( event_order_is( &ctx ), "queued-ahead arrival commits in event order" );
        heads[2] = ctx.prev_hash;
    }
    CHECK( heads[0]!=0UL && heads[0]==heads[1] && heads[1]==heads[2], "the chain head must be identical for every arrival order" );
}

static void
test_payment_record_is_held_back_until_the_previous_agent_record_commits( void ) {
    tk_audit_ctx_t ctx; event_ordered_ctx_init( &ctx );
    CHECK( tk_audit_before_frag( &ctx, 0UL, 0UL, TK_LINK_SIG_PAYMENT )==0, "payment 1 is taken at once" );
    CHECK( feed_payment( &ctx, 1 ), "payment 1 commits" );
    CHECK( tk_audit_before_frag( &ctx, 0UL, 0UL, TK_LINK_SIG_PAYMENT )==-1, "payment 2 stays queued upstream" );
    CHECK( tk_audit_before_frag( &ctx, ROLE_MODEL_IN, 0UL, TK_LINK_SIG_MODEL_CALL )==0, "model records are never held back" );
    CHECK( tk_audit_before_frag( &ctx, ROLE_AGENT_IN, 0UL, TK_LINK_SIG_AGENT_AUDIT )==0, "agent records are never held back" );
    CHECK( ctx.audit_count==1UL && ctx.rejected==0UL, "holding a payment record back changes and refuses nothing" );
    feed_agent( &ctx, 1, 0 );
    CHECK( ctx.agent_committed==1UL, "agent record 1 commits (no model record)" );
    CHECK( tk_audit_before_frag( &ctx, 0UL, 0UL, TK_LINK_SIG_PAYMENT )==0, "payment 2 is taken once agent 1 is committed" );
}

static void
test_nothing_is_held_back_without_both_a_payment_chain_and_agent_runs( void ) {
    /* An agent input but no payment input (the agent topology). */
    tk_audit_ctx_t agent_only; ordered_ctx_init( &agent_only );
    agent_only.payment_committed = 5UL;
    CHECK( tk_audit_before_frag( &agent_only, 0UL, 0UL, TK_LINK_SIG_PAYMENT )==0, "no payment input: nothing is held back" );
    feed_agent( &agent_only, 1, 0 );
    CHECK( agent_only.agent_committed==1UL, "an agent record does not wait for a payment record that has no chain" );

    /* A payment input but no agent input (the payment pipeline). */
    tk_audit_ctx_t payments; ctx_init( &payments );
    payments.has_payment_input = 1;
    payments.payment_committed = 5UL;
    CHECK( tk_audit_before_frag( &payments, 0UL, 0UL, TK_LINK_SIG_PAYMENT )==0, "no agent input: payment records commit on arrival" );
}

static void
test_event_count_gate_waits_for_both_streams( void ) {
    tk_audit_ctx_t ctx; event_ordered_ctx_init( &ctx );
    ctx.event_count = 2UL;
    feed_payment( &ctx, 1 ); feed_model( &ctx, 1 ); feed_agent( &ctx, 1, 1 );
    CHECK( ctx.input_exhausted==0, "one event of two is not the end" );
    feed_payment( &ctx, 2 );
    CHECK( ctx.input_exhausted==0 && ctx.payment_committed==2UL && ctx.agent_committed==1UL, "both payment records in, one agent record short: not the end" );
    feed_model( &ctx, 2 ); feed_agent( &ctx, 2, 1 );
    CHECK( ctx.input_exhausted==1, "the last agent record ends the run" );
}

static void
test_wrong_sig_for_role_is_rejected( void ) {
    tk_audit_ctx_t ctx; ordered_ctx_init( &ctx );
    place_payment( ORD_CHUNK_M );
    /* A payment sig on the agent input, and an agent sig on the model input. */
    tk_audit_during_frag( &ctx, ROLE_AGENT_IN, 0UL, TK_LINK_SIG_PAYMENT, ORD_CHUNK_M, sizeof(TkAgentAuditMsg), 0UL );
    CHECK( ctx.stage_valid==0, "a payment sig on the agent input is rejected" );
    tk_audit_during_frag( &ctx, ROLE_MODEL_IN, 0UL, TK_LINK_SIG_AGENT_AUDIT, ORD_CHUNK_M, sizeof(ModelAuditMsg), 0UL );
    CHECK( ctx.stage_valid==0, "an agent sig on the model input is rejected" );
}

int
main( void ) {
    test_each_input_stages_its_own_record();
    test_chunk_range_is_per_input();
    test_input_index_beyond_in_cnt_is_rejected();
    test_stale_stage_is_cleared_first();
    test_after_frag_with_nothing_staged();
    test_ordered_commit_is_independent_of_model_arrival();
    test_chain_is_identical_across_arrival_orders();
    test_watermark_follows_the_commit();
    test_agent_record_without_model_does_not_wait();
    test_late_duplicate_and_out_of_order_are_refused();
    test_hold_bound_is_enforced();
    test_unordered_mode_commits_on_arrival();
    test_event_order_is_independent_of_arrival();
    test_payment_record_is_held_back_until_the_previous_agent_record_commits();
    test_nothing_is_held_back_without_both_a_payment_chain_and_agent_runs();
    test_event_count_gate_waits_for_both_streams();
    test_wrong_sig_for_role_is_rejected();
    if( g_failed ) { fprintf( stderr, "tkaudt DURING_FRAG tests FAILED\n" ); return 1; }
    printf( "all tkaudt DURING_FRAG tests passed\n" );
    return 0;
}
