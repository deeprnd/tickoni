/* Shared extern declarations for the Firedancer-based tkpoly policy tile.

   Both topob.c (topology builder) and tile_run.c (process-mode dispatcher)
   reference these symbols.  The full tile descriptor lives in the upstream
   fd_stem tile (src/tickoni/c_abi/shim/tkpoly_stem.c).
*/
#ifndef __TKPOLY_STEM_H__
#define __TKPOLY_STEM_H__

#include "../../../disco/topo/fd_topo.h"

/* Set the event count for this tkpoly process.  Must be called before any
   footprint query, since it participates in workspace layout.
   topo_build.build() is the single call site. */
extern void tkpoly_set_event_count( ulong event_count );

/* Set the policy limit (cents) for this tkpoly process.  Read from the
   payment_pipeline.config file in stemRun and passed through the C setter. */
extern void tkpoly_set_policy_limit_cents( long long policy_limit_cents );

#endif /* __TKPOLY_STEM_H__ */
