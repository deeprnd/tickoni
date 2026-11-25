#ifndef __TK_GATE_STEM_H__
#define __TK_GATE_STEM_H__

#include <stdint.h>
#include "../../../disco/topo/fd_topo.h"
#include "../shim/audit_schema.h"

extern fd_topo_run_tile_t TK_GATE_RUN;
extern fd_topo_run_tile_t const * tk_get_gate_run_tile( void );
extern char const * tk_get_gate_run_name( void );
extern void * tk_get_gate_run_run( void );
extern void * tk_get_gate_run_scratch_align( void );
extern void * tk_get_gate_run_scratch_footprint( void );
extern void * tk_get_gate_run_privileged_init( void );
extern void * tk_get_gate_run_unprivileged_init( void );
extern ulong tkgate_tile_scratch_align( void );
extern ulong tkgate_tile_scratch_footprint( void );

/* tkgate's only source is its one input link, from the terminal tile
   (tk_gate_stem.c).  The event count gates its shutdown like every other spine
   tile's. */
extern void tkgate_set_event_count( uint64_t event_count );

/* 1 if `ev` has the wire shape tkgate forwards to tkings, else 0.  An all-zero
   trace id passes (tkgate fills it in).  Pure; exported for unit tests. */
extern int tkgate_wire_ok( TkEvent const * ev );

#endif