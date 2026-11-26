/* test_tkrepl_after_frag.c — the replay contract of tkrepl's stem.

   Compiles the real tile source into the test and drives the real static
   tkrepl_during_frag / tkrepl_after_frag.  A plain buffer stands in for the
   workspace that holds the input and output dcaches, a fd_stem_context_t over
   one real mcache (tkaudt) stands in for fd_stem, and a real CNC carries the
   result slots.  The verdict hook is a recording stub: the verdict itself is
   Zig's and is tested in tiles/replay/decision.zig; here the stem must hand the
   hook exactly what it observed and report exactly what the hook decided.

   Proves:
   1. Each capsule event is folded, not decided: count, the first event's case
      id and every later event checked against it (first mismatch position,
      1-based), first and last source offset, and the capsule hash of
      tk_capsule_hash.h.  Nothing is published and the CNC slots stay 0.
   2. The summary asks the hook once, with the summary and that observation.
   3. The verdict goes to tkaudt as one TkReplAuditMsg: RECORD_REPLAY_RESULT,
      the summary's case id, last source offset and trace, capsule_id = the
      summary's capsule hash, the hook's divergences and first position, on
      sig TK_LINK_SIG_REPLAY_AUDIT, one credit (STEM_BURST 1).  CNC slot 1 is
      replay_match and slot 0 replay_checked, and the tile then stops.
   4. A divergent verdict is reported as decided: replay_match 0.
   5. DURING_FRAG stages only, clears a stale stage first, and rejects a wrong
      sig, a wrong size, a fragment that is not whole and a chunk outside the
      input's range; a rejected fragment is counted in AFTER_FRAG; AFTER_FRAG
      with nothing staged does nothing; anything after the verdict is refused.
   6. tkrepl_set_hooks refuses a missing hook.
*/

#define _GNU_SOURCE

#include "../../c_abi/shim/tk_repl_stem.c"

#include "tango/mcache/fd_mcache.h"
#include "tango/cnc/fd_cnc.h"

#include <stdio.h>

#define CHUNK_BYTES   ((ulong)FD_CHUNK_ALIGN)
#define IN_CHUNK0     ((ulong)2)
#define IN_WMARK      ((ulong)18)
#define OUT_CHUNK0    ((ulong)40)
#define OUT_WMARK     ((ulong)140)
#define OUT_DEPTH     64UL
#define BUF_CHUNKS    ((ulong)256)
#define CNC_APP_SZ    64UL

static uint8_t g_buf[ BUF_CHUNKS * 64UL ] __attribute__((aligned(64)));
static uint8_t g_mcache_mem[ FD_MCACHE_FOOTPRINT( OUT_DEPTH, 0UL ) ] __attribute__((aligned(FD_MCACHE_ALIGN)));
static uint8_t g_cnc_mem[ FD_CNC_FOOTPRINT( CNC_APP_SZ ) ] __attribute__((aligned(FD_CNC_ALIGN)));

typedef struct {
    fd_frag_meta_t *  mcaches[1];
    ulong             seqs   [1];
    ulong             depths [1];
    ulong             cr_avail[1];
    ulong             min_cr_avail;
    int               out_reliable[1];
    fd_stem_context_t stem;
} fake_stem_t;

static int g_failed = 0;
#define CHECK(cond, msg) do { if( !(cond) ) { fprintf( stderr, "FAIL: %s (%s:%d)\n", msg, __FILE__, __LINE__ ); g_failed = 1; } } while(0)

/* ─── The recording verdict stub ─── */

static ulong                 g_hook_calls;
static TkReplVerifyQuery     g_hook_query;
static TkReplVerifyDirective g_hook_answer;

static TkReplVerifyDirective
stub_verify( TkReplVerifyQuery const * q ) {
    g_hook_calls += 1UL;
    g_hook_query  = *q;
    return g_hook_answer;
}

static void
fake_stem_init( fake_stem_t * f ) {
    memset( f, 0, sizeof(*f) );
    f->mcaches[0]               = fd_mcache_join( fd_mcache_new( g_mcache_mem, OUT_DEPTH, 0UL, 0UL ) );
    f->depths[0]                = OUT_DEPTH;
    f->cr_avail[0]              = OUT_DEPTH;
    f->out_reliable[0]          = 1;
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
   buffer, with the stub verdict answering `answer`. */
static void
ctx_init( tkrepl_ctx_t * ctx, TkReplVerifyDirective answer ) {
    memset( ctx, 0, sizeof(*ctx) );
    memset( g_buf, 0, sizeof(g_buf) );
    g_hook_calls  = 0UL;
    g_hook_answer = answer;
    memset( &g_hook_query, 0, sizeof(g_hook_query) );
    ctx->hooks.verify  = stub_verify;
    ctx->observed_hash = TK_CAPSULE_HASH_INIT;
    ctx->cnc           = fd_cnc_join( fd_cnc_new( g_cnc_mem, CNC_APP_SZ, 0UL, 0L ) );
    FD_TEST( ctx->cnc );
    ctx->has_input   = 1;
    ctx->in.wksp     = g_buf;
    ctx->in.chunk0   = IN_CHUNK0;
    ctx->in.wmark    = IN_WMARK;
    ctx->out.wksp    = g_buf;
    ctx->out.chunk0  = OUT_CHUNK0;
    ctx->out.wmark   = OUT_WMARK;
    ctx->out.chunk   = OUT_CHUNK0;
}

static ulong
cnc_slot( tkrepl_ctx_t const * ctx, ulong slot ) {
    return ((ulong const *)fd_cnc_app_laddr_const( (fd_cnc_t const *)ctx->cnc ))[ slot ];
}

static TkEvent
capsule_event( uint64_t offset, uint64_t case_id ) {
    TkEvent ev;
    memset( &ev, 0, sizeof(ev) );
    ev.version         = TK_EVENT_WIRE_VERSION;
    ev.kind            = TK_EVENT_KIND_AGENT_REQUEST;
    ev.source          = TK_EVENT_SOURCE_TKGATE;
    ev.pipeline_hops   = 4;
    ev.trace_id[0]     = (uint8_t)(0x40 + offset);
    ev.idempotency_key = 1000UL + offset;
    ev.source_offset   = offset;
    ev.event_hash      = 0xabc0UL + offset;
    ev.case_id         = case_id;
    return ev;
}

static TkCaseCapsuleMsg
summary_of( uint64_t case_id, uint64_t n, uint64_t hash ) {
    TkCaseCapsuleMsg m;
    memset( &m, 0, sizeof(m) );
    m.version             = TK_REPL_WIRE_VERSION;
    m.case_id             = case_id;
    m.event_count         = n;
    m.first_source_offset = 0UL;
    m.last_source_offset  = n-1UL;
    m.capsule_hash        = hash;
    m.trace_id[0]         = (uint8_t)(0x40 + n - 1UL);
    return m;
}

/* Places `bytes` in the input dcache and runs it through DURING_FRAG and
   AFTER_FRAG, as fd_stem does for an intact, whole fragment. */
static void
feed( tkrepl_ctx_t * ctx, fake_stem_t * f, ulong sig, void const * bytes, ulong sz ) {
    memcpy( g_buf + IN_CHUNK0*CHUNK_BYTES, bytes, sz );
    ulong ctl = fd_frag_meta_ctl( 0UL, 1, 1, 0 );
    tkrepl_during_frag( ctx, 0UL, 0UL, sig, IN_CHUNK0, sz, ctl );
    tkrepl_after_frag( ctx, 0UL, 0UL, sig, sz, 0UL, 0UL, &f->stem );
}

static uint64_t
fold_hash( uint64_t case_id, uint64_t n ) {
    uint64_t h = TK_CAPSULE_HASH_INIT;
    for( uint64_t i=0UL; i<n; i++ ) {
        TkEvent ev = capsule_event( i, case_id );
        h = tk_capsule_hash_append( h, &ev );
    }
    return h;
}

static TkReplVerifyDirective
answer( uint64_t divergences, uint64_t first_seq, uint8_t field ) {
    TkReplVerifyDirective d;
    memset( &d, 0, sizeof(d) );
    d.divergences         = divergences;
    d.first_divergent_seq = first_seq;
    d.first_field         = field;
    return d;
}

static void
test_events_are_folded_not_decided( void ) {
    tkrepl_ctx_t ctx; fake_stem_t f; fake_stem_init( &f ); ctx_init( &ctx, answer( 0UL, 0UL, 0 ) );
    for( uint64_t i=0UL; i<3UL; i++ ) {
        TkEvent ev = capsule_event( i, i==2UL ? 0x99UL : 0x5eedUL );   /* the third is attached to another case */
        feed( &ctx, &f, TK_LINK_SIG_EVENT, &ev, sizeof(ev) );
    }
    CHECK( ctx.observed_count==3UL, "every event is folded" );
    CHECK( ctx.observed_case_id==0x5eedUL, "the observed case is the first event's" );
    CHECK( ctx.case_id_mismatches==1UL && ctx.first_case_id_mismatch_seq==3UL, "a later event of another case is counted at its 1-based position" );
    CHECK( ctx.observed_first_source_offset==0UL && ctx.observed_last_source_offset==2UL, "first and last source offset" );
    uint64_t h = TK_CAPSULE_HASH_INIT;
    for( uint64_t i=0UL; i<3UL; i++ ) { TkEvent ev = capsule_event( i, i==2UL ? 0x99UL : 0x5eedUL ); h = tk_capsule_hash_append( h, &ev ); }
    CHECK( ctx.observed_hash==h, "the capsule hash is the chain of tk_capsule_hash.h" );
    CHECK( g_hook_calls==0UL && f.seqs[0]==0UL, "no verdict and no publish before the summary" );
    CHECK( cnc_slot( &ctx, 0UL )==0UL && cnc_slot( &ctx, 1UL )==0UL && !ctx.replay_checked, "the result slots stay 0" );
    CHECK( !tkrepl_should_shutdown( &ctx ), "the tile keeps running until its verdict" );
}

static void
test_the_summary_is_verified_and_reported_to_tkaudt( void ) {
    tkrepl_ctx_t ctx; fake_stem_t f; fake_stem_init( &f ); ctx_init( &ctx, answer( 0UL, 0UL, 0 ) );
    for( uint64_t i=0UL; i<4UL; i++ ) {
        TkEvent ev = capsule_event( i, 0x5eedUL );
        feed( &ctx, &f, TK_LINK_SIG_EVENT, &ev, sizeof(ev) );
    }
    TkCaseCapsuleMsg s = summary_of( 0x5eedUL, 4UL, fold_hash( 0x5eedUL, 4UL ) );
    feed( &ctx, &f, TK_LINK_SIG_CASE_CAPSULE, &s, sizeof(s) );

    CHECK( g_hook_calls==1UL, "the verdict is asked once" );
    CHECK( !memcmp( &g_hook_query.summary, &s, sizeof(s) ), "with the summary as received" );
    CHECK( g_hook_query.observed_count==4UL && g_hook_query.observed_case_id==0x5eedUL &&
           g_hook_query.observed_first_source_offset==0UL && g_hook_query.observed_last_source_offset==3UL &&
           g_hook_query.observed_hash==fold_hash( 0x5eedUL, 4UL ) &&
           g_hook_query.case_id_mismatches==0UL && g_hook_query.first_case_id_mismatch_seq==0UL,
           "and the observation as folded" );

    CHECK( f.seqs[0]==1UL, "one record to tkaudt" );
    CHECK( f.cr_avail[0]==OUT_DEPTH-1UL, "one credit: within STEM_BURST" );
    fd_frag_meta_t const * meta = f.mcaches[0] + fd_mcache_line_idx( 0UL, OUT_DEPTH );
    CHECK( meta->sig==TK_LINK_SIG_REPLAY_AUDIT && meta->sz==sizeof(TkReplAuditMsg), "a whole TkReplAuditMsg on its sig" );
    CHECK( meta->chunk>=OUT_CHUNK0 && meta->chunk<=OUT_WMARK, "written into the output's dcache" );
    TkReplAuditMsg const * m = (TkReplAuditMsg const *)( g_buf + meta->chunk*CHUNK_BYTES );
    CHECK( m->version==TK_REPL_WIRE_VERSION && m->record_type==RECORD_REPLAY_RESULT, "a replay result record" );
    CHECK( m->case_id==0x5eedUL && m->source_offset==3UL && m->trace_id[0]==s.trace_id[0], "for the summary's case, last offset and trace" );
    CHECK( m->payload.capsule_id==s.capsule_hash, "capsule_id is the capsule's content hash" );
    CHECK( m->payload.divergences==0UL && m->payload.first_divergent_seq==0UL, "the verdict as decided" );

    CHECK( ctx.replay_checked==1 && ctx.replay_match==1, "checked and matching" );
    CHECK( cnc_slot( &ctx, 1UL )==1UL && cnc_slot( &ctx, 0UL )==1UL, "CNC slot 1 replay_match, slot 0 replay_checked" );
    CHECK( tkrepl_should_shutdown( &ctx ), "the tile stops after its one verdict" );

    /* Nothing after the verdict. */
    TkEvent late = capsule_event( 4UL, 0x5eedUL );
    feed( &ctx, &f, TK_LINK_SIG_EVENT, &late, sizeof(late) );
    feed( &ctx, &f, TK_LINK_SIG_CASE_CAPSULE, &s, sizeof(s) );
    CHECK( ctx.observed_count==4UL && g_hook_calls==1UL && f.seqs[0]==1UL && ctx.rejected==2UL, "anything after the verdict is refused and counted" );
}

static void
test_a_divergent_verdict_is_reported_as_decided( void ) {
    tkrepl_ctx_t ctx; fake_stem_t f; fake_stem_init( &f );
    ctx_init( &ctx, answer( 2UL, 3UL, TK_REPL_FIELD_CAPSULE_HASH ) );
    TkEvent ev = capsule_event( 0UL, 0x5eedUL );
    feed( &ctx, &f, TK_LINK_SIG_EVENT, &ev, sizeof(ev) );
    TkCaseCapsuleMsg s = summary_of( 0x5eedUL, 2UL, 0x1234UL );
    feed( &ctx, &f, TK_LINK_SIG_CASE_CAPSULE, &s, sizeof(s) );
    fd_frag_meta_t const * meta = f.mcaches[0] + fd_mcache_line_idx( 0UL, OUT_DEPTH );
    TkReplAuditMsg const * m = (TkReplAuditMsg const *)( g_buf + meta->chunk*CHUNK_BYTES );
    CHECK( m->payload.divergences==2UL && m->payload.first_divergent_seq==3UL, "the divergences and first position the verdict decided" );
    CHECK( ctx.replay_checked==1 && ctx.replay_match==0, "checked, not matching" );
    CHECK( cnc_slot( &ctx, 1UL )==0UL && cnc_slot( &ctx, 0UL )==1UL, "CNC slot 1 is 0, slot 0 is 1" );
    CHECK( ctx.verdict.first_field==TK_REPL_FIELD_CAPSULE_HASH, "the verdict is kept for the accessors" );
}

static void
test_during_frag_stages_only_and_rejects_bad_fragments( void ) {
    tkrepl_ctx_t ctx; fake_stem_t f; fake_stem_init( &f ); ctx_init( &ctx, answer( 0UL, 0UL, 0 ) );
    TkEvent ev = capsule_event( 0UL, 0x5eedUL );
    memcpy( g_buf + IN_CHUNK0*CHUNK_BYTES, &ev, sizeof(ev) );
    ulong whole = fd_frag_meta_ctl( 0UL, 1, 1, 0 );

    tkrepl_during_frag( &ctx, 0UL, 0UL, TK_LINK_SIG_EVENT, IN_CHUNK0, TK_EVENT_SIZE, whole );
    CHECK( ctx.stage_kind==TKREPL_STAGE_EVENT, "a well-formed event is staged" );
    CHECK( ctx.observed_count==0UL && ctx.observed_hash==TK_CAPSULE_HASH_INIT && f.seqs[0]==0UL, "staging folds and publishes nothing" );

    /* The abandoned-fragment case: an out-of-range fragment after a valid,
       never-committed one leaves nothing to commit. */
    tkrepl_during_frag( &ctx, 0UL, 0UL, TK_LINK_SIG_EVENT, IN_WMARK+1UL, TK_EVENT_SIZE, whole );
    CHECK( ctx.stage_kind==TKREPL_STAGE_NONE, "a chunk above the input range clears the stale stage" );
    tkrepl_after_frag( &ctx, 0UL, 0UL, 0UL, 0UL, 0UL, 0UL, &f.stem );
    CHECK( ctx.observed_count==0UL && ctx.rejected==0UL && f.seqs[0]==0UL, "AFTER_FRAG with nothing staged does nothing" );

    tkrepl_during_frag( &ctx, 0UL, 0UL, TK_LINK_SIG_EVENT, IN_CHUNK0-1UL, TK_EVENT_SIZE, whole );
    CHECK( ctx.stage_kind==TKREPL_STAGE_NONE, "a chunk below the input range is not read" );

    tkrepl_during_frag( &ctx, 0UL, 0UL, TK_LINK_SIG_CASE_AUDIT, IN_CHUNK0, TK_EVENT_SIZE, whole );
    CHECK( ctx.stage_kind==TKREPL_STAGE_REJECT, "an unknown sig is rejected" );
    tkrepl_during_frag( &ctx, 0UL, 0UL, TK_LINK_SIG_EVENT, IN_CHUNK0, TK_EVENT_SIZE-1UL, whole );
    CHECK( ctx.stage_kind==TKREPL_STAGE_REJECT, "a short event is rejected" );
    tkrepl_during_frag( &ctx, 0UL, 0UL, TK_LINK_SIG_CASE_CAPSULE, IN_CHUNK0, TK_EVENT_SIZE, whole );
    CHECK( ctx.stage_kind==TKREPL_STAGE_REJECT, "a summary of the wrong size is rejected" );
    tkrepl_during_frag( &ctx, 0UL, 0UL, TK_LINK_SIG_EVENT, IN_CHUNK0, TK_EVENT_SIZE, fd_frag_meta_ctl( 0UL, 1, 0, 0 ) );
    CHECK( ctx.stage_kind==TKREPL_STAGE_REJECT, "a fragment that is not whole is rejected" );
    tkrepl_after_frag( &ctx, 0UL, 0UL, 0UL, 0UL, 0UL, 0UL, &f.stem );
    CHECK( ctx.rejected==1UL && ctx.observed_count==0UL && f.seqs[0]==0UL, "a rejected fragment is counted, never folded" );

    tkrepl_during_frag( &ctx, 0UL, 0UL, TK_LINK_SIG_EVENT, IN_WMARK, TK_EVENT_SIZE, whole );
    CHECK( ctx.stage_kind==TKREPL_STAGE_EVENT, "the input range is inclusive at its watermark" );
}

static void
test_a_missing_hook_is_refused( void ) {
    TkReplHooks none;
    memset( &none, 0, sizeof(none) );
    CHECK( tkrepl_set_hooks( NULL )!=0, "no hook table is refused" );
    CHECK( tkrepl_set_hooks( &none )!=0, "a table without verify is refused" );
    TkReplHooks some = { .verify = stub_verify };
    CHECK( tkrepl_set_hooks( &some )==0 && tkrepl_hooks_set, "a verify hook is registered" );
}

int
main( void ) {
    test_events_are_folded_not_decided();
    test_the_summary_is_verified_and_reported_to_tkaudt();
    test_a_divergent_verdict_is_reported_as_decided();
    test_during_frag_stages_only_and_rejects_bad_fragments();
    test_a_missing_hook_is_refused();
    if( g_failed ) { fprintf( stderr, "tkrepl AFTER_FRAG tests FAILED\n" ); return 1; }
    printf( "all tkrepl AFTER_FRAG tests passed\n" );
    return 0;
}
