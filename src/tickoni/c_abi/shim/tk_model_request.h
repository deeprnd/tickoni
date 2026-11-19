/* tk_model_request.h — the one wire-shape check for a ModelRequestMsg, shared by
   the tile that builds requests (tkagnt) and the tile that governs them
   (tkmodl), so neither restates it. */
#ifndef __TK_MODEL_REQUEST_H__
#define __TK_MODEL_REQUEST_H__

#include <string.h>

#include "audit_schema.h"
#include "../../../ballet/siphash13/fd_siphash13.h"

/* A fixed-width string field is well formed if it is NUL terminated inside
   the field (so a value is at most len-1 bytes). */
static inline int
tk_model_field_terminated( uint8_t const * field, unsigned long len ) {
    return field[len-1UL] == 0;
}

/* Version, replay_mode, and NUL termination of every fixed-width string field.
   Returns 1 if well formed. */
static inline int
tk_model_request_well_formed( ModelRequestMsg const * req ) {
    if( req->version != TKMODL_WIRE_VERSION )                         return 0;
    if( req->replay_mode != TKMODL_REPLAY_MODE_LIVE &&
        req->replay_mode != TKMODL_REPLAY_MODE_REPLAY )               return 0;
    if( !tk_model_field_terminated( req->model_id,               TKMODL_MODEL_ID_LEN ) )       return 0;
    if( !tk_model_field_terminated( req->actor_role,             TKMODL_ROLE_LEN ) )           return 0;
    if( !tk_model_field_terminated( req->workflow,               TKMODL_WORKFLOW_LEN ) )       return 0;
    if( !tk_model_field_terminated( req->capability,             TKMODL_CAPABILITY_LEN ) )     return 0;
    if( !tk_model_field_terminated( req->capability_envelope_id, TKMODL_ENVELOPE_LEN ) )       return 0;
    if( !tk_model_field_terminated( req->policy_version,         TKMODL_POLICY_VERSION_LEN ) ) return 0;
    if( !tk_model_field_terminated( req->budget_id,              TKMODL_BUDGET_LEN ) )         return 0;
    return 1;
}

/* Stable 64-bit digest of the capability envelope id, carried in the audit
   header so every model and agent record is bound to the envelope it ran
   under.  One definition for tkmodl and tkagnt. */
static inline uint64_t
tk_model_envelope_hash( uint8_t const * envelope_id ) {
    fd_siphash13_t sip[1];
    fd_siphash13_init( sip, AUDIT_HASH_K0, AUDIT_HASH_K1 );
    fd_siphash13_append( sip, envelope_id, strlen( (char const *)envelope_id ) );
    return fd_siphash13_fini( sip );
}

#endif /* __TK_MODEL_REQUEST_H__ */
