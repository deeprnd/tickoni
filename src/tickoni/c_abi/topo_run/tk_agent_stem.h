/* Shared C/FFI declarations for the tkagnt fd_stem agent worker.  The tile
   object and context stay private to tk_agent_stem.c. */
#ifndef __TK_AGENT_STEM_H__
#define __TK_AGENT_STEM_H__

#include <stdint.h>

#include "../../../disco/topo/fd_topo.h"
#include "../shim/audit_schema.h"

extern fd_topo_run_tile_t TK_AGENT_RUN;

extern fd_topo_run_tile_t const * tk_get_agent_run_tile( void );
extern char const * tk_get_agent_run_name( void );
extern void * tk_get_agent_run_run( void );
extern void * tk_get_agent_run_scratch_align( void );
extern void * tk_get_agent_run_scratch_footprint( void );
extern void * tk_get_agent_run_privileged_init( void );
extern void * tk_get_agent_run_unprivileged_init( void );

extern ulong tkagnt_tile_scratch_align( void );
extern ulong tkagnt_tile_scratch_footprint( void );
extern void  tkagnt_set_event_count( uint64_t event_count );

/* Registers the Zig-owned decision hooks (tk_agent_hooks.h).  Must be called in
   the tile's process before it runs; the tile refuses to start without them.
   Returns 0 on success, nonzero if a hook is missing. */
extern int tkagnt_set_hooks( TkAgentHooks const * hooks );

/* Declares that tier ordinal `tier` is served by the tkmodl instance with
   Firedancer kind_id `kind_id`.  The tile binds its links from these.  Returns
   0, or nonzero for an unknown tier or a tier or kind declared twice. */
extern int tkagnt_set_route( uint8_t tier, uint8_t kind_id );

/* Counters and state, read from the owning tile object's scratch base. */
extern ulong tkagnt_admitted( void * scratch );
extern ulong tkagnt_terminal_done( void * scratch );
extern ulong tkagnt_dispatched( void * scratch );
extern ulong tkagnt_results( void * scratch );
extern ulong tkagnt_denied( void * scratch );
extern ulong tkagnt_tokens( void * scratch );
extern ulong tkagnt_embeddings( void * scratch );
extern ulong tkagnt_mismatched( void * scratch );
extern ulong tkagnt_transport_dropped( void * scratch );

#endif /* __TK_AGENT_STEM_H__ */
