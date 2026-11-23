/* test_tkmodl_during_frag.c — DURING_FRAG staging contract for tkmodl.

   Compiles the real tile source into the test, so it calls the real static
   tkmodl_during_frag / tkmodl_after_frag.  A workspace is only a base pointer
   for stk_chunk_to_gaddr, so a plain buffer stands in for the input dcache.
   Governance and result publication need a live stem and are covered by the
   real-process tests; this file proves what DURING_FRAG may and may not do.

   Proves:
   1. A multipart fragment in range is staged verbatim, with its SOM/EOM bits,
      and nothing else changes (no counter, no progress, no output cursor, no
      reassembly state).  Both chunk bounds are inclusive.
   2. DURING_FRAG clears stage_valid FIRST: an invalid fragment following a
      valid, never-committed one (the abandoned-fragment case) leaves nothing
      for AFTER_FRAG to feed.
   3. An empty fragment, one larger than the link MTU, and one below
      in_chunk0 or above in_wmark are each rejected with no state change.
   4. AFTER_FRAG with nothing staged feeds nothing (and never touches the stem,
      so a NULL stem is safe here).
   5. A staged fragment reaches the reassembler in AFTER_FRAG: the first
      fragment of a message leaves it in progress and still counts and answers
      nothing.
*/

#define _GNU_SOURCE

#include "../../c_abi/shim/tk_model_stem.c"

#include <stdio.h>

#define CHUNK_BYTES   ((ulong)FD_CHUNK_ALIGN)
#define IN_CHUNK0     ((ulong)2)
#define IN_WMARK      ((ulong)200)
#define BUF_CHUNKS    ((ulong)400)

static uint8_t g_buf[ 400UL * 64UL ] __attribute__((aligned(64)));
static uint8_t g_rxbuf[ TK_MP_MAX_MESSAGE_BYTES ];
static uint8_t g_txbuf[ TK_MP_MAX_MESSAGE_BYTES ];

static void
ctx_init( tkmodl_ctx_t * ctx ) {
    memset( ctx, 0, sizeof(*ctx) );
    memset( g_buf, 0, sizeof(g_buf) );
    ctx->in.wksp   = g_buf;
    ctx->in.chunk0 = IN_CHUNK0;
    ctx->in.wmark  = IN_WMARK;
    ctx->txbuf     = g_txbuf;
    tk_mp_rx_init( &ctx->rx, TK_MP_DIR_REQUEST, g_rxbuf, TKMODL_PARTIAL_TIMEOUT_NS );
}

/* Everything DURING_FRAG must never change, as one comparison. */
typedef struct {
    uint64_t processed, allowed, denied, dropped;
    int      input_exhausted, tx_active, rx_active;
    ulong    out_chunk[2];
} snapshot_t;

static snapshot_t
snap( tkmodl_ctx_t const * c ) {
    snapshot_t s = { c->processed, c->allowed, c->denied, c->dropped, c->input_exhausted, c->tx_active, c->rx.active,
                     { c->out[0].chunk, c->out[1].chunk } };
    return s;
}

static int
unchanged( tkmodl_ctx_t const * c, snapshot_t const * s ) {
    return c->processed==s->processed && c->allowed==s->allowed && c->denied==s->denied &&
           c->dropped==s->dropped && c->input_exhausted==s->input_exhausted &&
           c->tx_active==s->tx_active && c->rx.active==s->rx_active &&
           c->out[0].chunk==s->out_chunk[0] && c->out[1].chunk==s->out_chunk[1];
}

static int g_failed = 0;
#define CHECK(cond, msg) do { if( !(cond) ) { fprintf( stderr, "FAIL: %s (%s:%d)\n", msg, __FILE__, __LINE__ ); g_failed = 1; } } while(0)

/* A first fragment of a 3-fragment request message, in dcache chunk `chunk`. */
static ulong g_frag_sz;
static void
place_first_fragment( ulong chunk ) {
    static uint8_t msg[ 2UL*TK_MP_FRAG_PAYLOAD_MAX+100UL ];
    memset( msg, 0x5a, sizeof(msg) );
    tk_mp_tx_t tx;
    tk_mp_tx_begin( &tx, TK_MP_DIR_REQUEST, TK_MP_CT_CHAT, 7UL, 9UL, msg, sizeof(msg) );
    uint8_t frag[ TK_MP_LINK_MTU ]; int som, eom;
    g_frag_sz = tk_mp_tx_frag( &tx, frag, &som, &eom );
    memcpy( g_buf + chunk*CHUNK_BYTES, frag, g_frag_sz );
}

static void
frag( tkmodl_ctx_t * ctx, ulong chunk, ulong sz, int som, int eom ) {
    tkmodl_during_frag( ctx, 0UL, 0UL, 0UL, chunk, sz, fd_frag_meta_ctl( 0UL, som, eom, 0 ) );
}

static void
test_valid_is_staged( void ) {
    tkmodl_ctx_t ctx; ctx_init( &ctx );
    place_first_fragment( IN_CHUNK0 );
    snapshot_t s = snap( &ctx );

    frag( &ctx, IN_CHUNK0, g_frag_sz, 1, 0 );
    CHECK( ctx.stage_valid==1, "valid fragment must be staged" );
    CHECK( ctx.stage_sz==g_frag_sz && ctx.stage_som==1 && ctx.stage_eom==0, "staged size and boundary bits" );
    CHECK( memcmp( ctx.stage, g_buf+IN_CHUNK0*CHUNK_BYTES, g_frag_sz )==0, "the staged copy must be the fragment" );
    CHECK( unchanged( &ctx, &s ), "staging must not touch counters/progress/outputs/reassembly" );

    /* Both bounds are inclusive. */
    place_first_fragment( IN_WMARK );
    ctx.stage_valid = 0;
    frag( &ctx, IN_WMARK, g_frag_sz, 1, 0 );
    CHECK( ctx.stage_valid==1, "chunk == in_wmark must be accepted" );
}

static void
test_invalid_cases( void ) {
    struct { char const * name; ulong chunk; ulong sz; } cases[] = {
        { "sz zero",               IN_CHUNK0,     0UL },
        { "sz over the link MTU",  IN_CHUNK0,     (ulong)TK_MP_LINK_MTU+1UL },
        { "chunk below in_chunk0", IN_CHUNK0-1UL, 100UL },
        { "chunk above in_wmark",  IN_WMARK+1UL,  100UL },
    };
    for( ulong i=0UL; i<sizeof(cases)/sizeof(cases[0]); i++ ) {
        tkmodl_ctx_t ctx; ctx_init( &ctx );
        place_first_fragment( IN_CHUNK0 );
        snapshot_t s = snap( &ctx );

        frag( &ctx, cases[i].chunk, cases[i].sz, 1, 0 );
        if( ctx.stage_valid!=0 || !unchanged( &ctx, &s ) )
            fprintf( stderr, "case failed: %s\n", cases[i].name );
        CHECK( ctx.stage_valid==0, "invalid fragment must not be staged" );
        CHECK( unchanged( &ctx, &s ), "invalid fragment must change no counter/progress/output state" );
    }
}

/* The abandoned-fragment case: fd_stem skips AFTER_FRAG when the producer
   overran the reader, so a stale stage_valid would let the NEXT AFTER_FRAG feed
   a fragment from an abandoned read.  DURING_FRAG must clear the flag before it
   validates anything. */
static void
test_stale_stage_is_cleared_first( void ) {
    tkmodl_ctx_t ctx; ctx_init( &ctx );
    place_first_fragment( IN_CHUNK0 );

    frag( &ctx, IN_CHUNK0, g_frag_sz, 1, 0 );          /* staged, never committed */
    CHECK( ctx.stage_valid==1, "precondition: staged" );

    frag( &ctx, IN_WMARK+1UL, g_frag_sz, 1, 0 );       /* next fragment is invalid */
    CHECK( ctx.stage_valid==0, "an invalid fragment must clear a stale staged fragment" );

    snapshot_t s = snap( &ctx );
    tkmodl_after_frag( &ctx, 0UL, 0UL, 0UL, 0UL, 0UL, 0UL, NULL );
    CHECK( unchanged( &ctx, &s ), "AFTER_FRAG after an abandoned fragment must feed nothing" );
}

static void
test_after_frag_with_nothing_staged( void ) {
    tkmodl_ctx_t ctx; ctx_init( &ctx );
    snapshot_t s = snap( &ctx );
    tkmodl_after_frag( &ctx, 0UL, 0UL, 0UL, 0UL, 0UL, 0UL, NULL );
    CHECK( unchanged( &ctx, &s ), "AFTER_FRAG with nothing staged must feed nothing" );
}

static void
test_first_fragment_starts_reassembly_and_answers_nothing( void ) {
    tkmodl_ctx_t ctx; ctx_init( &ctx );
    place_first_fragment( IN_CHUNK0 );
    frag( &ctx, IN_CHUNK0, g_frag_sz, 1, 0 );
    tkmodl_after_frag( &ctx, 0UL, 0UL, 0UL, 0UL, 0UL, 0UL, NULL );   /* partial: no publish, NULL stem is safe */
    CHECK( ctx.rx.active==1, "the first fragment must leave a message in progress" );
    CHECK( ctx.processed==0UL && ctx.allowed==0UL && ctx.denied==0UL, "a partial request is not governed" );
    CHECK( ctx.tx_active==0, "nothing is sent for a partial request" );
}

static void
test_malformed_stream_is_dropped_whole( void ) {
    tkmodl_ctx_t ctx; ctx_init( &ctx );
    place_first_fragment( IN_CHUNK0 );
    /* A continuation with no message in progress is an orphan: counted, never
       governed, audited, or answered. */
    frag( &ctx, IN_CHUNK0, g_frag_sz, 0, 0 );
    tkmodl_after_frag( &ctx, 0UL, 0UL, 0UL, 0UL, 0UL, 0UL, NULL );
    CHECK( ctx.dropped==1UL, "an orphan continuation is counted as dropped" );
    CHECK( ctx.processed==0UL && ctx.tx_active==0, "and nothing is governed or sent" );
}

int
main( void ) {
    test_valid_is_staged();
    test_invalid_cases();
    test_stale_stage_is_cleared_first();
    test_after_frag_with_nothing_staged();
    test_first_fragment_starts_reassembly_and_answers_nothing();
    test_malformed_stream_is_dropped_whole();
    if( g_failed ) { fprintf( stderr, "tkmodl DURING_FRAG tests FAILED\n" ); return 1; }
    printf( "all tkmodl DURING_FRAG tests passed\n" );
    return 0;
}
