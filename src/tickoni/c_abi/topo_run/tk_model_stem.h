/* Shared C/FFI declarations for the tkmodl fd_stem specialization
   (fixture/replay only).

   The descriptor and its context remain private to tk_model_stem.c.  Zig,
   topob, and the tile dispatcher use this narrow surface rather than
   duplicating the descriptor or context layout. */
#ifndef __TK_MODEL_STEM_H__
#define __TK_MODEL_STEM_H__

#include <stdint.h>

#include "../../../disco/topo/fd_topo.h"
#include "../shim/audit_schema.h"

extern fd_topo_run_tile_t TK_MODEL_RUN;

extern fd_topo_run_tile_t const * tk_get_model_run_tile( void );
extern char const * tk_get_model_run_name( void );
extern void * tk_get_model_run_run( void );
extern void * tk_get_model_run_scratch_align( void );
extern void * tk_get_model_run_scratch_footprint( void );
extern void * tk_get_model_run_privileged_init( void );
extern void * tk_get_model_run_unprivileged_init( void );

extern ulong tkmodl_tile_scratch_align( void );
extern ulong tkmodl_tile_scratch_footprint( void );

/* Behavior configuration.  Scratch queries stay valid before either is called
   because the context has a fixed footprint. */
extern void tkmodl_set_event_count( uint64_t event_count );

/* Validates and stores the runtime configuration.  Returns 0 on success, or a
   nonzero TKMODL_CFG_* code (and stores nothing) if the configuration is
   malformed, versioned wrong, enables a live provider, or exceeds a bound. */
#define TKMODL_CFG_OK                 0
#define TKMODL_CFG_NULL               1
#define TKMODL_CFG_BAD_MAGIC          2
#define TKMODL_CFG_BAD_VERSION        3
#define TKMODL_CFG_LIVE_PROVIDER      4
#define TKMODL_CFG_ALLOWLIST_BOUND    5
#define TKMODL_CFG_FIXTURE_BOUND      6
/* Returned by tkmodl_set_fixture_content(). */
#define TKMODL_CFG_CONTENT_NO_FIXTURE 7   /* no configured fixture has this key */
#define TKMODL_CFG_CONTENT_HASH       8   /* content does not hash to the fixture's response_hash */
#define TKMODL_CFG_CONTENT_BOUND      9   /* empty, over the message bound, or over the store */
#define TKMODL_CFG_CONTENT_DUPLICATE  10  /* content already installed for this fixture */
extern int tkmodl_configure( TkModlRuntimeConfig const * cfg );

/* Installs the captured response bytes for the fixture with this key, after
   tkmodl_configure().  The bytes must hash (canonical multipart hash) to the
   fixture's response_hash; nothing is stored on error. */
extern int tkmodl_set_fixture_content( uint64_t key, uint8_t const * bytes, uint32_t len );

/* Pure governance helper: same branch order and zero/empty meanings as
   src/tickoni/tiles/model/validator.zig.  Returns a ModelDecision; for
   MODEL_DENY_MISSING_SCOPE, scope_dim_out (TKMODL_SCOPE_DIM_LEN bytes) names
   the missing field.  Mutates nothing. */
extern uint8_t tkmodl_validate( TkModlRuntimeConfig const * cfg,
                                ModelRequestMsg const *     req,
                                uint8_t *                   scope_dim_out );

/* The same governance for an embedding request: the model is checked against
   the embedding allowlist, and the requested vector width must be non-zero and
   within the allowed widths (MODEL_DENY_EMBEDDING_DIMENSION). */
extern uint8_t tkmodl_validate_embedding( TkModlRuntimeConfig const * cfg,
                                          ModelRequestMsg const *     req,
                                          uint8_t *                   scope_dim_out );

/* Wire-shape check of a reassembled request: version, replay_mode, and NUL
   termination of every fixed-width string field.  Returns 1 if well formed. */
extern int tkmodl_request_well_formed( ModelRequestMsg const * req );

/* Committed counters, read from the owning tile object's scratch base. */
extern ulong tkmodl_ctx_processed( void * scratch );
extern ulong tkmodl_ctx_allowed( void * scratch );
extern ulong tkmodl_ctx_denied( void * scratch );
extern ulong tkmodl_ctx_dropped( void * scratch );

#endif /* __TK_MODEL_STEM_H__ */
