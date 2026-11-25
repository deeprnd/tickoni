/* stem_diag.h — producer side of the diagnostic fan-in for the fd_stem tiles
   (the spine tkings, tknorm, tkdedu, tkpoly, tkaudt and the runtime tiles
   tkgate, tkcase, tkdisp, tkagnt, tkmodl).

   A producer's diagnostic link is OPTIONAL: it exists only in a topology that
   wires the tile to tkdiag (paymentPipelineProcess(), investmentWorkflow()).  stk_diag_out_init finds
   it by its consumer's identity, not by position, and leaves `present` at 0 when
   there is none; stk_diag_publish is then a no-op, so the same tile runs
   unchanged in the minimal topologies and in the full workflow.  An all-zero
   stk_diag_out_t is exactly that "no link" state, so a tile context that is
   zeroed and never initialized (a unit-test fixture) never publishes.

   The link is unreliable (see tk_diag_fragment.h and the plan's "Resolved
   Design" 1), so a diagnostic publish draws no flow-control credit:
   fd_stem_publish only charges credits on outputs with a reliable consumer, and
   STEM_BURST therefore stays 1.  The tile's pipeline output is still published
   exactly once per iteration, and the diagnostic fragment is published right
   after it, in AFTER_FRAG (AFTER_CREDIT for tkings), after the tile's own commit and counter publish (the
   callback contract in stem_helpers.h).

   What a fragment carries beyond the tile's own counters:
     backpressure_waits  the tile's TILE_BACKPRESSURE counter, which fd_stem
                         keeps in the tile's metrics region (refreshed at
                         housekeeping, so it can trail by a few milliseconds).
     max_queue_depth     the peak backlog seen on the tile's inputs: how many
                         fragments the producer had published beyond the one
                         just processed.  The producer publishes its sequence to
                         the mcache periodically, so this is a lower bound.
     crashed             1 only on the final fragment of a tile that is about to
                         abort on a fatal fault it detected itself
                         (stk_diag_fault).  A tile killed from outside cannot
                         say so; tkdiag sees that from the process (see
                         tk_diag_fragment.h, "Tile liveness observation").

   Usage (for a consumer tile; tkings publishes from AFTER_CREDIT):
     ctx field:         stk_diag_out_t diag;
     unprivileged_init: stk_diag_out_init( &ctx->diag, topo, tile, 1UL );   // pipeline outputs
     AFTER_FRAG:        stk_diag_publish( &ctx->diag, stem, in_idx, seq, events, errors, 0UL );
     fatal path:        stk_diag_fault( &ctx->diag ); stk_diag_publish( ... ); FD_LOG_ERR(( ... ));

   The including tile MUST #include "audit_schema.h" and "stem_helpers.h" first. */
#ifndef __STEM_DIAG_H__
#define __STEM_DIAG_H__

#include "disco/stem/fd_stem.h"
#include "disco/metrics/fd_metrics.h"
#include "tango/dcache/fd_dcache.h"
#include "tango/mcache/fd_mcache.h"

/* Inputs whose backlog a tile tracks.  tkaudt has the most (one per audit
   producer); eight covers every payment topology. */
#define STK_DIAG_MAX_IN (8UL)

typedef struct {
    int      present;    /* 1 when this tile has a diagnostic link; 0 (the zeroed state) when it has none */
    int      fault;      /* 1 once stk_diag_fault has been called */
    ulong    out_idx;    /* stem output index of the diagnostic link; meaningful only when present */
    stk_link_out_t link; /* the diagnostic link's dcache (stem_helpers.h) */
    uint64_t seq;        /* diag fragments published; the last one's `seq` */
    uint32_t tile_id;
    uint32_t tile_type;

    ulong          in_cnt;                       /* inputs tracked, at most STK_DIAG_MAX_IN */
    ulong const *  in_seq[ STK_DIAG_MAX_IN ];    /* each input mcache's published-sequence cell */
    uint64_t       max_queue_depth;
} stk_diag_out_t;

/* Index of this tile's output link whose consumer is tkdiag, or ULONG_MAX when
   it has none.  Fails closed (FD_LOG_ERR) on more than one.  A tile whose
   pipeline output count depends on the topology (tkagnt, tk_pass_stem.c)
   subtracts this link to get the count it passes to stk_diag_out_init. */
static inline ulong
stk_diag_out_find( fd_topo_t const *       topo,
                   fd_topo_tile_t const *  tile ) {
    ulong found = ULONG_MAX;
    for( ulong o=0UL; o<tile->out_cnt; o++ ) {
        int to_diag = 0;
        for( ulong t=0UL; t<topo->tile_cnt && !to_diag; t++ ) {
            fd_topo_tile_t const * consumer = &topo->tiles[t];
            if( strcmp( consumer->name, TILE_ID_TKDIAG )!=0 ) continue;
            for( ulong j=0UL; j<consumer->in_cnt; j++ )
                if( consumer->in_link_id[j]==tile->out_link_id[o] ) { to_diag = 1; break; }
        }
        if( !to_diag ) continue;
        if( FD_UNLIKELY( found!=ULONG_MAX ) )
            FD_LOG_ERR(( "%s: more than one diagnostic link to tkdiag", tile->name ));
        found = o;
    }
    return found;
}

/* Finds this tile's diagnostic output: the out link whose consumer is tkdiag.
   `pipeline_out_cnt` is the number of pipeline output links the tile has (1 for
   tknorm, tkdedu and tkpoly, 0 for the sink tkaudt).  The tile then has exactly
   that many, plus at most one diagnostic link, which must be its LAST output.
   Also binds the tile's input mcaches for the backlog measurement.

   Fails closed (FD_LOG_ERR) on a malformed wiring: a different number of
   outputs, a diagnostic link anywhere but last, one too small for a fragment or
   without a dcache, or a tile that is not a diagnostic producer.  Call from
   unprivileged_init, after the workspaces are joined. */
static inline void
stk_diag_out_init( stk_diag_out_t *        d,
                   fd_topo_t const *       topo,
                   fd_topo_tile_t const *  tile,
                   ulong                   pipeline_out_cnt ) {
    memset( d, 0, sizeof(*d) );

    ulong diag_o = stk_diag_out_find( topo, tile );
    if( diag_o!=ULONG_MAX ) {
        d->present = 1;
        d->out_idx = diag_o;
    }

    ulong expected_out_cnt = pipeline_out_cnt + ( d->present ? 1UL : 0UL );
    if( FD_UNLIKELY( tile->out_cnt!=expected_out_cnt ) )
        FD_LOG_ERR(( "%s: expected %lu pipeline output link(s) plus an optional diagnostic link, found %lu output link(s)",
                     tile->name, pipeline_out_cnt, tile->out_cnt ));
    if( !d->present ) return;
    if( FD_UNLIKELY( d->out_idx!=pipeline_out_cnt ) )
        FD_LOG_ERR(( "%s: the diagnostic link must be the last output link (index %lu), found at %lu",
                     tile->name, pipeline_out_cnt, d->out_idx ));

    d->tile_type = tk_diag_type_for_tile_name( tile->name );
    if( FD_UNLIKELY( !d->tile_type ) )
        FD_LOG_ERR(( "%s: not a diagnostic producer, but wired to tkdiag", tile->name ));
    d->tile_id = (uint32_t)tile->id;

    stk_link_out_init( &d->link, topo, tile, d->out_idx, (ulong)sizeof(diag_fragment_t) );

    /* The backlog of each input, from its producer's published sequence. */
    if( FD_UNLIKELY( tile->in_cnt>STK_DIAG_MAX_IN ) )
        FD_LOG_ERR(( "%s: %lu inputs exceed the %lu a diagnostic producer tracks",
                     tile->name, tile->in_cnt, STK_DIAG_MAX_IN ));
    for( ulong i=0UL; i<tile->in_cnt; i++ ) {
        fd_topo_link_t const * in = &topo->links[ tile->in_link_id[i] ];
        d->in_seq[i] = in->mcache ? fd_mcache_seq_laddr_const( in->mcache ) : NULL;
    }
    d->in_cnt = tile->in_cnt;
}

/* Marks this tile as about to abort on a fatal fault it detected itself.  The
   next stk_diag_publish carries crashed=1; call it before FD_LOG_ERR. */
static inline void
stk_diag_fault( stk_diag_out_t * d ) {
    d->fault = 1;
}

/* Publishes one diagnostic fragment with the tile's current cumulative
   counters.  `in_idx` and `in_seq` are the input and sequence number of the
   fragment just committed, from which the input backlog is measured.  No-op
   without a diagnostic link.  Call after the tile's committed publish. */
static inline void
stk_diag_publish( stk_diag_out_t *     d,
                  fd_stem_context_t *  stem,
                  ulong                in_idx,
                  ulong                in_seq,
                  uint64_t             events_processed,
                  uint64_t             errors,
                  uint64_t             audit_records ) {
    if( !d->present ) return;

    if( in_idx<d->in_cnt && d->in_seq[in_idx] ) {
        uint64_t backlog = tkdiag_backlog( fd_mcache_seq_query( d->in_seq[in_idx] ), in_seq );
        if( backlog>d->max_queue_depth ) d->max_queue_depth = backlog;
    }

    d->seq += 1UL;
    diag_fragment_t * f = (diag_fragment_t *)stk_link_out_laddr( &d->link );
    memset( f, 0, sizeof(*f) );
    f->tile_id            = d->tile_id;
    f->tile_type          = d->tile_type;
    f->seq                = d->seq;
    f->timestamp_ns       = (uint64_t)tk_monotonic_nanos();
    f->events_processed   = events_processed;
    f->errors             = errors;
    f->backpressure_waits = FD_MCNT_GET( TILE, BACKPRESSURE );
    f->max_queue_depth    = d->max_queue_depth;
    f->audit_records      = audit_records;
    f->crashed            = d->fault;

    stk_link_out_commit( &d->link, stem, d->out_idx, 0UL, sizeof(*f), fd_frag_meta_ctl( 0UL, 1, 1, 0 ) );
}

#endif /* __STEM_DIAG_H__ */
