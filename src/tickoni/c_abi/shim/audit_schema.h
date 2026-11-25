/* Shared C schema for the tkaudt stem tile.
   Matches the Zig audit schema in src/tickoni/schema/audit/audit.zig.  The
   spine event envelope (TkEvent) is in tk_event_wire.h, included at the end.

   This header is included by tk_audit_stem.c and any other tile that
   needs to read/write audit data in C.
*/
#ifndef __AUDIT_SCHEMA_H__
#define __AUDIT_SCHEMA_H__

#include <stddef.h>
#include <stdint.h>

#include "audit_consts.h"
#include "tk_multipart_wire.h"
#include "tk_agent_hooks.h"

/* ─── Tile IDs ─── */

#define AUDIT_SCHEMA_VERSION 3

/* A request trace id (TkEvent.trace_id and every copy of it): 16 opaque
   bytes, W3C Trace Context / OpenTelemetry trace-id order (byte 0 is the
   first hex pair of the 32-char lowercase form at W3C boundaries).  All zero
   is invalid.  A byte array, not __uint128_t, so MSVC, Clang, GCC and Zig
   agree on its layout on every platform; _Alignas(16) keeps the 16-byte
   field alignment, offsets and sizes the wire structs already have. */
#define TK_TRACE_ID_SZ 16

/* Committed-order watermark value before tkaudt has committed anything.
   Full 64-bit width on every platform: C's ULONG_MAX is only 32-bit on
   Windows (LLP64) while the fseq word is 64-bit. */
#define TK_AUDIT_WATERMARK_NONE ((uint64_t)UINT64_MAX)

/* Tile IDs used as producers in audit records. The pipeline stage that
   actually finalizes a message's decision stamps its own id here
   (tknorm for malformed_drop, tkpoly for allow/deny) instead of
   every record being attributed to tkpoly. */
#define TILE_ID_TKINGS  "tkings"
#define TILE_ID_TKNORM  "tknorm"
#define TILE_ID_TKDEDU  "tkdedu"
#define TILE_ID_TKPOLY  "tkpoly"
#define TILE_ID_TKAUDT  "tkaudt"
#define TILE_ID_TKREPL  "tkrepl"
#define TILE_ID_TKCASE  "tkcase"
#define TILE_ID_TKDISP  "tkdisp"
#define TILE_ID_TKAGNT  "tkagnt"
#define TILE_ID_TKMODL  "tkmodl"
#define TILE_ID_TKTOOL  "tktool"
#define TILE_ID_TKADPT  "tkadpt"
#define TILE_ID_TKEXEC  "tkexec"
#define TILE_ID_TKGATE   "tkgate"
#define TILE_ID_METRIC  "metric"
#define TILE_ID_TKDIAG  "tkdiag"

/* ─── Workspace Names ─── */

#define WKSP_NAME_METRIC    "metric"
#define WKSP_NAME_METRIC_IN "metric_in"

/* ─── PolicyOutcome (matches Zig audit.PolicyOutcome enum(u8)) ─── */

typedef uint8_t PolicyOutcome;
enum {
    POLICY_ALLOW                = 0,
    POLICY_DENY                 = 1,
    POLICY_REQUIRE_APPROVAL     = 2,
    POLICY_MALFORMED_DROP       = 3,
    POLICY_DUPLICATE_DROP       = 4,
    POLICY_ESCALATE             = 5,
    POLICY_REQUIRE_MORE_EVIDENCE = 6,
};

/* ─── RecordType (matches Zig audit.RecordType enum(u8)) ─── */

typedef uint8_t RecordType;
enum {
    RECORD_SOURCE_EVENT           = 0,
    RECORD_NORMALIZATION          = 1,
    RECORD_POLICY_DECISION        = 2,
    RECORD_MODEL_CALL             = 3,
    RECORD_FINANCIAL_ADAPTER_CALL = 4,
    RECORD_PROPOSAL               = 5,
    RECORD_DESTINATION_CHECK      = 6,
    RECORD_LIMIT_CHECK            = 7,
    RECORD_APPROVAL_REQUIRED      = 8,
    RECORD_DENIAL                 = 9,
    RECORD_TELEMETRY_CHECKPOINT   = 10,
    RECORD_REPLAY_RESULT          = 11,
    RECORD_DUPLICATION            = 12,
    RECORD_CASE_CREATION          = 13,
};

/* ─── Header (matches Zig audit.Header struct) ─── */

typedef struct {
    uint16_t  schema_version;   /* 0  - audit schema version (3) */
    uint8_t   _pad0[4];         /* 2  - align trace_id to 16 */
    _Alignas(16) uint8_t trace_id[TK_TRACE_ID_SZ]; /* 16 - request trace the record belongs to (TkEvent.trace_id) */
    uint64_t  run_id;           /* 24 - topology run ID */
    uint64_t  seq;              /* 32 - sequence number within run */
    uint64_t  source_offset;    /* 40 - original source offset */
    uint8_t   tile_id[6];       /* 48 - producer tile id */
    uint8_t   _pad1[2];         /* 54 - align logical_actor_id */
    uint64_t  logical_actor_id; /* 56 - logical actor (0 for pipeline) */
    uint8_t   policy_version[32]; /* 64 - policy version string */
    uint64_t  case_id;          /* 96 - CaseOps case (TkEvent.case_id); 0 until tkcase assigns one */
    uint64_t  capability_envelope_id; /* 104 - capability envelope reference (simplified stub) */
    uint64_t  timestamp_ns;     /* 112 - nanosecond timestamp */
    uint64_t  prev_hash;        /* 120 - hash chain link */
    uint64_t  record_hash;      /* 128 - hash of this record */
    uint8_t   version[64];      /* 136 - semver string, null-terminated */
    uint8_t   platform_tier[64]; /* 200 - e.g. "linux_full" */
    uint8_t   isolation_tier[64]; /* 264 - e.g. "retail" */
    uint8_t   release_digest[64]; /* 328 - git SHA or build digest */
    uint8_t   manifest_id[64];    /* 392 - which manifest was loaded */
} AuditHeader;                  /* 400 */

/* ─── PolicyDecisionPayload (matches Zig audit.PolicyDecisionPayload) ─── */

typedef struct {
    PolicyOutcome outcome;          /* 0  - policy decision outcome */
    uint8_t   _pad0[7];             /* 1  - align rule_id */
    uint32_t  rule_id;              /* 8  - matching rule ID */
    uint8_t   failed_scope_dim[32]; /* 12 - which scope dimension failed */
    uint64_t  source_event_hash;    /* 44 - hash of source event */
    uint32_t  catalog_schema_version; /* 52 - catalog schema version */
    uint8_t   _pad1[4];             /* 56 - align taxonomy_id */
    uint8_t   taxonomy_id[32];      /* 60 - taxonomy identifier */
    uint32_t  taxonomy_version;     /* 92 - taxonomy version */
    uint8_t   classification_code[32]; /* 96 - classification code */
} PolicyDecisionPayload;


/* ─── Wire-format payload types (for binary serialization) ───
   These mirror the wire codec types in wire.zig.
   translate-c generates extern structs from these — no hand-written
   Zig mirrors needed, alignment is guaranteed by the C compiler. */

typedef struct {
    uint8_t   source_system[16];
    uint8_t   event_type[32];
    uint64_t  raw_hash;
} WireSourceEventPayload;

typedef struct {
    uint64_t  source_event_hash;
    uint64_t  normalized_hash;
    uint8_t   canonical_event_type[32];
} WireNormalizationPayload;

typedef struct {
    uint8_t   model_id[32];
    uint64_t  prompt_hash;
    uint64_t  response_hash;
    uint32_t  token_estimate;
    uint8_t   retry_count;
    uint8_t   actor_role[16];
    uint8_t   workflow[16];
    uint64_t  policy_decision_id;
    uint64_t  replay_substitution_id;
} WireModelCallPayload;

typedef struct {
    uint8_t   adapter_id[16];
    uint64_t  request_hash;
    uint64_t  response_hash;
    uint32_t  replay_substitution_id;
} WireFinancialAdapterCallPayload;

typedef struct {
    uint8_t   proposal_type[32];
    uint64_t  proposal_hash;
    uint8_t   approval_state;
} WireProposalPayload;

typedef struct {
    uint8_t   destination_type[16];
    uint32_t  allowlist_version;
    PolicyOutcome outcome;
} WireDestinationCheckPayload;

typedef struct {
    RecordType limit_type;  /* LimitType — same as RecordType enum */
    int64_t     value;
    int64_t     limit;
    PolicyOutcome outcome;
} WireLimitCheckPayload;

typedef struct {
    uint8_t   action_class[32];
    uint8_t   approval_path[32];
    uint64_t  proposal_hash;
} WireApprovalRequiredPayload;

typedef struct {
    uint8_t   action_class[32];
    uint32_t  reason_code;
    uint8_t   failed_scope_dim[32];
    uint32_t  catalog_schema_version;
    uint8_t   taxonomy_id[32];
    uint32_t  taxonomy_version;
    uint8_t   classification_code[32];
} WireDenialPayload;

typedef struct {
    uint64_t  metric_set_hash;
    uint64_t  source_offset_watermark;
} WireTelemetryCheckpointPayload;

typedef struct {
    uint64_t  capsule_id;
    uint64_t  divergences;
    uint64_t  first_divergent_seq;
} WireReplayResultPayload;

typedef struct {
    uint64_t  idempotency_key;
    uint8_t   is_duplicate;
} WireDeduplicationPayload;

typedef struct {
    uint64_t  basket_id;
    uint8_t   instrument_count;
    uint8_t   rejected_count;
    int64_t   total_allocated_cents;
} WireCaseCreationPayload;

/* ─── tkmodl wire contract (fixture/replay-only tkmodl, wire version 1) ───

   Fixed-size, pointer-free, little-endian records.  Strings are fixed-width
   NUL-padded byte fields; an all-zero required field means "missing scope".
   Prompt and response bodies never travel on a link: only ids and hashes do.
   Source of truth for the C tile, the Zig FFI wrapper (translate-c) and the
   tkaudt model-call record. */

#define TKMODL_WIRE_VERSION        2
#define TKMODL_MODEL_ID_LEN        32
#define TKMODL_ROLE_LEN            16
#define TKMODL_WORKFLOW_LEN        16
#define TKMODL_CAPABILITY_LEN      32
#define TKMODL_ENVELOPE_LEN        32
#define TKMODL_POLICY_VERSION_LEN  32
#define TKMODL_BUDGET_LEN          32
#define TKMODL_SCOPE_DIM_LEN       32

/* Fragment `sig` discriminating what a link carries.  Spine links (TkEvent)
   publish sig 0; the tkmodl audit link publishes the record type it carries. */
#define TK_LINK_SIG_EVENT          0UL
#define TK_LINK_SIG_MODEL_CALL     ((unsigned long)RECORD_MODEL_CALL)
#define TK_LINK_SIG_MODEL_DENIAL   ((unsigned long)RECORD_DENIAL)

/* TkModlDecision tags (match src/tickoni/tiles/model/messages.zig). */
typedef uint8_t ModelDecision;
enum {
    MODEL_ALLOW_LIVE                    = 0,
    MODEL_ALLOW_REPLAY                  = 1,
    MODEL_DENY_MISSING_SCOPE            = 2,
    MODEL_DENY_MODEL_NOT_ALLOWED        = 3,
    MODEL_DENY_BUDGET_EXHAUSTED         = 4,
    MODEL_DENY_CONTEXT_LIMIT            = 5,
    MODEL_DENY_OUTPUT_LIMIT             = 6,
    MODEL_DENY_RETRY_LIMIT              = 7,
    MODEL_DENY_LIVE_PROVIDER_DISABLED   = 8,
    MODEL_DENY_REPLAY_SUBSTITUTION_MISSING = 9,
    MODEL_DENY_EMBEDDING_DIMENSION      = 10,  /* embedding width missing, not allowed, or not the capture's */
};

#define TKMODL_REPLAY_MODE_LIVE    0
#define TKMODL_REPLAY_MODE_REPLAY  1

/* tkagnt -> tkmodl (the scope of an agent request, TkAgentRequestMsg).  288 bytes. */
typedef struct {
    uint16_t  version;                /* 0   - TKMODL_WIRE_VERSION */
    uint8_t   replay_mode;            /* 2   - TKMODL_REPLAY_MODE_* */
    uint8_t   retry_limit;            /* 3 */
    uint32_t  _pad0;                  /* 4 */
    uint64_t  request_id;             /* 8 */
    uint64_t  run_id;                 /* 16 */
    uint64_t  actor_id;               /* 24 */
    uint64_t  account_id;             /* 32 */
    uint64_t  policy_decision_id;     /* 40 */
    uint64_t  replay_substitution_id; /* 48 - key into the tkmodl fixture table */
    uint64_t  prompt_hash;            /* 56 */
    uint32_t  max_context_tokens;     /* 64 */
    uint32_t  max_output_tokens;      /* 68 */
    uint32_t  timeout_ms;             /* 72 */
    uint32_t  embedding_dimensions;   /* 76 - requested vector width in f32 elements; 0 for chat */
    uint8_t   model_id[TKMODL_MODEL_ID_LEN];                    /* 80 */
    uint8_t   actor_role[TKMODL_ROLE_LEN];                      /* 112 */
    uint8_t   workflow[TKMODL_WORKFLOW_LEN];                    /* 128 */
    uint8_t   capability[TKMODL_CAPABILITY_LEN];                /* 144 */
    uint8_t   capability_envelope_id[TKMODL_ENVELOPE_LEN];      /* 176 */
    uint8_t   policy_version[TKMODL_POLICY_VERSION_LEN];        /* 208 */
    uint8_t   budget_id[TKMODL_BUDGET_LEN];                     /* 240 */
    _Alignas(16) uint8_t trace_id[TK_TRACE_ID_SZ]; /* 272 - request trace; stamped by tkdisp from the event */
} ModelRequestMsg;                    /* 288 */

/* tkmodl -> tkagnt.  136 bytes. */
typedef struct {
    uint16_t  version;                /* 0 */
    uint8_t   decision;               /* 2 - ModelDecision */
    uint8_t   retry_count;            /* 3 */
    uint32_t  _pad0;                  /* 4 */
    uint64_t  request_id;             /* 8 */
    uint64_t  run_id;                 /* 16 */
    uint64_t  prompt_hash;            /* 24 */
    uint64_t  response_hash;          /* 32 */
    uint64_t  replay_substitution_id; /* 40 */
    uint64_t  latency_ms;             /* 48 */
    uint32_t  prompt_tokens;          /* 56 */
    uint32_t  completion_tokens;      /* 60 */
    uint32_t  total_tokens;           /* 64 */
    uint32_t  _pad1;                  /* 68 */
    uint8_t   model_id[TKMODL_MODEL_ID_LEN];            /* 72 */
    uint8_t   failed_scope_dim[TKMODL_SCOPE_DIM_LEN];   /* 104 */
} ModelResultMsg;                     /* 136 */

/* tkmodl -> tkaudt.  Carries exactly one record; record_type selects the
   union member (RECORD_MODEL_CALL for allowed requests, RECORD_DENIAL for
   denied ones).  The audit record header is built by tkaudt. */
typedef struct {
    uint16_t  version;                /* 0 */
    uint8_t   record_type;            /* 2 - RecordType */
    uint8_t   _pad0[4];               /* 3 */
    uint64_t  run_id;                 /* 8 */
    uint64_t  request_id;             /* 16 - becomes header.source_offset */
    uint64_t  capability_envelope_hash; /* 24 - becomes header.capability_envelope_id */
    uint8_t   policy_version[TKMODL_POLICY_VERSION_LEN]; /* 32 */
    _Alignas(16) uint8_t trace_id[TK_TRACE_ID_SZ]; /* 64 - becomes header.trace_id */
    union {
        WireModelCallPayload model_call;
        WireDenialPayload    denial;
    } payload;                        /* 80 */
} ModelAuditMsg;                    /* 224 */

/* ─── tkmodl runtime configuration (supervisor -> tkmodl child handoff) ───

   Read by each tkmodl child from its own `tkmodl.<kind_id>.config` (an
   identity-bound header followed by this struct; see
   src/app/tickoni/model_instances.zig) and passed to the C tile through
   tkmodl_configure().  This tile is fixture/replay only, so
   live_provider_enabled must be zero: the tile rejects a configuration that
   enables a live provider.  Zero limits and an empty allowlist keep the
   validator.zig meaning (no enforcement / no restriction). */

#define TKMODL_CONFIG_MAGIC          0x544b4d43u  /* "TKMC" */
#define TKMODL_CONFIG_VERSION        2
#define TKMODL_MAX_ALLOWED_MODELS    16
#define TKMODL_FIXTURE_CAP           16
#define TKMODL_MAX_EMBEDDING_DIMENSIONS 8

/* Captured response bytes for the fixture table live in a bounded per-process
   store, outside the audit record.  A single capture is also bounded by the
   multipart message ceiling less the result header. */
enum { TKMODL_CONTENT_STORE_BYTES = 512*1024 };

/* One captured model result, resolved by replay_substitution_id. */
typedef struct {
    uint64_t  key;                    /* 0  - replay_substitution_id; 0 = unused */
    uint64_t  prompt_hash;            /* 8  - must equal the request's prompt_hash */
    uint64_t  response_hash;          /* 16 */
    uint32_t  prompt_tokens;          /* 24 */
    uint32_t  completion_tokens;      /* 28 */
    uint32_t  total_tokens;           /* 32 */
    uint32_t  latency_ms;             /* 36 */
    uint8_t   model_id[TKMODL_MODEL_ID_LEN]; /* 40 - must equal the request's model_id */
} TkModlFixtureEntry;                 /* 72 */

typedef struct {
    uint32_t  magic;                  /* 0  - TKMODL_CONFIG_MAGIC */
    uint16_t  version;                /* 4  - TKMODL_CONFIG_VERSION */
    uint8_t   allowed_model_count;    /* 6  - <= TKMODL_MAX_ALLOWED_MODELS */
    uint8_t   live_provider_enabled;  /* 7  - must be 0 for the fixture/replay tile */
    uint32_t  hard_max_context_tokens; /* 8  - 0 = no enforcement */
    uint32_t  hard_max_output_tokens;  /* 12 - 0 = no enforcement */
    uint32_t  hard_timeout_ms;        /* 16 */
    uint32_t  per_run_token_budget;   /* 20 - 0 = no enforcement */
    uint8_t   hard_max_retry_count;   /* 24 - 0 = no enforcement */
    uint8_t   fixture_count;          /* 25 - <= TKMODL_FIXTURE_CAP */
    uint8_t   allowed_embedding_model_count;     /* 26 - <= TKMODL_MAX_ALLOWED_MODELS; 0 = no restriction */
    uint8_t   allowed_embedding_dimension_count; /* 27 - <= TKMODL_MAX_EMBEDDING_DIMENSIONS; 0 = no restriction */
    uint8_t   _pad[4];                /* 28 */
    uint8_t   allowed_model_ids[TKMODL_MAX_ALLOWED_MODELS][TKMODL_MODEL_ID_LEN]; /* 32 - chat/completion models */
    TkModlFixtureEntry fixtures[TKMODL_FIXTURE_CAP];
    /* Embedding governance: the embedding model allowlist and the vector widths
       (f32 elements) this instance may serve. A request is governed against
       these, not the chat allowlist, when it is an embedding request. */
    uint8_t   allowed_embedding_model_ids[TKMODL_MAX_ALLOWED_MODELS][TKMODL_MODEL_ID_LEN];
    uint32_t  allowed_embedding_dimensions[TKMODL_MAX_EMBEDDING_DIMENSIONS];
} TkModlRuntimeConfig;

_Static_assert( sizeof(TkModlFixtureEntry)==72UL, "TkModlFixtureEntry ABI drift" );
_Static_assert( offsetof(TkModlRuntimeConfig, allowed_model_ids)==32UL, "TkModlRuntimeConfig ABI drift" );
_Static_assert( sizeof(TkModlRuntimeConfig)%8UL==0UL, "TkModlRuntimeConfig must be 8-byte multiple" );

/* ─── AuditEvent (minimal layout for scratch allocation) ───
   Header + one payload variant, selected by record_type.  Declared after the
   Wire* payload types it embeds. */
typedef struct {
    AuditHeader       header;         /* 0  - 400 bytes */
    RecordType        record_type;    /* 400 - union discriminant */
    uint8_t           _pad0[7];       /* 401 - align payload to 8 */
    union {
        PolicyDecisionPayload policy_decision;
        WireModelCallPayload  model_call;
        WireProposalPayload   proposal;
        WireDenialPayload     denial;
    };
} AuditEvent;                   /* 488 */

#define AUDIT_EVENT_SIZE sizeof(AuditEvent)

_Static_assert( sizeof(ModelRequestMsg)==288UL, "ModelRequestMsg wire size drift" );
_Static_assert( offsetof(ModelRequestMsg, trace_id)==272UL, "ModelRequestMsg.trace_id ABI drift" );
_Static_assert( offsetof(ModelRequestMsg, model_id)==80UL, "ModelRequestMsg.model_id ABI drift" );
_Static_assert( sizeof(ModelResultMsg)==136UL, "ModelResultMsg wire size drift" );
_Static_assert( offsetof(ModelResultMsg, model_id)==72UL, "ModelResultMsg.model_id ABI drift" );
_Static_assert( offsetof(ModelAuditMsg, payload)==80UL, "ModelAuditMsg.payload ABI drift" );
_Static_assert( sizeof(ModelAuditMsg)==224UL, "ModelAuditMsg wire size drift" );
_Static_assert( offsetof(ModelAuditMsg, trace_id)==64UL, "ModelAuditMsg.trace_id ABI drift" );
_Static_assert( offsetof(AuditHeader, trace_id)==16UL, "AuditHeader.trace_id ABI drift" );
_Static_assert( offsetof(AuditHeader, case_id)==104UL, "AuditHeader.case_id ABI drift" );
_Static_assert( offsetof(AuditHeader, capability_envelope_id)==112UL, "AuditHeader.capability_envelope_id ABI drift" );

#include "tk_agent_wire.h"
#include "tk_event_wire.h"
#include "tk_diag_fragment.h"

#endif /* __AUDIT_SCHEMA_H__ */
