/* Shared C/FFI declarations for the tkpoly fd_stem specialization.

   The descriptor and its context remain private to tk_policy_stem.c.  Zig,
   topob, and the eventual tile dispatcher use this narrow surface rather
   than duplicating the descriptor or context layout. */
#ifndef __TK_POLICY_STEM_H__
#define __TK_POLICY_STEM_H__

#include <stdint.h>

#include "../../../disco/topo/fd_topo.h"

extern fd_topo_run_tile_t TK_POLICY_RUN;

extern fd_topo_run_tile_t const * tk_get_policy_run_tile( void );
extern char const * tk_get_policy_run_name( void );
extern void * tk_get_policy_run_run( void );
extern void * tk_get_policy_run_scratch_align( void );
extern void * tk_get_policy_run_scratch_footprint( void );
extern void * tk_get_policy_run_privileged_init( void );
extern void * tk_get_policy_run_unprivileged_init( void );

extern ulong tkpoly_tile_scratch_align( void );
extern ulong tkpoly_tile_scratch_footprint( void );

/* These configure behavior only.  Scratch queries remain valid before either
   setter is called because the policy context has a fixed footprint. */
extern void tkpoly_set_event_count( uint64_t event_count );
extern void tkpoly_set_policy_limit_cents( int64_t policy_limit_cents );

extern uint8_t tkpoly_policy_helper( uint8_t decision,
                                     int is_duplicate,
                                     int64_t amount_cents,
                                     int64_t policy_limit_cents );

/* The argument is the owning tile object's scratch base, not a child-process
   pointer.  These accessors expose committed counters without leaking the
   private context layout over FFI. */
/* An agent request's outcome: malformed > duplicate > allow (decision O1). */
extern uint8_t tkpoly_agent_request_helper( uint8_t decision, int is_duplicate );

extern ulong tkpoly_ctx_processed( void * scratch );
extern ulong tkpoly_ctx_allowed( void * scratch );
extern ulong tkpoly_ctx_denied( void * scratch );

#endif /* __TK_POLICY_STEM_H__ */
