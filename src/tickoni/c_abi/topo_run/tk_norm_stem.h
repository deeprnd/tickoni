/* Shared extern declaration for TK_NORM_RUN — the Firedancer-based
   tknorm fd_topo_run_tile_t.

   Both tile_run.c (process-mode dispatcher) and topob.c (topology
   builder) need to reference this symbol.

   The full definition lives in tk_normalize_stem.c.
*/
#ifndef __TK_NORM_STEM_H__
#define __TK_NORM_STEM_H__

#include "../../../disco/topo/fd_topo.h"

/* Extern declaration — full definition lives in tk_normalize_stem.c. */
extern fd_topo_run_tile_t TK_NORM_RUN;

/* Wrapper that returns the address of TK_NORM_RUN so callers
   never need to know the symbol name. */
extern fd_topo_run_tile_t const * tk_get_norm_run_tile( void );

/* Alignment constant for the norm tile's scratch space. */
#define TKNORM_CTX_ALIGN 8

#endif /* __TK_NORM_STEM_H__ */
