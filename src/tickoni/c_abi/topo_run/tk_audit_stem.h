/* Shared extern declaration for TK_AUDIT_RUN — the fd_stem-based
   tkaudt tile fd_topo_run_tile_t used by the audit tile.
 *
 * Both tile_run.c (process-mode dispatcher) and topob.c (topology
 * builder) need to reference this symbol.  Consolidating into a
 * single header prevents two independent extern declarations.
 */
#ifndef __TK_AUDIT_STEM_TILE_H__
#define __TK_AUDIT_STEM_TILE_H__

/* TK_HAS_AUDIT_STEM_TILE — enabled on platforms where the audit
   tile stem shim can compile and link.  Same as metric tile:
   Linux and macOS use the POSIX poll-based transport. */
#if FD_HAS_HOSTED && FD_HAS_LINUX
#define TK_HAS_AUDIT_STEM_TILE 1
#elif FD_HAS_HOSTED && FD_HAS_MACOS
#define TK_HAS_AUDIT_STEM_TILE 1
#else
#define TK_HAS_AUDIT_STEM_TILE 0
#endif

#include "../../../disco/topo/fd_topo.h"

/* Alignment constant — mirrors the definition in tk_audit_stem.c.
   Declared here so topob.c can reference it without including the .c file.
   64 bytes is a safe alignment for the tk_audit_ctx_t struct (which
   contains ulong-aligned fields and AuditEvent with 64-byte arrays). */
#define TKAUDT_CTX_ALIGN 64UL

/* Extern declaration — full definition lives in tk_audit_stem.c. */
extern fd_topo_run_tile_t TK_AUDIT_RUN;

/* Wrapper that returns the address of TK_AUDIT_RUN so callers
   never need to know the symbol name. */
extern fd_topo_run_tile_t * tk_get_audit_run_tile( void );

/* Extern declarations for audit tile scratch helpers used by topob.c.
   Full definitions live in tk_audit_stem.c. */
extern ulong tk_audit_scratch_align( void );
extern ulong tk_audit_scratch_footprint_tile( fd_topo_tile_t const * tile );

#endif /* __TK_AUDIT_STEM_TILE_H__ */
