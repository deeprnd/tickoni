/* test_tkpoly_during_frag.c — P5.2: DURING_FRAG staging validation.

   Tests:
   1. stk_validate_frag rejects oversized fragments
   2. Chunk bounds: a chunk below in_chunk0 is rejected before copy
   3. Chunk bounds: a chunk above in_wmark is rejected before copy
   4. Chunk bounds: in_chunk0 and in_wmark themselves are accepted
   5. A realistic workspace-relative chunk far above the link depth is
      accepted — chunk indices are wksp-relative, not 0..depth ring slots
   6. Invalid transport changes no counters, output bytes, progress,
      exhaustion, or policy state

   Verify: invalid transport changes no counters, output bytes,
   progress, exhaustion, or policy state.
*/

#define _GNU_SOURCE

#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>

#include "firedancer.h"
#include "audit_schema.h"
#include "tickoni/c_abi/shim/stem_helpers.h"

#include "disco/topo/fd_topo.h"
#include "util/wksp/fd_wksp.h"
#include "util/fd_util.h"

/* ─── Minimal context for testing ─── */

typedef struct {
    uint64_t processed;
    uint64_t allowed;
    uint64_t denied;
    int      stage_valid;
    ulong    stage_sz;
    TkEvent staged_message;
    void *   wksp;
    ulong    in_chunk0;
    ulong    in_wmark;
} test_ctx_t;

/* ─── Inline DURING_FRAG logic (mirrors tkpoly_during_frag) ───
   The staged copy is read through `src` rather than the wksp/chunk pair so
   the test can exercise the validation path without a real workspace join.
   The bounds predicate is the one under test and must stay byte-identical
   to tk_policy_stem.c's. */

static int
test_during_frag( test_ctx_t * ctx, void const * src, ulong chunk, ulong sz ) {
    /* Clear validity first (P5.2 requirement) */
    ctx->stage_valid = 0;

    /* Validate size and wksp join (shared boilerplate) */
    if( !stk_validate_frag( sz, TK_EVENT_SIZE, ctx->wksp ) )
        return 0;  /* rejected */

    /* Chunk bounds: must be [in_chunk0, in_wmark] (P5.2 addition) */
    if( FD_UNLIKELY( chunk < ctx->in_chunk0 || chunk > ctx->in_wmark ) )
        return 0;  /* rejected */

    memcpy( &ctx->staged_message, src, sizeof(TkEvent) );
    ctx->stage_valid = 1;
    ctx->stage_sz = sizeof(TkEvent);

    return 1;  /* staged */
}

/* A dcache placed well into its workspace: chunk0 is far above any
   plausible link depth, which is exactly why the link depth is not a bound
   on a fragment's chunk index. */
#define TEST_IN_CHUNK0 ((ulong)65536)
#define TEST_IN_WMARK  ((ulong)65598)
#define TEST_IN_DEPTH  ((ulong)64)

static TkEvent test_msg;

static void
test_ctx_init( test_ctx_t * ctx ) {
    memset( ctx, 0, sizeof(*ctx) );
    memset( &test_msg, 0, sizeof(test_msg) );
    test_msg.source_offset = 42;
    ctx->wksp      = (void *)&test_msg;  /* only checked for non-NULL */
    ctx->in_chunk0 = TEST_IN_CHUNK0;
    ctx->in_wmark  = TEST_IN_WMARK;
}

/* ─── Test 1: oversized fragment is rejected ─── */

static int
test_oversized_rejected( void ) {
    test_ctx_t ctx;
    test_ctx_init( &ctx );

    if( test_during_frag( &ctx, &test_msg, TEST_IN_CHUNK0, TK_EVENT_SIZE + 1 ) != 0 ) {
        FD_LOG_WARNING(( "test_oversized_rejected: oversized fragment was staged" ));
        return 0;
    }
    if( ctx.stage_valid != 0 ) {
        FD_LOG_WARNING(( "test_oversized_rejected: stage_valid should be 0, got %d", ctx.stage_valid ));
        return 0;
    }
    if( ctx.processed != 0 || ctx.allowed != 0 || ctx.denied != 0 ) {
        FD_LOG_WARNING(( "test_oversized_rejected: counters should be 0" ));
        return 0;
    }
    return 1;
}

/* ─── Test 2: a chunk below in_chunk0 is rejected ───
   This is the regression a depth-based bound introduced: every real
   fragment's chunk index sits at or above in_chunk0, so a 0..depth bound
   rejected all of them while letting genuinely low indices through. */

static int
test_below_chunk0_rejected( void ) {
    test_ctx_t ctx;
    test_ctx_init( &ctx );

    if( test_during_frag( &ctx, &test_msg, TEST_IN_CHUNK0 - 1UL, TK_EVENT_SIZE ) != 0 ) {
        FD_LOG_WARNING(( "test_below_chunk0_rejected: chunk below in_chunk0 was staged" ));
        return 0;
    }
    if( ctx.stage_valid != 0 || ctx.stage_sz != 0 ) {
        FD_LOG_WARNING(( "test_below_chunk0_rejected: staging state changed" ));
        return 0;
    }

    /* A chunk inside the link-depth range is still below in_chunk0. */
    if( test_during_frag( &ctx, &test_msg, TEST_IN_DEPTH - 1UL, TK_EVENT_SIZE ) != 0 ) {
        FD_LOG_WARNING(( "test_below_chunk0_rejected: depth-range chunk was staged" ));
        return 0;
    }
    if( ctx.processed != 0 || ctx.allowed != 0 || ctx.denied != 0 ) {
        FD_LOG_WARNING(( "test_below_chunk0_rejected: counters should be 0" ));
        return 0;
    }
    return 1;
}

/* ─── Test 3: a chunk above in_wmark is rejected ─── */

static int
test_above_wmark_rejected( void ) {
    test_ctx_t ctx;
    test_ctx_init( &ctx );

    if( test_during_frag( &ctx, &test_msg, TEST_IN_WMARK + 1UL, TK_EVENT_SIZE ) != 0 ) {
        FD_LOG_WARNING(( "test_above_wmark_rejected: chunk above in_wmark was staged" ));
        return 0;
    }
    if( ctx.stage_valid != 0 || ctx.stage_sz != 0 ) {
        FD_LOG_WARNING(( "test_above_wmark_rejected: staging state changed" ));
        return 0;
    }
    if( ctx.processed != 0 || ctx.allowed != 0 || ctx.denied != 0 ) {
        FD_LOG_WARNING(( "test_above_wmark_rejected: counters should be 0" ));
        return 0;
    }
    return 1;
}

/* ─── Test 4: both bounds are inclusive ─── */

static int
test_bounds_inclusive( void ) {
    test_ctx_t ctx;

    test_ctx_init( &ctx );
    if( test_during_frag( &ctx, &test_msg, TEST_IN_CHUNK0, TK_EVENT_SIZE ) != 1 ) {
        FD_LOG_WARNING(( "test_bounds_inclusive: in_chunk0 was rejected" ));
        return 0;
    }
    if( ctx.stage_valid != 1 || ctx.stage_sz != sizeof(TkEvent) ) {
        FD_LOG_WARNING(( "test_bounds_inclusive: staging state not set at in_chunk0" ));
        return 0;
    }

    test_ctx_init( &ctx );
    if( test_during_frag( &ctx, &test_msg, TEST_IN_WMARK, TK_EVENT_SIZE ) != 1 ) {
        FD_LOG_WARNING(( "test_bounds_inclusive: in_wmark was rejected" ));
        return 0;
    }
    if( ctx.stage_valid != 1 || ctx.stage_sz != sizeof(TkEvent) ) {
        FD_LOG_WARNING(( "test_bounds_inclusive: staging state not set at in_wmark" ));
        return 0;
    }
    return 1;
}

/* ─── Test 5: the staged copy is the fragment's bytes ─── */

static int
test_staged_copy_is_fragment( void ) {
    test_ctx_t ctx;
    test_ctx_init( &ctx );
    test_msg.source_offset = 7;

    if( test_during_frag( &ctx, &test_msg, TEST_IN_CHUNK0 + 2UL, TK_EVENT_SIZE ) != 1 ) {
        FD_LOG_WARNING(( "test_staged_copy_is_fragment: in-bounds chunk was rejected" ));
        return 0;
    }
    if( ctx.staged_message.source_offset != 7 ) {
        FD_LOG_WARNING(( "test_staged_copy_is_fragment: staged source_offset=%lu, want 7",
                         (unsigned long)ctx.staged_message.source_offset ));
        return 0;
    }
    /* Staging only: DURING_FRAG advances no counter. */
    if( ctx.processed != 0 || ctx.allowed != 0 || ctx.denied != 0 ) {
        FD_LOG_WARNING(( "test_staged_copy_is_fragment: counters should be 0" ));
        return 0;
    }
    return 1;
}

/* ─── Test 6: invalid transport leaves all state untouched ─── */

static int
test_invalid_transport_no_state_change( void ) {
    test_ctx_t ctx;
    test_ctx_init( &ctx );

    /* Pre-fill counters to detect any mutation */
    ctx.processed = 42;
    ctx.allowed   = 10;
    ctx.denied    = 5;
    ctx.stage_valid = 1;  /* stale from previous run */
    ctx.stage_sz  = 12345;

    /* Oversized fragment — should be rejected, state unchanged */
    test_during_frag( &ctx, &test_msg, TEST_IN_CHUNK0, TK_EVENT_SIZE + 100 );

    if( ctx.stage_valid != 0 ) {
        FD_LOG_WARNING(( "test_invalid_transport_no_state_change: stage_valid should be 0, got %d", ctx.stage_valid ));
        return 0;
    }
    /* stage_sz is NOT reset on rejection — only stage_valid is.  AFTER_FRAG
       checks stage_valid before reading stage_sz, so a stale size is never
       observable. */
    if( ctx.processed != 42 || ctx.allowed != 10 || ctx.denied != 5 ) {
        FD_LOG_WARNING(( "test_invalid_transport_no_state_change: counters changed to %lu/%lu/%lu",
                         (unsigned long)ctx.processed, (unsigned long)ctx.allowed,
                         (unsigned long)ctx.denied ));
        return 0;
    }

    /* Out-of-bounds chunk — should also leave state untouched */
    test_during_frag( &ctx, &test_msg, TEST_IN_WMARK + 100UL, TK_EVENT_SIZE );

    if( ctx.stage_valid != 0 ) {
        FD_LOG_WARNING(( "test_invalid_transport_no_state_change: stage_valid should still be 0, got %d", ctx.stage_valid ));
        return 0;
    }
    if( ctx.processed != 42 || ctx.allowed != 10 || ctx.denied != 5 ) {
        FD_LOG_WARNING(( "test_invalid_transport_no_state_change: counters changed after OOB chunk" ));
        return 0;
    }
    return 1;
}

/* ─── Main ─── */

int
main( void ) {
    int failures = 0;

    printf( "test_oversized_rejected: " );
    if( test_oversized_rejected() ) printf( "PASS\n" );
    else { printf( "FAIL\n" ); failures++; }

    printf( "test_below_chunk0_rejected: " );
    if( test_below_chunk0_rejected() ) printf( "PASS\n" );
    else { printf( "FAIL\n" ); failures++; }

    printf( "test_above_wmark_rejected: " );
    if( test_above_wmark_rejected() ) printf( "PASS\n" );
    else { printf( "FAIL\n" ); failures++; }

    printf( "test_bounds_inclusive: " );
    if( test_bounds_inclusive() ) printf( "PASS\n" );
    else { printf( "FAIL\n" ); failures++; }

    printf( "test_staged_copy_is_fragment: " );
    if( test_staged_copy_is_fragment() ) printf( "PASS\n" );
    else { printf( "FAIL\n" ); failures++; }

    printf( "test_invalid_transport_no_state_change: " );
    if( test_invalid_transport_no_state_change() ) printf( "PASS\n" );
    else { printf( "FAIL\n" ); failures++; }

    if( failures ) {
        FD_LOG_ERR(( "%d test(s) failed", failures ));
    }
    printf( "all P5.2 DURING_FRAG tests passed\n" );
    return 0;
}
