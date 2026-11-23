/* Shared C/FFI declarations for the tkdisp agent dispatch scheduler fd_stem
   specialization.  The tile object and context stay private to
   tk_disp_stem.c. */
#ifndef __TK_DISP_STEM_H__
#define __TK_DISP_STEM_H__

#include <stdint.h>

#include "../../../disco/topo/fd_topo.h"
#include "../shim/audit_schema.h"

extern fd_topo_run_tile_t TK_DISP_RUN;

extern fd_topo_run_tile_t const * tk_get_disp_run_tile( void );
extern char const * tk_get_disp_run_name( void );
extern void * tk_get_disp_run_run( void );
extern void * tk_get_disp_run_scratch_align( void );
extern void * tk_get_disp_run_scratch_footprint( void );
extern void * tk_get_disp_run_privileged_init( void );
extern void * tk_get_disp_run_unprivileged_init( void );

extern ulong tkdisp_tile_scratch_align( void );
extern ulong tkdisp_tile_scratch_footprint( void );
extern void  tkdisp_set_event_count( uint64_t event_count );

/* Installs the template a tkdisp sends for every PAYMENT event (decision O2:
   the tier, scope and prompt reference come from here, never from the event;
   an agent-request event carries its own request).  Returns 0, or nonzero and
   installs nothing for a request that is not well formed. */
extern int tkdisp_set_template( TkAgentRequestMsg const * req );

/* Requests sent and events seen. */
extern ulong tkdisp_scheduled( void * scratch );
extern ulong tkdisp_events_seen( void * scratch );

/* Committed terminal results.  `scratch` is the owning tile object's scratch
   base; the copy accessor aborts on an out-of-range index or a size mismatch. */
extern ulong tkdisp_result_count( void * scratch );
extern void  tkdisp_result_copy( void * scratch, ulong idx, void * dst, ulong dst_sz );

#endif /* __TK_DISP_STEM_H__ */
