/* Shared C/FFI declarations for the tkagnt result-sink fd_stem specialization.
   The tile object and context stay private to tk_agent_sink_stem.c. */
#ifndef __TK_AGENT_SINK_STEM_H__
#define __TK_AGENT_SINK_STEM_H__

#include <stdint.h>

#include "../../../disco/topo/fd_topo.h"

extern fd_topo_run_tile_t TK_AGENT_SINK_RUN;

extern fd_topo_run_tile_t const * tk_get_agent_sink_run_tile( void );
extern char const * tk_get_agent_sink_run_name( void );
extern void * tk_get_agent_sink_run_run( void );
extern void * tk_get_agent_sink_run_scratch_align( void );
extern void * tk_get_agent_sink_run_scratch_footprint( void );
extern void * tk_get_agent_sink_run_privileged_init( void );
extern void * tk_get_agent_sink_run_unprivileged_init( void );

extern ulong tkagnt_tile_scratch_align( void );
extern ulong tkagnt_tile_scratch_footprint( void );
extern void  tkagnt_set_event_count( uint64_t event_count );

/* Committed-result accessors.  `scratch` is the owning tile object's scratch
   base; every accessor aborts on an out-of-range index. */
extern ulong tkagnt_result_count( void * scratch );
extern ulong tkagnt_result_request_id( void * scratch, ulong idx );
extern ulong tkagnt_result_run_id( void * scratch, ulong idx );
extern uint  tkagnt_result_decision( void * scratch, ulong idx );
extern ulong tkagnt_result_prompt_hash( void * scratch, ulong idx );
extern ulong tkagnt_result_response_hash( void * scratch, ulong idx );
extern ulong tkagnt_result_replay_substitution_id( void * scratch, ulong idx );
extern uint  tkagnt_result_total_tokens( void * scratch, ulong idx );
extern uint  tkagnt_result_prompt_tokens( void * scratch, ulong idx );
extern uint  tkagnt_result_completion_tokens( void * scratch, ulong idx );
extern void  tkagnt_result_failed_scope_dim( void * scratch, ulong idx, uint8_t * dst );
extern void  tkagnt_result_model_id( void * scratch, ulong idx, uint8_t * dst );

#endif /* __TK_AGENT_SINK_STEM_H__ */
