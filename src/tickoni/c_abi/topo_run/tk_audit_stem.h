/* Shared extern declaration for TK_AUDIT_RUN — the Firedancer-based
   tkaudt fd_topo_run_tile_t used by the audit tile.

   Both tile_run.c (process-mode dispatcher) and topob.c (topology
   builder) need to reference this symbol.  Consolidating into a
   single header prevents two independent extern declarations and
   makes the FFI boundary explicit.

   The full definition lives in tk_audit_stem.c.
*/
#ifndef __TK_AUDIT_STEM_H__
#define __TK_AUDIT_STEM_H__

#include <stdint.h>
#include "../../../disco/topo/fd_topo.h"

/* Extern declaration — full definition lives in tk_audit_stem.c. */
extern fd_topo_run_tile_t TK_AUDIT_RUN;

/* Wrapper that returns the address of TK_AUDIT_RUN so callers
   never need to know the symbol name. */
extern fd_topo_run_tile_t const * tk_get_audit_run_tile( void );

/* Query the scratch footprint for the audit tile without needing a
   fd_topo_tile_t pointer.  Calls through TK_AUDIT_RUN.scratch_footprint.

   This keeps topob.c from depending on the full fd_topo_run_tile_t
   definition — it only sees the extern declaration and this thin
   accessor. */
extern ulong tk_audit_scratch_footprint( void );

/* Query the alignment of the audit tile's scratch object without needing the
   fd_topo_run_tile_t definition.  Calls through TK_AUDIT_RUN.scratch_align, so
   the topology builder and the tile cannot disagree: tk_audit_stem.c derives
   the value from alignof(tk_audit_ctx_t) and owns it alone. */
extern ulong tk_audit_scratch_align( void );

/* Set event_count from topo_build.build() — called before any footprint queries. */
extern void tkaudit_set_event_count( ulong event_count );

/* Field accessors for standalone test — avoids Zig-C struct layout mismatch.
   Matches the tknorm/tkdedu accessor set. */
extern char const * tk_get_audit_run_name( void );
extern void * tk_get_audit_run_run( void );
extern void * tk_get_audit_run_scratch_align( void );
extern void * tk_get_audit_run_scratch_footprint( void );
extern void * tk_get_audit_run_privileged_init( void );
extern void * tk_get_audit_run_unprivileged_init( void );

/* Audit-record accessors for the integration test.  `scratch` is the tile's
   scratch base (fd_topo_obj_laddr of its tile_obj_id); this file resolves the
   context and record array from it, so no caller needs tk_audit_ctx_t or
   AuditEvent layout.  tk_audit_record_count returns the COMMITTED count —
   slots at or beyond it are uncommitted staging.  The field accessors abort
   on an out-of-range index. */
extern ulong tk_audit_record_count( void * scratch );
extern ulong tk_audit_record_seq( void * scratch, ulong idx );
extern ulong tk_audit_record_prev_hash( void * scratch, ulong idx );
extern ulong tk_audit_record_hash( void * scratch, ulong idx );
extern uint  tk_audit_record_schema_version( void * scratch, ulong idx );
extern ulong tk_audit_record_source_offset( void * scratch, ulong idx );
extern void  tk_audit_record_trace_id( void * scratch, ulong idx, unsigned __int128 * out );
extern ulong tk_audit_record_case_id( void * scratch, ulong idx );
extern uint  tk_audit_record_outcome( void * scratch, ulong idx );
extern void  tk_audit_record_decided_by( void * scratch, ulong idx, uint8_t * dst );
extern ulong tk_audit_record_source_event_hash( void * scratch, ulong idx );

/* tkmodl records (record_type RECORD_MODEL_CALL / RECORD_DENIAL).  The model
   and denial accessors abort if the record at idx is not that type. */
extern uint  tk_audit_record_type( void * scratch, ulong idx );
extern ulong tk_audit_record_capability_envelope( void * scratch, ulong idx );
extern void  tk_audit_record_model_id( void * scratch, ulong idx, uint8_t * dst );
extern ulong tk_audit_record_model_prompt_hash( void * scratch, ulong idx );
extern ulong tk_audit_record_model_response_hash( void * scratch, ulong idx );
extern uint  tk_audit_record_model_token_estimate( void * scratch, ulong idx );
extern ulong tk_audit_record_model_policy_decision_id( void * scratch, ulong idx );
extern ulong tk_audit_record_model_replay_substitution_id( void * scratch, ulong idx );
extern uint  tk_audit_record_denial_reason_code( void * scratch, ulong idx );
extern ulong tk_audit_agent_committed( void * scratch );
extern ulong tk_audit_rejected_count( void * scratch );
extern ulong tk_audit_held_model_count( void * scratch );
extern ulong tk_audit_held_agent_count( void * scratch );
extern ulong tk_audit_record_proposal_hash( void * scratch, ulong idx );
extern void  tk_audit_record_proposal_type( void * scratch, ulong idx, uint8_t * dst );
extern void  tk_audit_record_denial_failed_scope_dim( void * scratch, ulong idx, uint8_t * dst );

/* Whole-record copy (dst_sz must equal sizeof(AuditEvent)); lets a test feed
   the committed record to the independent Zig hash. */
extern void  tk_audit_record_copy( void * scratch, ulong idx, void * dst, ulong dst_sz );

#endif /* __TK_AUDIT_STEM_H__ */
