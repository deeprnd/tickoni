/* Shared extern declaration for TK_POLICY_RUN — the Firedancer-based
   tkpoly fd_topo_run_tile_t.

   Both tile_run.c (process-mode dispatcher) and topob.c (topology
   builder) need to reference this symbol.

   The full definition lives in tk_policy_stem.c.
*/
#ifndef __TKPOLY_STEM_H__
#define __TKPOLY_STEM_H__

#include <stdint.h>

#include "../../../disco/topo/fd_topo.h"

/* Extern declaration — full definition lives in tk_policy_stem.c. */
extern fd_topo_run_tile_t TK_POLICY_RUN;

/* Wrapper that returns the address of TK_POLICY_RUN so callers
   never need to know the symbol name. */
extern fd_topo_run_tile_t const * tk_get_policy_run_tile( void );

/* Query the scratch footprint for the policy tile without needing a
   fd_topo_tile_t pointer. */
extern ulong tkpolicy_tile_scratch_footprint( void );

/* Query the alignment of the policy tile's scratch object. */
extern ulong tkpolicy_tile_scratch_align( void );

/* Set the policy limit in cents for this process.  Must be called before any
   footprint query, since it participates in workspace layout. */
extern void tkpoly_set_policy_limit_cents( long long policy_limit_cents );

/* Set the event count for shutdown gating.  Must be called before any
   footprint query, since it participates in workspace layout. */
extern void tkpoly_set_event_count( ulong event_count );

/* Field accessors for standalone test — avoids Zig-C struct layout mismatch. */
extern char const * tk_get_policy_run_name( void );
extern void * tk_get_policy_run_run( void );
extern void * tk_get_policy_run_scratch_align( void );
extern void * tk_get_policy_run_scratch_footprint( void );
extern void * tk_get_policy_run_privileged_init( void );
extern void * tk_get_policy_run_unprivileged_init( void );

/* Pure policy helper — branch precedence and signed boundary check.
 * Accepts incoming decision, duplicate flag, signed amount, signed limit.
 * Returns the existing outcome value (from audit_schema.h POLICY_*).
 * Branch precedence: malformed > duplicate > high-amount.
 * High-amount check: abs(amount) <= limit (signed comparison). */
extern uint8_t tkpoly_policy_helper( uint8_t  decision,
                                     int      is_duplicate,
                                     long long amount,
                                     long long limit );

/* Scratch-base counter readers for the tkpoly context.
 * `scratch` is the tile's scratch base (fd_topo_obj_laddr of its tile_obj_id);
 * this resolves the tkpoly_ctx_t from it, so callers never need the
 * context layout.  These return the live counters. */
extern ulong tkpolicy_ctx_processed( void * scratch );
extern ulong tkpolicy_ctx_allowed( void * scratch );
extern ulong tkpolicy_ctx_denied( void * scratch );

#endif /* __TKPOLY_STEM_H__ */
