/* Shared extern declaration for TKNORM_RUN — the fd_stem-based
   tknorm tile fd_topo_run_tile_t used by the normalize tile.

   Both tile_run.c (process-mode dispatcher) and topob.c (topology
   builder) need to reference this symbol.  Consolidating into a
   single header prevents two independent extern declarations. */
#ifndef __TK_NORM_STEM_TILE_H__
#define __TK_NORM_STEM_TILE_H__

/* TK_HAS_NORM_STEM_TILE — enabled on platforms where the normalize
   tile stem shim can compile and link.  Same as audit tile:
   Linux and macOS use the POSIX poll-based transport. */
#if FD_HAS_HOSTED && FD_HAS_LINUX
#define TK_HAS_NORM_STEM_TILE 1
#elif FD_HAS_HOSTED && FD_HAS_MACOS
#define TK_HAS_NORM_STEM_TILE 1
#else
#define TK_HAS_NORM_STEM_TILE 0
#endif

#include "../../../disco/topo/fd_topo.h"

/* Alignment constant — mirrors the definition in tk_normalize_stem.c.
   64 bytes is a safe alignment for the tknorm_ctx_t struct (which
   contains ulong-aligned fields). */
#define TK_NORM_CTX_ALIGN 64UL

/* Extern declaration — full definition lives in tk_normalize_stem.c. */
extern fd_topo_run_tile_t TKNORM_RUN;

/* Wrapper that returns the address of TKNORM_RUN so callers
   never need to know the symbol name. */
extern fd_topo_run_tile_t * tk_get_normalize_run_tile( void );

/* Extern declarations for normalize tile scratch helpers used by topob.c.
   Full definitions live in tk_normalize_stem.c. */
extern ulong tk_norm_scratch_align( void );
extern ulong tk_norm_scratch_footprint_tile( fd_topo_tile_t const * tile );

#endif /* __TK_NORM_STEM_TILE_H__ */
