/* tk_agent_wire.h — logical message bodies and records of the tkagnt process
   tile.  Included at the end of audit_schema.h (it uses ModelRequestMsg,
   ModelResultMsg and the audit payload types), so Zig sees it through the one
   translate-c step as audit_mod.TkAgent*.

   Who sends what:

     tkings  -> tkagnt   multipart, TK_MP_DIR_REQUEST, TK_MP_CT_AGENT_REQUEST
                         body = TkAgentRequestHdr + prompt bytes
     tkagnt  -> tkmodl   multipart, TK_MP_DIR_REQUEST, TK_MP_CT_CHAT|EMBEDDING
                         body = ModelRequestMsg + prompt bytes
     tkmodl  -> tkagnt   multipart, TK_MP_DIR_RESULT,  TK_MP_CT_CHAT|EMBEDDING
                         body = ModelResultMsg + response bytes (or vector bytes)
     tkmodl  -> tkaudt   one fragment, ModelAuditMsg (hashes only, no content)
     tkagnt  -> tkaudt   one fragment, TkAgentAuditMsg (hashes only, no content)
     tkagnt  -> tkdisp   one fragment, TkAgentResultMsg (hashes and status)

   Only the multipart links carry content.  The audit and terminal-result
   records are body-free: they hold hashes and attribution metadata.

   One agent request yields one model dispatch and one terminal result.  The
   agent assigns each accepted request a contiguous admission ordinal,
   `agent_seq` (1, 2, 3, ...), which is also its `model_request_id` and
   ModelRequestMsg.request_id.  `agent_seq` is the deterministic audit order
   key: tkaudt commits, for each ordinal in order, the model record (if any)
   and then the agent record, so the committed sequence does not depend on the
   order in which model completions arrive. */
#ifndef __TK_AGENT_WIRE_H__
#define __TK_AGENT_WIRE_H__

#define TK_AGENT_WIRE_VERSION  1

/* tkings -> tkagnt body header.  `scope` is a complete ModelRequestMsg whose
   request_id and prompt_hash the agent overwrites (it assigns agent_seq and
   tkmodl computes the prompt hash from the bytes it receives). */
typedef struct {
    uint16_t         version;          /* 0  - TK_AGENT_WIRE_VERSION */
    uint8_t          request_type;     /* 2  - TK_AGENT_REQ_* */
    uint8_t          requested_tier;   /* 3  - tier ordinal; TK_AGENT_TIER_NONE only for embedding */
    uint32_t         _pad;             /* 4  */
    ModelRequestMsg  scope;            /* 8  */
} TkAgentRequestHdr;                   /* 280 */

/* Terminal outcome of one agent run. */
enum {
    TK_AGENT_OUT_OK                    = 0,
    TK_AGENT_OUT_DENY_INVALID_REQUEST  = 1,   /* malformed or contradictory request */
    TK_AGENT_OUT_DENY_ABSENT_TIER      = 2,   /* the named tier is not configured */
    TK_AGENT_OUT_MODEL_DENIED          = 3,   /* tkmodl denied the call */
    TK_AGENT_OUT_INVALID_CONTENT       = 4,   /* result content is not the expected shape */
    TK_AGENT_OUT_INVALID_TIER          = 5,   /* a tier named by the model or result is unknown */
    TK_AGENT_OUT_CONTENT_TOO_LARGE     = 6,
    TK_AGENT_OUT_MODEL_TIMEOUT         = 7,   /* no complete result before the deadline */
    TK_AGENT_OUT_TRANSPORT_FAILURE     = 8,   /* a malformed multipart stream from tkmodl */
    TK_AGENT_OUT_RESULT_MISMATCH       = 9,   /* result does not match the pending dispatch */
    TK_AGENT_OUT_CAPACITY              = 10,  /* no room to accept the request */
    TK_AGENT_OUT_SHUTDOWN              = 11   /* cancelled by an administrative drain */
};

/* tkagnt -> tkdisp.  One per accepted request.  96 bytes. */
typedef struct {
    uint16_t  version;           /* 0  */
    uint8_t   outcome;           /* 2  - TK_AGENT_OUT_* */
    uint8_t   confidence;        /* 3  - TK_AGENT_CONF_* (classifier results) */
    uint8_t   recommended_tier;  /* 4  - tier ordinal or TK_AGENT_TIER_NONE */
    uint8_t   source_tier;       /* 5  - tier that answered, or TK_AGENT_TIER_NONE */
    uint8_t   request_type;      /* 6  */
    uint8_t   model_decision;    /* 7  - ModelDecision of the result, if one arrived */
    uint32_t  response_len;      /* 8  */
    uint32_t  total_tokens;      /* 12 */
    uint64_t  run_id;            /* 16 */
    uint64_t  agent_seq;         /* 24 - admission ordinal and audit order key */
    uint64_t  prompt_hash;       /* 32 */
    uint64_t  response_hash;     /* 40 - canonical hash of the response bytes */
    uint64_t  proposal_hash;     /* 48 - the hash bound into the audit record */
    uint8_t   model_id[TKMODL_MODEL_ID_LEN]; /* 56 - padded to 88 */
    uint8_t   _pad[8];           /* 88 */
} TkAgentResultMsg;              /* 96 */

/* tkagnt -> tkaudt.  record_type is RECORD_PROPOSAL for a completed run and
   RECORD_DENIAL for a denied or failed one.  `has_model_record` says whether a
   tkmodl record with request_id == agent_seq precedes this one (a run denied at
   routing, or one whose model never answered, has none): tkaudt waits for that
   record before committing this one, and for nothing else. */
typedef struct {
    uint16_t  version;                 /* 0  */
    uint8_t   record_type;             /* 2  - RecordType */
    uint8_t   has_model_record;        /* 3  */
    uint32_t  _pad0;                   /* 4  */
    uint64_t  run_id;                  /* 8  */
    uint64_t  agent_seq;               /* 16 - becomes header.source_offset; the order key */
    uint64_t  capability_envelope_hash; /* 24 - becomes header.capability_envelope_id */
    uint8_t   policy_version[TKMODL_POLICY_VERSION_LEN]; /* 32 */
    union {
        WireProposalPayload proposal;
        WireDenialPayload   denial;
    } payload;                         /* 64 */
} TkAgentAuditMsg;

#define TK_LINK_SIG_AGENT_AUDIT   0x4147UL   /* "AG": tkagnt -> tkaudt */
#define TK_LINK_SIG_MODEL_RESULT  0x4d52UL   /* "MR": tkmodl -> tkagnt result fragments */
#define TK_LINK_SIG_MODEL_REQUEST 0x4d51UL   /* "MQ": tkagnt -> tkmodl request fragments */
#define TK_LINK_SIG_AGENT_RESULT  0x4152UL   /* "AR": tkagnt -> tkdisp */
#define TK_LINK_SIG_AGENT_REQUEST 0x4151UL   /* "AQ": tkings -> tkagnt request fragments */

/* Link MTUs for the single-fragment records. */
enum {
    TK_AGENT_AUDIT_LINK_MTU  = 512,
    TK_AGENT_RESULT_LINK_MTU = 256
};

_Static_assert( sizeof(TkAgentRequestHdr)==280UL,  "TkAgentRequestHdr wire size drift" );
_Static_assert( offsetof(TkAgentRequestHdr, scope)==8UL, "TkAgentRequestHdr.scope ABI drift" );
_Static_assert( sizeof(TkAgentResultMsg)==96UL,    "TkAgentResultMsg wire size drift" );
_Static_assert( offsetof(TkAgentResultMsg, run_id)==16UL, "TkAgentResultMsg.run_id ABI drift" );
_Static_assert( offsetof(TkAgentAuditMsg, payload)==64UL, "TkAgentAuditMsg.payload ABI drift" );
_Static_assert( sizeof(TkAgentAuditMsg)<=(unsigned long)TK_AGENT_AUDIT_LINK_MTU,   "TkAgentAuditMsg must fit its link" );
_Static_assert( sizeof(TkAgentResultMsg)<=(unsigned long)TK_AGENT_RESULT_LINK_MTU, "TkAgentResultMsg must fit its link" );

#endif /* __TK_AGENT_WIRE_H__ */
