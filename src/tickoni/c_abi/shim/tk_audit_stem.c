/* tk_audit_stem.c — Stub fd_stem tile for tkaudt.
   Phase 1: counting stub only (no hash chain, no audit record building).

   Goal: wire the stem tile into the pipeline, verify it runs without crashing,
   then incrementally add real audit logic.

   Stub behavior:
   - DURING_FRAG: validate a non-empty fragment, increment audited counter, write to CNC
   - SHOULD_SHUTDOWN: exit on the supervisor's CNC HALT signal
   - No hash chain, no audit event building

   Follows the tk_metric_tile.c pattern:
   - privileged_init / unprivileged_init match Firedancer typedef (2 params)
   - run entry point gets ctx from scratch space
   - fd_stem compiles a tile-specific static run loop
*/

#define _GNU_SOURCE

#include "firedancer.h"
#include "audit_schema.h"

#include "../../../disco/topo/fd_topo.h"

/* We need access to the topo helper function.
   tk_topo_run_tile.c declares tk_topo_find_tile_obj as an extern. */
extern ulong tk_topo_find_tile_obj( fd_topo_t const * topo, ulong tile_id, char const * obj_type );

/* tk_audit_ctx_t MUST be defined BEFORE the STEM_CALLBACK_CONTEXT_TYPE
   macro expansion in fd_stem.c. fd_stem.c uses this type to declare
   'ctx' in its stem_run function, so it must be a complete type at
   the point of the #include. */
typedef struct {
    /* Audit state (stub: just counters) */
    uint64_t audited;           /* Total fragments processed */

    /* CNC reference for shutdown detection and progress reporting */
    void     *cnc;

    /* Scratch-allocated audit records (not yet used in stub, but layout-ready) */
    uint64_t audit_count;
    uint64_t prev_hash;

    /* Tile pointer for allow_shutdown */
    fd_topo_tile_t const *tile;

    /* Scratch-allocated audit record ring buffer pointer.
       Points into scratch space (computed in privileged_init). */
    AuditEvent *audit_records;
} tk_audit_ctx_t;

#define TKAUDT_CTX_ALIGN alignof(tk_audit_ctx_t)
#define TKAUDT_AUDIT_CAPACITY 16384

/* Audit hash seed — initial prev_hash value. */
#define AUDIT_SEED 0xDEADBEEF

/* Forward declarations for Firedancer callback typedefs (2 params each).
   All callback functions MUST be static — they are used by the
   STEM_CALLBACK_* macros which fd_stem.c expands into calls within
   stem_run. If they were non-static, fd_stem.c's implicit declaration
   would conflict with these static definitions.

   DURING_FRAG needs a forward declaration because fd_stem.c calls it
   before the static definition below. privileged_init/unprivileged_init do
   not need forward declarations for the template; Firedancer infrastructure
   calls them directly. */
static void tk_audit_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tk_audit_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tk_audit_during_frag( tk_audit_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig,
                                   ulong chunk, ulong sz, uint ctl );
static void tk_audit_run( fd_topo_t * topo, fd_topo_tile_t * tile );

/* Generate an audit-specific static stem specialization. */
#define STEM_NAME         tkaudt
#define STEM_BURST        (1UL)
#define STEM_LAZY         ((long)10e6)
#define STEM_CALLBACK_CONTEXT_TYPE  tk_audit_ctx_t
#define STEM_CALLBACK_CONTEXT_ALIGN TKAUDT_CTX_ALIGN
#define STEM_CALLBACK_DURING_FRAG   tk_audit_during_frag
#define STEM_CALLBACK_SHOULD_SHUTDOWN(ctx) \
  ( (ctx)->cnc && fd_cnc_signal_query( (fd_cnc_t *)(ctx)->cnc ) == FD_CNC_SIGNAL_HALT )

#include "../../../disco/metrics/fd_metrics.h"
#include "../../../disco/stem/fd_stem.c"

#undef STEM_NAME
#undef STEM_CALLBACK_CONTEXT_TYPE
#undef STEM_CALLBACK_CONTEXT_ALIGN
#undef STEM_CALLBACK_DURING_FRAG
#undef STEM_CALLBACK_SHOULD_SHUTDOWN

/* ─── Scratch footprint ─── */

static ulong
tk_audit_scratch_align( void ) {
    return TKAUDT_CTX_ALIGN;
}

static ulong
tk_audit_scratch_footprint_tile( fd_topo_tile_t const * tile ) {
    (void)tile;
    ulong footprint = fd_alignment( TKAUDT_CTX_ALIGN, sizeof(tk_audit_ctx_t) );
    /* Reserve space for audit records array (not yet used in stub, but layout-ready) */
    footprint += fd_alignment( alignof(AuditEvent), sizeof(AuditEvent) * TKAUDT_AUDIT_CAPACITY );
    return footprint;
}

/* No-argument wrapper — delegates to tk_audit_scratch_footprint_tile( NULL ).
   Provides a thin accessor for topob.c so it never needs the full
   fd_topo_run_tile_t definition. */
ulong
tk_audit_scratch_footprint( void ) {
    return tk_audit_scratch_footprint_tile( NULL );
}

/* ─── Callbacks ───

   privileged_init / unprivileged_init match the Firedancer typedef
   (fd_topo_run_tile_t.privileged_init and .unprivileged_init).
   They take 2 params: (fd_topo_t const *, fd_topo_tile_t const *).

   ctx is retrieved from scratch via fd_topo_obj_laddr(topo, tile->tile_obj_id).
   This matches the tk_metric_tile.c pattern exactly.
*/

static void
tk_audit_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    (void)topo;
    (void)tile;

    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tk_audit_ctx_t * ctx = (tk_audit_ctx_t *)fd_ulong_align_up( (ulong)scratch, TKAUDT_CTX_ALIGN );

    /* Scratch is already zeroed by Firedancer. Initialize explicitly. */
    ctx->audited = 0;
    ctx->cnc = NULL;
    ctx->audit_count = 0;
    ctx->prev_hash = AUDIT_SEED;
    ctx->tile = tile;
    ctx->audit_records = NULL;
}

static void
tk_audit_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    (void)topo;
    (void)tile;

    /* ctx lives in scratch. MUST match stem_run's alignment. */
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tk_audit_ctx_t * ctx = (tk_audit_ctx_t *)fd_ulong_align_up( (ulong)scratch, TKAUDT_CTX_ALIGN );

    /* Find the CNC for this tile and set ctx->cnc for shutdown detection. */
    ulong cnc_obj_id = tk_topo_find_tile_obj( topo, (ulong)tile->id, "cnc" );
    if( cnc_obj_id != ULONG_MAX ) {
        void * cnc_laddr = fd_topo_obj_laddr( (fd_topo_t *)topo, cnc_obj_id );
        ctx->cnc = cnc_laddr;
        FD_LOG_NOTICE(( "tkaudt: stem tile unprivileged init found CNC obj_id=%lu", cnc_obj_id ));
    }
    FD_LOG_NOTICE(( "tkaudt: stem tile unprivileged init, tile_id=%lu cnc=%p",
                    tile->id, ctx->cnc ));
}

static void
tk_audit_during_frag( tk_audit_ctx_t * ctx,
                      ulong            in_idx,
                      ulong            seq,
                      ulong            sig,
                      ulong            chunk,
                      ulong            sz,
                      uint             ctl ) {
    (void)in_idx; (void)seq; (void)sig; (void)chunk; (void)ctl;

    /* This tile is currently a counting stub.  fd_stem validates that the
       fragment fits the input link MTU before invoking this callback. */
    if( FD_UNLIKELY( !sz ) ) {
        FD_LOG_WARNING(( "tkaudt: empty fragment" ));
        return;
    }

    /* Publish progress to CNC app[0] for supervisor snapshots. */
    ctx->audited += 1;
    if( ctx->cnc ) {
        ulong * app = (ulong *)fd_cnc_app_laddr( (fd_cnc_t *)ctx->cnc );
        if( app ) app[0] = ctx->audited;
    }
}

/* ─── Run entry point ───

   This is the tk_audit_run callback. Firedancer infrastructure calls
   privileged_init, then unprivileged_init, then this run function.

   Pattern from tk_metric_tile.c:
   1. Find scratch space via fd_topo_obj_laddr(topo, tile->tile_obj_id)
   2. Cast to ctx type
   3. Find CNC object and set ctx->cnc (for shutdown detection)
   4. Enter the audit-specific tkaudt_run loop
*/

static void
tk_audit_run( fd_topo_t *      topo,
              fd_topo_tile_t * tile ) {
    void * scratch = fd_topo_obj_laddr( topo, tile->tile_obj_id );
    tk_audit_ctx_t * ctx = (tk_audit_ctx_t *)fd_ulong_align_up( (ulong)scratch, TKAUDT_CTX_ALIGN );

    /* The stem shutdown callback reads the tile CNC. */
    ulong cnc_obj_id = tk_topo_find_tile_obj( topo, tile->id, "cnc" );
    if( FD_UNLIKELY( cnc_obj_id==ULONG_MAX ) )
        FD_LOG_ERR(( "tkaudt: CNC object not found for tile %lu", tile->id ));
    ctx->cnc = fd_topo_obj_laddr( topo, cnc_obj_id );

    /* fd_metrics_tl is set by fd_topo_run_tile before this callback. */
    tkaudt_run( topo, tile );
}

/* ─── fd_topo_run_tile_t ─── */

fd_topo_run_tile_t TK_AUDIT_RUN = {
    .name                     = "tkaudt",
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
    .scratch_align            = tk_audit_scratch_align,
    .scratch_footprint        = tk_audit_scratch_footprint_tile,
    .loose_footprint          = NULL,
    .privileged_init          = tk_audit_privileged_init,
    .unprivileged_init        = tk_audit_unprivileged_init,
    .run                      = tk_audit_run,
    .rlimit_file_cnt_fn       = NULL,
};

fd_topo_run_tile_t const *
tk_get_audit_run_tile( void ) {
    return &TK_AUDIT_RUN;
}
