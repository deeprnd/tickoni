/* Shared C/FFI declarations for tkrepl, the replay fd_stem tile
   (tk_repl_stem.c).  tkrepl replays the run's case capsule tkcase streams it,
   with external effects disabled, and reports the Zig verdict to tkaudt
   (RECORD_REPLAY_RESULT) and on its CNC slots.  Its wire contract
   (TkCaseCapsuleMsg, TkReplAuditMsg, TkReplHooks) is in tkrepl_frag.h; the tile
   context stays private to tk_repl_stem.c.

   Both tile_run.c (process-mode dispatcher) and topob.c (topology builder)
   reference these symbols. */
#ifndef __TK_REPL_STEM_H__
#define __TK_REPL_STEM_H__

#include "../../../disco/topo/fd_topo.h"

extern fd_topo_run_tile_t TK_REPL_RUN;

extern fd_topo_run_tile_t const * tk_get_replay_run_tile( void );

/* Scratch layout of the tile object, without the fd_topo_run_tile_t
   definition.  Both call through TK_REPL_RUN, so the builder and the tile
   cannot disagree. */
extern ulong tkrepl_tile_scratch_footprint( void );
extern ulong tkrepl_tile_scratch_align( void );

/* tkrepl_set_hooks( TkReplHooks const * ) registers the Zig-owned verdict hook
   (tkrepl_frag.h); its one caller is Zig (c_abi/tkrepl.zig).  A tile with a
   capsule input refuses to start without it. */

/* Read from the tile object's scratch base (any process). */
extern ulong tkrepl_replay_checked( void * scratch );   /* 1 once the verdict is reported */
extern ulong tkrepl_replay_match( void * scratch );     /* 1 when it found no divergence */
extern ulong tkrepl_observed_count( void * scratch );   /* capsule events folded */
extern ulong tkrepl_observed_hash( void * scratch );    /* their capsule hash */
extern ulong tkrepl_rejected( void * scratch );         /* fragments refused */
extern void  tkrepl_verdict_copy( void * scratch, void * dst, ulong dst_sz );   /* dst_sz == sizeof(TkReplVerifyDirective) */

/* Field accessors for the standalone identity test. */
extern char const * tk_get_replay_run_name( void );
extern void * tk_get_replay_run_run( void );
extern void * tk_get_replay_run_scratch_align( void );
extern void * tk_get_replay_run_scratch_footprint( void );
extern void * tk_get_replay_run_privileged_init( void );
extern void * tk_get_replay_run_unprivileged_init( void );

#endif /* __TK_REPL_STEM_H__ */
