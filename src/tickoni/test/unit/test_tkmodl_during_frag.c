/* test_tkmodl_during_frag.c — DURING_FRAG staging contract for tkmodl.

   Unlike the older tkpoly test (which mirrors the callback inline), this file
   compiles the real tile source into the test, so it calls the real static
   tkmodl_during_frag / tkmodl_after_frag.  A workspace is only a base pointer
   for stk_chunk_to_gaddr, so a plain buffer stands in for the input dcache.

   Proves:
   1. A well-formed request in range is staged and nothing else changes.
   2. DURING_FRAG clears stage_valid FIRST: an invalid fragment following a
      valid, never-committed one (the abandoned-fragment case) leaves nothing
      for AFTER_FRAG to commit.
   3. Wrong size, chunk below in_chunk0, chunk above in_wmark, wrong wire
      version, bad replay_mode, and an unterminated string field are each
      rejected with no counter, progress, exhaustion, or output change.
   4. AFTER_FRAG with nothing staged commits nothing (and never touches the
      stem, so a NULL stem is safe here).
*/

#define _GNU_SOURCE

#include "../../c_abi/shim/tk_model_stem.c"

#include <stdio.h>

#define CHUNK_BYTES   ((ulong)FD_CHUNK_ALIGN)
#define IN_CHUNK0     ((ulong)2)
#define IN_WMARK      ((ulong)10)
#define BUF_CHUNKS    ((ulong)32)

static uint8_t g_buf[ 32UL * 64UL ] __attribute__((aligned(64)));

static void
make_good_request( ModelRequestMsg * r ) {
    memset( r, 0, sizeof(*r) );
    r->version     = TKMODL_WIRE_VERSION;
    r->replay_mode = TKMODL_REPLAY_MODE_REPLAY;
    r->request_id  = 1;
    r->replay_substitution_id = 7;
    strcpy( (char *)r->model_id,               "fixture.model" );
    strcpy( (char *)r->actor_role,             "ops_reviewer" );
    strcpy( (char *)r->workflow,               "trading_control" );
    strcpy( (char *)r->capability,             "trading_order.propose" );
    strcpy( (char *)r->capability_envelope_id, "capenv.fixture" );
    strcpy( (char *)r->policy_version,         "v1" );
    strcpy( (char *)r->budget_id,              "budget.fixture" );
}

static void
ctx_init( tkmodl_ctx_t * ctx ) {
    memset( ctx, 0, sizeof(*ctx) );
    memset( g_buf, 0, sizeof(g_buf) );
    ctx->wksp      = g_buf;
    ctx->in_chunk0 = IN_CHUNK0;
    ctx->in_wmark  = IN_WMARK;
}

/* Everything DURING_FRAG must never change, as one comparison. */
typedef struct {
    uint64_t processed, allowed, denied;
    int      input_exhausted;
    ulong    out_chunk[2];
} snapshot_t;

static snapshot_t
snap( tkmodl_ctx_t const * c ) {
    snapshot_t s = { c->processed, c->allowed, c->denied, c->input_exhausted,
                     { c->out_chunk[0], c->out_chunk[1] } };
    return s;
}

static int
unchanged( tkmodl_ctx_t const * c, snapshot_t const * s ) {
    return c->processed==s->processed && c->allowed==s->allowed && c->denied==s->denied &&
           c->input_exhausted==s->input_exhausted &&
           c->out_chunk[0]==s->out_chunk[0] && c->out_chunk[1]==s->out_chunk[1];
}

static int g_failed = 0;
#define CHECK(cond, msg) do { if( !(cond) ) { fprintf( stderr, "FAIL: %s (%s:%d)\n", msg, __FILE__, __LINE__ ); g_failed = 1; } } while(0)

static void
place( ModelRequestMsg const * r, ulong chunk ) {
    memcpy( g_buf + chunk*CHUNK_BYTES, r, sizeof(*r) );
}

static void
frag( tkmodl_ctx_t * ctx, ulong chunk, ulong sz ) {
    tkmodl_during_frag( ctx, 0UL, 0UL, 0UL, chunk, sz, 0UL );
}

static void
test_valid_is_staged( void ) {
    tkmodl_ctx_t ctx; ctx_init( &ctx );
    ModelRequestMsg r; make_good_request( &r ); place( &r, IN_CHUNK0 );
    snapshot_t s = snap( &ctx );

    frag( &ctx, IN_CHUNK0, sizeof(ModelRequestMsg) );
    CHECK( ctx.stage_valid==1, "valid request must be staged" );
    CHECK( ctx.staged_request.request_id==1, "staged copy must hold the request" );
    CHECK( unchanged( &ctx, &s ), "staging must not touch counters/progress/outputs" );

    /* Both bounds are inclusive. */
    place( &r, IN_WMARK );
    ctx.stage_valid = 0;
    frag( &ctx, IN_WMARK, sizeof(ModelRequestMsg) );
    CHECK( ctx.stage_valid==1, "chunk == in_wmark must be accepted" );
}

static void
test_invalid_cases( void ) {
    ModelRequestMsg good; make_good_request( &good );

    struct { char const * name; ulong chunk; ulong sz; int mutate; } cases[] = {
        { "sz too small",          IN_CHUNK0,     sizeof(ModelRequestMsg)-1UL, 0 },
        { "sz too large",          IN_CHUNK0,     sizeof(ModelRequestMsg)+1UL, 0 },
        { "sz zero",               IN_CHUNK0,     0UL,                         0 },
        { "chunk below in_chunk0", IN_CHUNK0-1UL, sizeof(ModelRequestMsg),     0 },
        { "chunk above in_wmark",  IN_WMARK+1UL,  sizeof(ModelRequestMsg),     0 },
        { "wrong wire version",    IN_CHUNK0,     sizeof(ModelRequestMsg),     1 },
        { "bad replay_mode",       IN_CHUNK0,     sizeof(ModelRequestMsg),     2 },
        { "unterminated model_id", IN_CHUNK0,     sizeof(ModelRequestMsg),     3 },
        { "unterminated budget_id",IN_CHUNK0,     sizeof(ModelRequestMsg),     4 },
    };
    for( ulong i=0UL; i<sizeof(cases)/sizeof(cases[0]); i++ ) {
        tkmodl_ctx_t ctx; ctx_init( &ctx );
        ModelRequestMsg r = good;
        if( cases[i].mutate==1 ) r.version = TKMODL_WIRE_VERSION + 1;
        if( cases[i].mutate==2 ) r.replay_mode = 2;
        if( cases[i].mutate==3 ) memset( r.model_id, 'x', sizeof(r.model_id) );
        if( cases[i].mutate==4 ) memset( r.budget_id, 'x', sizeof(r.budget_id) );
        place( &r, IN_CHUNK0 );
        snapshot_t s = snap( &ctx );

        frag( &ctx, cases[i].chunk, cases[i].sz );
        if( ctx.stage_valid!=0 || !unchanged( &ctx, &s ) )
            fprintf( stderr, "case failed: %s\n", cases[i].name );
        CHECK( ctx.stage_valid==0, "invalid fragment must not be staged" );
        CHECK( unchanged( &ctx, &s ), "invalid fragment must change no counter/progress/output state" );
    }
}

/* The abandoned-fragment case: fd_stem skips AFTER_FRAG when the producer
   overran the reader, so a stale stage_valid would let the NEXT AFTER_FRAG
   commit a request built from an abandoned read.  DURING_FRAG must clear the
   flag before it validates anything. */
static void
test_stale_stage_is_cleared_first( void ) {
    tkmodl_ctx_t ctx; ctx_init( &ctx );
    ModelRequestMsg r; make_good_request( &r ); place( &r, IN_CHUNK0 );

    frag( &ctx, IN_CHUNK0, sizeof(ModelRequestMsg) );   /* staged, never committed */
    CHECK( ctx.stage_valid==1, "precondition: staged" );

    frag( &ctx, IN_WMARK+1UL, sizeof(ModelRequestMsg) ); /* next fragment is invalid */
    CHECK( ctx.stage_valid==0, "an invalid fragment must clear a stale staged request" );

    snapshot_t s = snap( &ctx );
    tkmodl_after_frag( &ctx, 0UL, 0UL, 0UL, 0UL, 0UL, 0UL, NULL );
    CHECK( unchanged( &ctx, &s ), "AFTER_FRAG after an abandoned fragment must commit nothing" );
}

static void
test_after_frag_with_nothing_staged( void ) {
    tkmodl_ctx_t ctx; ctx_init( &ctx );
    snapshot_t s = snap( &ctx );
    tkmodl_after_frag( &ctx, 0UL, 0UL, 0UL, 0UL, 0UL, 0UL, NULL );
    CHECK( unchanged( &ctx, &s ), "AFTER_FRAG with nothing staged must commit nothing" );
}

int
main( void ) {
    test_valid_is_staged();
    test_invalid_cases();
    test_stale_stage_is_cleared_first();
    test_after_frag_with_nothing_staged();
    if( g_failed ) { fprintf( stderr, "tkmodl DURING_FRAG tests FAILED\n" ); return 1; }
    printf( "all tkmodl DURING_FRAG tests passed\n" );
    return 0;
}
