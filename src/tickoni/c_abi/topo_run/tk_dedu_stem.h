/* Shared extern declaration for TK_DEDU_RUN — the Firedancer-based
   tkdedu fd_topo_run_tile_t.

   Both tile_run.c (process-mode dispatcher) and topob.c (topology
   builder) need to reference this symbol.

   The full definition lives in tk_dedu_stem.c.
*/
#ifndef __TK_DEDU_STEM_H__
#define __TK_DEDU_STEM_H__

#include "../../../disco/topo/fd_topo.h"

/* Extern declaration — full definition lives in tk_dedu_stem.c. */
extern fd_topo_run_tile_t TK_DEDU_RUN;

/* Wrapper that returns the address of TK_DEDU_RUN so callers
   never need to know the symbol name. */
extern fd_topo_run_tile_t const * tk_get_dedu_run_tile( void );

/* Query the scratch footprint for the dedu tile without needing a
   fd_topo_tile_t pointer. */
extern ulong tkdedu_tile_scratch_footprint( void );

/* Alignment constant for the dedu tile's scratch space. */
#define TKDEDU_CTX_ALIGN 8

/* Field accessors for standalone test — avoids Zig-C struct layout mismatch. */
extern char const * tk_get_dedu_run_name( void );
extern void * tk_get_dedu_run_run( void );
extern void * tk_get_dedu_run_scratch_align( void );
extern void * tk_get_dedu_run_scratch_footprint( void );
extern void * tk_get_dedu_run_privileged_init( void );
extern void * tk_get_dedu_run_unprivileged_init( void );

#endif /* __TK_DEDU_STEM_H__ */
