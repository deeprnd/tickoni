/* tk_diag_stem.c — tkdiag: the minimal observer fd_stem tile.
 *
 * tkdiag has 0 input links and 0 output links.  It owns no fragment I/O at all,
 * so it defines only BEFORE_CREDIT (no DURING_FRAG, AFTER_FRAG or AFTER_CREDIT)
 * and never publishes.  Unlike the metric tile it has no Firedancer backend to
 * delegate to, so the stem specialization below is its own.
 *
 *   BEFORE_CREDIT    publishes the two diagnostic counters to this tile's CNC
 *                    app slots.
 *   SHOULD_SHUTDOWN  CNC HALT only, like the metric tile (the other 0-input
 *                    observer).  There is no event count to exhaust, and an
 *                    iteration-count bound is not a duration: a 0-input stem
 *                    loop spins, so it would stop the tile almost immediately.
 *
 * CNC app slots (declared in tile_registry.zig, the supervisor's reader):
 *   slot 0  diag_crashed_tile
 *   slot 1  diag_sandbox_failures
 * tkdiag is the only writer of its own CNC.  Both slots hold 0 for now: reading
 * the real values needs the supervisor to wire shared diagnostic state into this
 * tile's workspace, which is future work (see the migration plan).
 *
 * No /proc reads, no file or network I/O: cross-platform by design.
 *
 * Follows the fd_stem callback contract in stem_helpers.h; with no fragment
 * input there is no DURING_FRAG/AFTER_FRAG split to observe.
 */

#define _GNU_SOURCE

#include "firedancer.h"
#include "audit_schema.h"
#include "tickoni/c_abi/shim/stem_helpers.h"
#include "tickoni/c_abi/topo_run/tk_diag_stem.h"

#include "disco/topo/fd_topo.h"
#include "util/fd_util.h"

#include <string.h>
#include <stddef.h>

#define TKDIAG_SLOT_CRASHED_TILE      0UL
#define TKDIAG_SLOT_SANDBOX_FAILURES  1UL

typedef struct {
    void * cnc;
} tkdiag_ctx_t;

#define TKDIAG_CTX_ALIGN alignof(tkdiag_ctx_t)

static void tkdiag_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tkdiag_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tkdiag_before_credit( tkdiag_ctx_t * ctx, fd_stem_context_t * stem, int * charge_busy );
static void tkdiag_run_entry( fd_topo_t * topo, fd_topo_tile_t * tile );

#define STEM_NAME                         tkdiag
#define STEM_BURST                        (1UL)
#define STEM_LAZY                         ((long)10e6)
#define STEM_CALLBACK_CONTEXT_TYPE        tkdiag_ctx_t
#define STEM_CALLBACK_CONTEXT_ALIGN       TKDIAG_CTX_ALIGN
#define STEM_CALLBACK_BEFORE_CREDIT       tkdiag_before_credit
#define STEM_CALLBACK_SHOULD_SHUTDOWN(ctx) \
  ( (ctx)->cnc && fd_cnc_signal_query( (fd_cnc_t *)(ctx)->cnc ) == FD_CNC_SIGNAL_HALT )

#include "disco/stem/fd_stem.c"

#undef STEM_NAME
#undef STEM_CALLBACK_CONTEXT_TYPE
#undef STEM_CALLBACK_CONTEXT_ALIGN
#undef STEM_CALLBACK_BEFORE_CREDIT
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

/* ─── Callbacks ─── */

static void
tkdiag_privileged_init( fd_topo_t const *      topo,
                        fd_topo_tile_t const * tile ) {
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkdiag_ctx_t * ctx = STK_GET_CTX(tkdiag_ctx_t, scratch, TKDIAG_CTX_ALIGN);
    memset( ctx, 0, sizeof(*ctx) );
}

static void
tkdiag_unprivileged_init( fd_topo_t const *      topo,
                          fd_topo_tile_t const * tile ) {
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkdiag_ctx_t * ctx = STK_GET_CTX(tkdiag_ctx_t, scratch, TKDIAG_CTX_ALIGN);

    STK_UNPRIV_INIT(topo, tile, ctx);
    if( FD_UNLIKELY( !ctx->cnc ) )
        FD_LOG_ERR(( "%s: CNC object not found for tile %lu", tile->name, tile->id ));
    /* An observer takes no fragments and publishes none; a topology that wires
       a link to it is misconfigured, and the tile refuses to start. */
    if( FD_UNLIKELY( tile->in_cnt || tile->out_cnt ) )
        FD_LOG_ERR(( "%s: observer tile takes no links, found %lu in and %lu out",
                     tile->name, tile->in_cnt, tile->out_cnt ));
}

static void
tkdiag_before_credit( tkdiag_ctx_t *       ctx,
                      fd_stem_context_t *  stem,
                      int *                charge_busy ) {
    (void)stem; (void)charge_busy;

    /* Placeholders until shared diagnostic state is wired in. */
    stk_publish_counter( ctx->cnc, TKDIAG_SLOT_CRASHED_TILE,     0UL );
    stk_publish_counter( ctx->cnc, TKDIAG_SLOT_SANDBOX_FAILURES, 0UL );
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
    .populate_allowed_fds     = NULL,
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
