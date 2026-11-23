#ifndef __TK_INGEST_STEM_H__
#define __TK_INGEST_STEM_H__

#include <stdint.h>
#include "../../../disco/topo/fd_topo.h"
#include "../shim/audit_schema.h"

extern fd_topo_run_tile_t TK_INGEST_RUN;
extern fd_topo_run_tile_t const * tk_get_ingest_run_tile( void );
extern char const * tk_get_ingest_run_name( void );
extern void * tk_get_ingest_run_run( void );
extern void * tk_get_ingest_run_scratch_align( void );
extern void * tk_get_ingest_run_scratch_footprint( void );
extern void * tk_get_ingest_run_privileged_init( void );
extern void * tk_get_ingest_run_unprivileged_init( void );
extern ulong tkings_tile_scratch_align( void );
extern ulong tkings_tile_scratch_footprint( void );

/* tkings's only source is its one input link (tk_ingest_stem.c).  The event
   count gates its shutdown like every other spine tile's. */
extern void tkings_set_event_count( uint64_t event_count );

/* 1 if `ev` has the canonical TkEvent framing tkings forwards, else 0.  Pure;
   exported for unit tests. */
extern int tkings_framing_ok( TkEvent const * ev );

#endif
