/* Shared C/FFI declarations for tkcase, the case router fd_stem tile
   (tk_case_stem.c).  tkcase owns case scope creation, event attachment
   (TkEvent.case_id), the case capsule and the case lifecycle audit records.
   Its wire contract (TkCaseScope, TkCaseAuditMsg) is in audit_schema.h; the
   tile context stays private to tk_case_stem.c.

   Both tile_run.c (process-mode dispatcher) and topob.c (topology builder)
   reference these symbols. */
#ifndef __TK_CASE_STEM_H__
#define __TK_CASE_STEM_H__

#include "../../../disco/topo/fd_topo.h"

extern fd_topo_run_tile_t TK_CASE_RUN;

extern fd_topo_run_tile_t const * tk_get_case_run_tile( void );

/* Scratch layout of the tile object, without the fd_topo_run_tile_t
   definition.  Both call through TK_CASE_RUN, so the builder and the tile
   cannot disagree. */
extern ulong tkcase_tile_scratch_footprint( void );
extern ulong tkcase_tile_scratch_align( void );

/* Sets the run's event count: the shutdown gate, the event that closes the
   case, and the capsule size.  It participates in workspace layout, so call it
   before any footprint query; topo_build.build() is the single call site. */
extern void tkcase_set_event_count( ulong event_count );

/* Seeds the case-id generator; 0 (the default) seeds it from the tile's tick
   counter.  Read in privileged_init, so call it before the tile runs. */
extern void tkcase_set_rng_seed( ulong seed );

/* Read from the tile object's scratch base (any process). */
extern ulong tkcase_consumed( void * scratch );             /* events committed */
extern ulong tkcase_forwarded( void * scratch );            /* event fragments published, summed over tkpoly and tkdisp */
extern ulong tkcase_case_audit_emitted( void * scratch );   /* lifecycle records published */
extern ulong tkcase_capsule_count( void * scratch );        /* events in the capsule */
extern ulong tkcase_capsule_hash( void * scratch );         /* their capsule hash (tk_capsule_hash.h) */
extern void  tkcase_scope_copy( void * scratch, void * dst, ulong dst_sz );                /* dst_sz == sizeof(TkCaseScope) */
extern void  tkcase_capsule_copy( void * scratch, ulong idx, void * dst, ulong dst_sz );   /* dst_sz == sizeof(TkEvent) */

/* Field accessors for the standalone identity test. */
extern char const * tk_get_case_run_name( void );
extern void * tk_get_case_run_run( void );
extern void * tk_get_case_run_scratch_align( void );
extern void * tk_get_case_run_scratch_footprint( void );
extern void * tk_get_case_run_privileged_init( void );
extern void * tk_get_case_run_unprivileged_init( void );

#endif /* __TK_CASE_STEM_H__ */
