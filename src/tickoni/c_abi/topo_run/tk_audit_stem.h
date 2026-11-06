/* Shared extern declaration for TK_AUDIT_RUN — the Firedancer-based
   tkaudt fd_topo_run_tile_t used by the audit tile.

   Both tile_run.c (process-mode dispatcher) and topob.c (topology
   builder) need to reference this symbol.  Consolidating into a
   single header prevents two independent extern declarations and
   makes the FFI boundary explicit.

   The full definition lives in tk_audit_stem.c.
*/
#ifndef __TK_AUDIT_STEM_H__
#define __TK_AUDIT_STEM_H__

#include "../../../disco/topo/fd_topo.h"

/* Extern declaration — full definition lives in tk_audit_stem.c. */
extern fd_topo_run_tile_t TK_AUDIT_RUN;

/* Wrapper that returns the address of TK_AUDIT_RUN so callers
   never need to know the symbol name. */
extern fd_topo_run_tile_t const * tk_get_audit_run_tile( void );

/* Query the scratch footprint for the audit tile without needing a
   fd_topo_tile_t pointer.  Calls through TK_AUDIT_RUN.scratch_footprint.

   This keeps topob.c from depending on the full fd_topo_run_tile_t
   definition — it only sees the extern declaration and this thin
   accessor. */
extern ulong tk_audit_scratch_footprint( void );

/* The alignment for the audit tile's scratch space.
   Matches TKAUDT_CTX_ALIGN in tk_audit_stem.c.
   topob.c uses this to verify alignment parity. */
#define TKAUDT_CTX_ALIGN 8

#endif /* __TK_AUDIT_STEM_H__ */
