/* tk_diag_stem.c — tkdiag: the diagnostics fd_stem tile.

   tkdiag is Tickoni's counterpart of Firedancer's diag tile
   (src/disco/diag/fd_diag_tile.c), minus everything that is Solana
   (bundle/vote/replay/turbine status) and plus the diagnostic fan-in of
   doc/execution/plans/v2.10-s14-tkdiag-fan-in.md.  Like Firedancer's it has no
   HTTP server of its own: it writes into the metrics regions, and the metric tile
   serves them at /metrics.  It does three things.

   1. Observes every tile (BEFORE_CREDIT, every TKDIAG_REPORT_INTERVAL_NS, never
      sleeping, since the loop must keep draining fragments).  For each tile it
      reads the tile's /proc statistics through tk_os_stats.h and writes the
      OS-level metrics into that tile's metrics region: CPU time by regime,
      page faults, context switches, last CPU and resident memory.  It also
      applies Firedancer's liveness rule (tk_diag_fragment.h, "Tile liveness
      observation"): a tile whose process is gone while its TILE_STATUS gauge is
      not "shutdown" died abnormally, which is logged once as a warning and
      counted in the CrashedTiles metric and CNC slot 0; one that died before it
      ever ran is also counted in SandboxFailures and slot 1.
   2. Receives one diagnostic fragment per pipeline tile over an unreliable link
      (tk_diag_fragment.h) and keeps the latest per input.  DURING_FRAG stages a
      copy (it may be torn); AFTER_FRAG, the first point at which the fragment is
      known intact, offers it to the aggregation.
   3. Reads tkrepl's CNC app slots 0 (replay_checked) and 1 (replay_match), the
      replay result tkrepl publishes, and shuts down once replay_checked is set,
      as the plan's Step 4 describes.  With no tkrepl, or one that has not
      finished, nothing happens: SHOULD_SHUTDOWN is that or CNC HALT.

   The aggregate and the replay result are published as the `tkdiag` metrics kind
   (metrics.xml: TilesReporting, CrashedTiles, SandboxFailures, ReplayChecked,
   ReplayMatch, TotalErrors, TotalAuditRecords, TotalBackpressureWaits,
   MaxQueueDepth, FragmentsAccepted, FragmentsRejected) from STEM_CALLBACK_METRICS_WRITE, and the supervisor reads
   the first five counts from the CNC app slots below.

   Callbacks follow the contract in stem_helpers.h.  AFTER_CREDIT is not defined:
   tkdiag publishes nothing.  DURING_HOUSEKEEPING advances the CNC heartbeat and,
   on the first call, moves the CNC BOOT -> RUN (stem_helpers.h, "CNC liveness").

   Fail-closed wiring (unprivileged_init): tkdiag takes no output link; every
   input must come from a diagnostic producer and be an UNRELIABLE consumer, so a
   slow or halted tkdiag can never backpressure the event path; each input is
   bound to its producer's identity from the topology, and a fragment that
   disagrees with it is refused, not trusted.  With no input links (a topology
   without diagnostic links) it still observes the tiles.

   Sandbox: the /proc descriptors are opened in privileged_init, before the
   sandbox is entered, and listed by populate_allowed_fds so they survive it, as
   Firedancer's diag tile does.  tkdiag has no seccomp policy yet, like every
   other Tickoni tile.

   CNC app slots (declared in tile_registry.zig, the supervisor's reader);
   tkdiag is the only writer of its own CNC:
     slot 0  diag_crashed_tile        tiles that died abnormally or reported a fault
     slot 1  diag_sandbox_failures    tiles that died before they ran
     slot 2  diag_tiles_reporting     inputs with an accepted fragment
     slot 3  diag_fragments_accepted  fragments accepted
     slot 4  diag_fragments_rejected  fragments refused (malformed, wrong sender,
                                      stale or duplicate, bad size or chunk) */

#define _GNU_SOURCE

#include "firedancer.h"
#include "audit_schema.h"
#include "tickoni/c_abi/shim/stem_helpers.h"
#include "tickoni/c_abi/shim/tk_os_stats.h"
#include "tickoni/c_abi/topo_run/tk_diag_stem.h"

#include "disco/metrics/fd_metrics.h"
#include "disco/topo/fd_topo.h"
#include "util/fd_util.h"

#include <string.h>
#include <stddef.h>

#define TKDIAG_SLOT_CRASHED_TILE       0UL
#define TKDIAG_SLOT_SANDBOX_FAILURES   1UL
#define TKDIAG_SLOT_TILES_REPORTING    2UL
#define TKDIAG_SLOT_FRAGS_ACCEPTED     3UL
#define TKDIAG_SLOT_FRAGS_REJECTED     4UL

/* tkrepl's CNC app slots, as tile_registry.zig declares them. */
#define TKREPL_SLOT_REPLAY_CHECKED     0UL
#define TKREPL_SLOT_REPLAY_MATCH       1UL

/* Firedancer's REPORT_INTERVAL_MILLIS. */
#define TKDIAG_REPORT_INTERVAL_NS      (100LL*1000LL*1000LL)

/* How long privileged_init waits for the other tiles to publish their pid.
   Processes start within a second of each other; a tile still without a pid
   after this has not booted, and is reported as having died before it ran. */
#define TKDIAG_BOOT_WAIT_NS            (30LL*1000LL*1000LL*1000LL)

/* Staging verdict of the fragment DURING_FRAG just looked at. */
enum { TKDIAG_STAGE_NONE = 0, TKDIAG_STAGE_OK = 1, TKDIAG_STAGE_BAD = 2 };

/* How tkdiag follows one tile. */
enum {
    TKDIAG_TRACK_NONE  = 0,   /* not followed: the probe could not be opened */
    TKDIAG_TRACK_PROBE = 1,   /* its process is read through `probe` */
    TKDIAG_TRACK_GONE  = 2    /* its process is gone (or never appeared) */
};

typedef struct {
    void *            cnc;
    fd_topo_t const * topo;

    /* Aggregation: the latest fragment per input and everything derived. */
    tkdiag_agg_t      agg;

    /* Staging (written in during_frag, committed in after_frag). */
    int               stage_state;
    diag_fragment_t   staged;

    /* Per-input fragment bounds.  Each input has its own dcache, so its own
       chunk range, and its own workspace join. */
    void *            wksp  [TKDIAG_MAX_INPUTS];
    ulong             chunk0[TKDIAG_MAX_INPUTS];
    ulong             wmark [TKDIAG_MAX_INPUTS];

    /* Observation of every tile (Firedancer's diag tile).  Indexed by
       Firedancer tile index. */
    ulong             tile_cnt;
    ulong             self_idx;
    ulong volatile *  metrics[FD_TOPO_MAX_TILES];
    uint8_t           track  [FD_TOPO_MAX_TILES];
    tk_os_probe_t     probe  [FD_TOPO_MAX_TILES];
    tkdiag_tile_obs_t obs    [FD_TOPO_MAX_TILES];
    ulong             crashed_total;
    ulong             boot_failures;
    long long         next_report_nanos;

    /* tkrepl's CNC app region (NULL without a tkrepl) and what it holds. */
    ulong volatile *  repl_app;
    int               replay_checked;
    int               replay_match;
    int               done;
} tkdiag_ctx_t;

#define TKDIAG_CTX_ALIGN alignof(tkdiag_ctx_t)

static void tkdiag_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tkdiag_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tkdiag_before_credit( tkdiag_ctx_t * ctx, fd_stem_context_t * stem, int * charge_busy );
static void tkdiag_during_frag( tkdiag_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig,
                                ulong chunk, ulong sz, ulong ctl );
static void tkdiag_after_frag( tkdiag_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig,
                               ulong sz, ulong tsorig, ulong tspub, fd_stem_context_t * stem );
static void tkdiag_metrics_write( tkdiag_ctx_t * ctx );
static void tkdiag_run_entry( fd_topo_t * topo, fd_topo_tile_t * tile );

#define STEM_NAME                         tkdiag
#define STEM_BURST                        (1UL)
#define STEM_LAZY                         ((long)10e6)
#define STEM_CALLBACK_CONTEXT_TYPE        tkdiag_ctx_t
#define STEM_CALLBACK_CONTEXT_ALIGN       TKDIAG_CTX_ALIGN
#define STEM_CALLBACK_DURING_HOUSEKEEPING(ctx) stk_cnc_liveness( (ctx)->cnc )
#define STEM_CALLBACK_BEFORE_CREDIT       tkdiag_before_credit
#define STEM_CALLBACK_DURING_FRAG         tkdiag_during_frag
#define STEM_CALLBACK_AFTER_FRAG          tkdiag_after_frag
#define STEM_CALLBACK_METRICS_WRITE       tkdiag_metrics_write
#define STEM_CALLBACK_SHOULD_SHUTDOWN(ctx) \
  ( (ctx)->done || \
    ( (ctx)->cnc && fd_cnc_signal_query( (fd_cnc_t *)(ctx)->cnc ) == FD_CNC_SIGNAL_HALT ) )

#include "disco/stem/fd_stem.c"

#undef STEM_NAME
#undef STEM_CALLBACK_CONTEXT_TYPE
#undef STEM_CALLBACK_CONTEXT_ALIGN
#undef STEM_CALLBACK_DURING_HOUSEKEEPING
#undef STEM_CALLBACK_BEFORE_CREDIT
#undef STEM_CALLBACK_DURING_FRAG
#undef STEM_CALLBACK_AFTER_FRAG
#undef STEM_CALLBACK_METRICS_WRITE
#undef STEM_CALLBACK_SHOULD_SHUTDOWN

/* ─── Scratch layout ─── */

static ulong
tkdiag_scratch_align_tile( void ) {
    return TKDIAG_CTX_ALIGN;
}

static ulong
tkdiag_scratch_footprint_tile( fd_topo_tile_t const * tile ) {
    (void)tile;
    return fd_ulong_align_up( sizeof(tkdiag_ctx_t), TKDIAG_CTX_ALIGN );
}

/* ─── Initialization ─── */

static void
tkdiag_privileged_init( fd_topo_t const *      topo,
                        fd_topo_tile_t const * tile ) {
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkdiag_ctx_t * ctx = STK_GET_CTX(tkdiag_ctx_t, scratch, TKDIAG_CTX_ALIGN);
    memset( ctx, 0, sizeof(*ctx) );

    /* The tile's workspaces are joined before this runs, so the input
       dcaches' workspaces resolve here. */
    if( FD_UNLIKELY( tile->in_cnt>TKDIAG_MAX_INPUTS ) )
        FD_LOG_ERR(( "%s: expected at most %lu diagnostic inputs, found %lu",
                     tile->name, (ulong)TKDIAG_MAX_INPUTS, tile->in_cnt ));
    for( ulong i=0UL; i<tile->in_cnt; i++ )
        ctx->wksp[i] = stk_derive_wksp( topo, tile, i );

    /* Observation of the whole topology, as Firedancer's diag tile does it: open
       every tile's /proc files now, before the sandbox is entered. */
    if( FD_UNLIKELY( topo->tile_cnt>FD_TOPO_MAX_TILES ) )
        FD_LOG_ERR(( "%s: %lu tiles exceed the %lu tkdiag can observe", tile->name, topo->tile_cnt, (ulong)FD_TOPO_MAX_TILES ));
    ctx->tile_cnt = topo->tile_cnt;
    ctx->self_idx = tile->id;

    long long deadline = fd_log_wallclock_nanos() + TKDIAG_BOOT_WAIT_NS;
    for( ulong i=0UL; i<topo->tile_cnt; i++ ) {
        ulong * metrics = fd_metrics_join( fd_topo_obj_laddr( (fd_topo_t *)topo, topo->tiles[i].metrics_obj_id ) );
        if( FD_UNLIKELY( !metrics ) )
            FD_LOG_ERR(( "%s: cannot join the metrics region of tile %lu", tile->name, i ));
        ctx->metrics[i] = fd_metrics_tile( metrics );

        uint64_t pid = 0UL, tid = 0UL;
        if( i==tile->id ) {
            tk_os_self_ids( &pid, &tid );
        } else {
            /* A tile publishes its pid as soon as it starts.  Wait for it, but
               not forever: a tile that never boots must not wedge tkdiag. */
            for(;;) {
                pid = ctx->metrics[i][ FD_METRICS_GAUGE_TILE_PID_OFF ];
                tid = ctx->metrics[i][ FD_METRICS_GAUGE_TILE_TID_OFF ];
                if( pid && tid ) break;
                if( fd_log_wallclock_nanos()>deadline ) { pid = 0UL; tid = 0UL; break; }
                fd_log_sleep( 1000000L );   /* 1 ms */
            }
        }

        if( !pid ) {                          /* never started: reported as died before it ran */
            ctx->track[i] = TKDIAG_TRACK_GONE;
            continue;
        }
        int rc = tk_os_probe_open( &ctx->probe[i], pid, tid );
        if( rc==TK_OS_PROBE_OK )        ctx->track[i] = TKDIAG_TRACK_PROBE;
        else if( rc==TK_OS_PROBE_GONE ) ctx->track[i] = TKDIAG_TRACK_GONE;
        else {
            ctx->track[i] = TKDIAG_TRACK_NONE;
            FD_LOG_WARNING(( "%s: cannot observe tile %s:%lu (pid %lu)", tile->name, topo->tiles[i].name, topo->tiles[i].kind_id, (ulong)pid ));
        }
    }
}

static void
tkdiag_unprivileged_init( fd_topo_t const *      topo,
                          fd_topo_tile_t const * tile ) {
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkdiag_ctx_t * ctx = STK_GET_CTX(tkdiag_ctx_t, scratch, TKDIAG_CTX_ALIGN);

    STK_UNPRIV_INIT(topo, tile, ctx);
    if( FD_UNLIKELY( !ctx->cnc ) )
        FD_LOG_ERR(( "%s: CNC object not found for tile %lu", tile->name, tile->id ));
    /* A collector publishes nothing; a topology that wires a link out of it is
       misconfigured, and the tile refuses to start. */
    if( FD_UNLIKELY( tile->out_cnt ) )
        FD_LOG_ERR(( "%s: collector tile takes no output links, found %lu", tile->name, tile->out_cnt ));

    ctx->topo = topo;
    ctx->next_report_nanos = fd_log_wallclock_nanos();

    /* The replay result lives in tkrepl's CNC app slots.  tkdiag only reads it. */
    for( ulong i=0UL; i<topo->tile_cnt; i++ ) {
        if( strcmp( topo->tiles[i].name, TILE_ID_TKREPL )!=0 ) continue;
        ulong cnc_obj = tk_topo_find_tile_obj( topo, topo->tiles[i].id, "cnc" );
        if( cnc_obj==ULONG_MAX ) break;
        ctx->repl_app = (ulong volatile *)fd_cnc_app_laddr( (fd_cnc_t *)fd_topo_obj_laddr( (fd_topo_t *)topo, cnc_obj ) );
        break;
    }

    if( !tile->in_cnt ) return;   /* no diagnostic links: observation only */

    uint32_t bound_id  [TKDIAG_MAX_INPUTS];
    uint32_t bound_type[TKDIAG_MAX_INPUTS];
    for( ulong i=0UL; i<tile->in_cnt; i++ ) {
        fd_topo_link_t const * in_link = &topo->links[ tile->in_link_id[i] ];

        /* An unreliable consumer is what keeps diagnostics off the event path.
           A reliable one would let a slow or halted tkdiag stall its producer. */
        if( FD_UNLIKELY( tile->in_link_reliable[i] ) )
            FD_LOG_ERR(( "%s: diagnostic input %lu must be an unreliable consumer", tile->name, i ));
        if( FD_UNLIKELY( !ctx->wksp[i] || !in_link->dcache || !in_link->mtu ) )
            FD_LOG_ERR(( "%s: diagnostic input %lu has no joined workspace, dcache or mtu", tile->name, i ));
        if( FD_UNLIKELY( in_link->mtu<sizeof(diag_fragment_t) ) )
            FD_LOG_ERR(( "%s: diagnostic input %lu mtu %lu is below the %lu-byte fragment",
                         tile->name, i, (ulong)in_link->mtu, (ulong)sizeof(diag_fragment_t) ));
        ctx->chunk0[i] = fd_dcache_compact_chunk0( ctx->wksp[i], in_link->dcache );
        ctx->wmark [i] = fd_dcache_compact_wmark ( ctx->wksp[i], in_link->dcache, in_link->mtu );

        /* Bind the input to its producer's identity, from the topology. */
        fd_topo_tile_t const * producer = NULL;
        for( ulong t=0UL; t<topo->tile_cnt && !producer; t++ ) {
            fd_topo_tile_t const * other = &topo->tiles[t];
            for( ulong o=0UL; o<other->out_cnt; o++ )
                if( other->out_link_id[o]==tile->in_link_id[i] ) { producer = other; break; }
        }
        if( FD_UNLIKELY( !producer ) )
            FD_LOG_ERR(( "%s: diagnostic input %lu has no producer in the topology", tile->name, i ));
        bound_type[i] = tk_diag_type_for_tile_name( producer->name );
        if( FD_UNLIKELY( !bound_type[i] ) )
            FD_LOG_ERR(( "%s: diagnostic input %lu comes from %s, which is not a diagnostic producer",
                         tile->name, i, producer->name ));
        bound_id[i] = (uint32_t)producer->id;
    }
    if( FD_UNLIKELY( tkdiag_agg_init( &ctx->agg, tile->in_cnt, bound_id, bound_type ) ) )
        FD_LOG_ERR(( "%s: cannot bind %lu diagnostic inputs (two inputs from one producer type?)",
                     tile->name, tile->in_cnt ));

    FD_LOG_NOTICE(( "%s: unprivileged init tile_id=%lu observed_tiles=%lu diagnostic_inputs=%lu replay_source=%s",
                    tile->name, tile->id, ctx->tile_cnt, tile->in_cnt, ctx->repl_app ? "tkrepl" : "none" ));
}

/* ─── Observation ─── */

/* A counter never goes backwards in Prometheus, else it thinks the application
   restarted (Firedancer's diag tile does the same for idle time). */
static inline void
tkdiag_counter_set( ulong volatile * slot, ulong value ) {
    if( value>*slot ) *slot = value;
}

/* Writes one tile's OS-level statistics into that tile's metrics region. */
static void
tkdiag_write_tile_stats( ulong volatile * m, tk_os_stats_t const * st ) {
    ulong busy = st->user_nanos + st->system_nanos + st->wait_nanos
               + m[ FD_METRICS_COUNTER_TILE_CPU_DURATION_NANOS_INTERRUPT_OFF ];
    tkdiag_counter_set( &m[ FD_METRICS_COUNTER_TILE_CPU_DURATION_NANOS_USER_OFF   ], st->user_nanos );
    tkdiag_counter_set( &m[ FD_METRICS_COUNTER_TILE_CPU_DURATION_NANOS_SYSTEM_OFF ], st->system_nanos );
    tkdiag_counter_set( &m[ FD_METRICS_COUNTER_TILE_CPU_DURATION_NANOS_WAIT_OFF   ], st->wait_nanos );
    tkdiag_counter_set( &m[ FD_METRICS_COUNTER_TILE_CPU_DURATION_NANOS_IDLE_OFF   ],
                        st->lifetime_nanos>busy ? st->lifetime_nanos-busy : 0UL );
    tkdiag_counter_set( &m[ FD_METRICS_COUNTER_TILE_PAGE_FAULT_MINOR_OFF          ], st->minor_faults );
    tkdiag_counter_set( &m[ FD_METRICS_COUNTER_TILE_PAGE_FAULT_MAJOR_OFF          ], st->major_faults );
    tkdiag_counter_set( &m[ FD_METRICS_COUNTER_TILE_CONTEXT_SWITCH_VOLUNTARY_OFF  ], st->voluntary_switches );
    tkdiag_counter_set( &m[ FD_METRICS_COUNTER_TILE_CONTEXT_SWITCH_INVOLUNTARY_OFF], st->involuntary_switches );
    m[ FD_METRICS_GAUGE_TILE_LAST_CPU_OFF       ] = st->last_cpu;
    m[ FD_METRICS_GAUGE_TILE_RESIDENT_BYTES_OFF ] = st->resident_bytes;
}

static void
tkdiag_publish_slots( tkdiag_ctx_t * ctx ) {
    stk_publish_counter( ctx->cnc, TKDIAG_SLOT_CRASHED_TILE,     ctx->crashed_total );
    stk_publish_counter( ctx->cnc, TKDIAG_SLOT_SANDBOX_FAILURES, ctx->boot_failures );
    stk_publish_counter( ctx->cnc, TKDIAG_SLOT_TILES_REPORTING,  ctx->agg.tiles_reporting );
    stk_publish_counter( ctx->cnc, TKDIAG_SLOT_FRAGS_ACCEPTED,   ctx->agg.accepted );
    stk_publish_counter( ctx->cnc, TKDIAG_SLOT_FRAGS_REJECTED,   ctx->agg.rejected );
}

/* One observation of every tile, then the replay result. */
static void
tkdiag_report( tkdiag_ctx_t * ctx ) {
    for( ulong i=0UL; i<ctx->tile_cnt; i++ ) {
        if( ctx->track[i]==TKDIAG_TRACK_NONE ) continue;

        int alive = 1;
        if( ctx->track[i]==TKDIAG_TRACK_PROBE ) {
            tk_os_stats_t st;
            int rc = tk_os_probe_read( &ctx->probe[i], &st );
            if( rc==TK_OS_PROBE_OK ) {
                tkdiag_write_tile_stats( ctx->metrics[i], &st );
            } else if( rc==TK_OS_PROBE_GONE ) {
                tk_os_probe_close( &ctx->probe[i] );
                ctx->track[i] = TKDIAG_TRACK_GONE;
                alive = 0;
            }   /* TK_OS_PROBE_ERROR: unknown this time, so not dead */
        } else {
            alive = 0;
        }

        ulong status = ctx->metrics[i][ FD_METRICS_GAUGE_TILE_STATUS_OFF ];
        if( tkdiag_obs_update( &ctx->obs[i], alive, status ) ) {
            fd_topo_tile_t const * t = &ctx->topo->tiles[i];
            if( ctx->obs[i].never_ran )
                FD_LOG_WARNING(( "tkdiag: tile %s:%lu (index %lu) died before it started running (boot or sandbox entry failed)",
                                 t->name, t->kind_id, i ));
            else
                FD_LOG_WARNING(( "tkdiag: tile %s:%lu (index %lu) died without a clean shutdown (status %lu)",
                                 t->name, t->kind_id, i, status ));
        }
    }
    ctx->crashed_total = tkdiag_crashed_total( &ctx->agg, ctx->obs, ctx->tile_cnt );
    ctx->boot_failures = tkdiag_boot_failures( ctx->obs, ctx->tile_cnt );

    if( ctx->repl_app ) {
        ulong checked = __atomic_load_n( &ctx->repl_app[ TKREPL_SLOT_REPLAY_CHECKED ], __ATOMIC_ACQUIRE );
        ulong match   = __atomic_load_n( &ctx->repl_app[ TKREPL_SLOT_REPLAY_MATCH   ], __ATOMIC_ACQUIRE );
        ctx->replay_match = match!=0UL;
        if( checked && !ctx->replay_checked )
            FD_LOG_NOTICE(( "tkdiag: tkrepl finished its replay check (match=%d), shutting down", ctx->replay_match ));
        ctx->replay_checked = checked!=0UL;
        if( ctx->replay_checked ) ctx->done = 1;
    }

    tkdiag_publish_slots( ctx );
}

/* ─── Callbacks ─── */

/* Firedancer's diag tile sleeps here until the next report is due.  tkdiag
   has inputs to drain, so it only checks the clock. */
static void
tkdiag_before_credit( tkdiag_ctx_t *       ctx,
                      fd_stem_context_t *  stem,
                      int *                charge_busy ) {
    (void)stem;

    long long now = fd_log_wallclock_nanos();
    if( now<ctx->next_report_nanos ) return;
    ctx->next_report_nanos = now + TKDIAG_REPORT_INTERVAL_NS;

    *charge_busy = 1;
    tkdiag_report( ctx );
}

static void
tkdiag_during_frag( tkdiag_ctx_t * ctx,
                    ulong          in_idx,
                    ulong          seq,
                    ulong          sig,
                    ulong          chunk,
                    ulong          sz,
                    ulong          ctl ) {
    (void)seq; (void)sig; (void)ctl;

    /* Clear first: fd_stem may skip AFTER_FRAG for this fragment (reading
       overrun), and a stale verdict would let the next AFTER_FRAG commit an
       abandoned copy. */
    ctx->stage_state = TKDIAG_STAGE_NONE;

    /* Fail closed on a fragment that cannot be read: a wrong size, or a chunk
       outside this input's dcache.  The verdict is committed in AFTER_FRAG. */
    if( FD_UNLIKELY( in_idx>=ctx->agg.in_cnt || sz!=sizeof(diag_fragment_t)
                     || chunk<ctx->chunk0[in_idx] || chunk>ctx->wmark[in_idx] ) ) {
        ctx->stage_state = TKDIAG_STAGE_BAD;
        return;
    }
    memcpy( &ctx->staged, stk_chunk_to_gaddr( ctx->wksp[in_idx], chunk ), sizeof(diag_fragment_t) );
    ctx->stage_state = TKDIAG_STAGE_OK;
}

/* AFTER_FRAG is the commit point: the first callback fd_stem reaches after its
   post-DURING_FRAG overrun re-check, so the only place the staged copy is known
   to be intact.  Counters and the CNC slots are written only here. */
static void
tkdiag_after_frag( tkdiag_ctx_t *      ctx,
                   ulong               in_idx,
                   ulong               seq,
                   ulong               sig,
                   ulong               sz,
                   ulong               tsorig,
                   ulong               tspub,
                   fd_stem_context_t * stem ) {
    (void)seq; (void)sig; (void)sz; (void)tsorig; (void)tspub; (void)stem;

    int state = ctx->stage_state;
    ctx->stage_state = TKDIAG_STAGE_NONE;
    if( state==TKDIAG_STAGE_NONE ) return;

    if( state==TKDIAG_STAGE_OK ) {
        uint64_t crashed_before = ctx->agg.crashed_tiles;
        tkdiag_agg_accept( &ctx->agg, in_idx, &ctx->staged );
        /* A fault report (or its clearing) changes the crashed total at once;
           the periodic report refreshes it otherwise. */
        if( ctx->agg.crashed_tiles!=crashed_before )
            ctx->crashed_total = tkdiag_crashed_total( &ctx->agg, ctx->obs, ctx->tile_cnt );
    } else {
        ctx->agg.rejected = tkdiag_sat_add( ctx->agg.rejected, 1UL );
    }
    tkdiag_publish_slots( ctx );
}

/* Called from stem housekeeping: the tkdiag metrics kind of metrics.xml. */
static void
tkdiag_metrics_write( tkdiag_ctx_t * ctx ) {
    FD_MGAUGE_SET( TKDIAG, TILES_REPORTING,     ctx->agg.tiles_reporting );
    FD_MGAUGE_SET( TKDIAG, CRASHED_TILES,       ctx->crashed_total );
    FD_MGAUGE_SET( TKDIAG, SANDBOX_FAILURES,    ctx->boot_failures );
    FD_MGAUGE_SET( TKDIAG, REPLAY_CHECKED,      (ulong)ctx->replay_checked );
    FD_MGAUGE_SET( TKDIAG, REPLAY_MATCH,        (ulong)ctx->replay_match );
    FD_MGAUGE_SET( TKDIAG, TOTAL_ERRORS,        ctx->agg.total_errors );
    FD_MGAUGE_SET( TKDIAG, TOTAL_AUDIT_RECORDS, ctx->agg.total_audit_records );
    FD_MGAUGE_SET( TKDIAG, TOTAL_BACKPRESSURE_WAITS, ctx->agg.total_backpressure_waits );
    FD_MGAUGE_SET( TKDIAG, MAX_QUEUE_DEPTH,     ctx->agg.max_queue_depth );
    FD_MCNT_SET  ( TKDIAG, FRAGMENTS_ACCEPTED,  ctx->agg.accepted );
    FD_MCNT_SET  ( TKDIAG, FRAGMENTS_REJECTED,  ctx->agg.rejected );
}

/* ─── Sandbox ─── */

/* The descriptors that must survive sandbox entry: stderr, the log file, and
   every /proc file tkdiag keeps open (Firedancer's populate_allowed_fds). */
static ulong
tkdiag_populate_allowed_fds( fd_topo_t const *      topo,
                             fd_topo_tile_t const * tile,
                             ulong                  out_fds_cnt,
                             int *                  out_fds ) {
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkdiag_ctx_t * ctx = STK_GET_CTX(tkdiag_ctx_t, scratch, TKDIAG_CTX_ALIGN);

    ulong cnt = 0UL;
    if( FD_UNLIKELY( out_fds_cnt<2UL ) ) FD_LOG_ERR(( "out_fds_cnt %lu", out_fds_cnt ));
    out_fds[ cnt++ ] = 2; /* stderr */
    if( FD_LIKELY( -1!=fd_log_private_logfile_fd() ) )
        out_fds[ cnt++ ] = fd_log_private_logfile_fd(); /* logfile */

    for( ulong i=0UL; i<ctx->tile_cnt; i++ ) {
        if( ctx->track[i]!=TKDIAG_TRACK_PROBE ) continue;
        int fds[ 2 ];
        ulong n = (ulong)tk_os_probe_fds( &ctx->probe[i], fds, 2UL );
        if( FD_UNLIKELY( cnt+n>out_fds_cnt ) ) FD_LOG_ERR(( "out_fds_cnt %lu", out_fds_cnt ));
        for( ulong j=0UL; j<n; j++ ) out_fds[ cnt++ ] = fds[ j ];
    }
    return cnt;
}

/* ─── Run entry point ─── */

static void
tkdiag_run_entry( fd_topo_t *      topo,
                  fd_topo_tile_t * tile ) {
    tkdiag_run( topo, tile );

    tile->allow_shutdown = 1;
}

/* ─── fd_topo_run_tile_t ─── */

fd_topo_run_tile_t TK_DIAG_RUN = {
    .name                     = TILE_ID_TKDIAG,
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
    .populate_allowed_fds     = tkdiag_populate_allowed_fds,
    .scratch_align            = tkdiag_scratch_align_tile,
    .scratch_footprint        = tkdiag_scratch_footprint_tile,
    .loose_footprint          = NULL,
    .privileged_init          = tkdiag_privileged_init,
    .unprivileged_init        = tkdiag_unprivileged_init,
    .run                      = tkdiag_run_entry,
    .rlimit_file_cnt_fn       = NULL,
};

STK_DEFINE_RUN_TILE_ACCESSORS(
    tk_get_diag,
    TK_DIAG_RUN,
    tkdiag_tile_scratch_align,
    tkdiag_tile_scratch_footprint
)
