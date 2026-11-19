/* Shared C/FFI declarations for the placeholder stem tiles of the investment
   workflow: tkcase, tktool and tkadpt share one implementation (tk_pass_stem.c)
   and one scratch layout.  The tile object and context stay private to it. */
#ifndef __TK_PASS_STEM_H__
#define __TK_PASS_STEM_H__

#include <stdint.h>

#include "../../../disco/topo/fd_topo.h"

extern fd_topo_run_tile_t TK_CASE_RUN;
extern fd_topo_run_tile_t TK_TOOL_RUN;
extern fd_topo_run_tile_t TK_ADPT_RUN;

extern ulong tkpass_tile_scratch_align( void );
extern ulong tkpass_tile_scratch_footprint( void );
extern void  tkpass_set_event_count( uint64_t event_count );

/* Fragments consumed and (tkcase only) forwarded, from the tile's scratch base. */
extern ulong tkpass_consumed( void * scratch );
extern ulong tkpass_forwarded( void * scratch );

#endif /* __TK_PASS_STEM_H__ */
