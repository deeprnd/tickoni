/* Shared C schema for the tkaudt stem tile.
   Matches the Zig audit schema in src/tickoni/schema/audit/audit.zig
   and the payment pipeline's PaymentMessage/RawPayment in
   src/tickoni/tiles/payment_pipeline/runtime.zig.

   This header is included by tk_audit_stem.c and any other tile that
   needs to read/write audit data in C.
*/
#ifndef __AUDIT_SCHEMA_H__
#define __AUDIT_SCHEMA_H__

#include <stddef.h>
#include <stdint.h>

#include "audit_consts.h"

/* ─── Tile IDs ─── */

#define AUDIT_SCHEMA_VERSION 2

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
#define TILE_ID_TKAPI   "tkapi0"
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

/* ─── RawPayment (matches Zig runtime.RawPayment's in-memory layout) ───
   Zig's default struct layout places the 64-bit amount before account_id:
   source_offset=0, idempotency_key=8, amount_cents=16, account_id=24,
   currency=28, malformed=31.  Total size: 32 bytes. */
typedef struct {
    uint64_t  source_offset;
    uint64_t  idempotency_key;
    int64_t   amount_cents;
    uint32_t  account_id;
    uint8_t   currency[3];
    uint8_t   malformed;
} RawPayment;

/* ─── PaymentMessage (matches Zig runtime.PaymentMessage's in-memory layout) ───
   Sent from tkpoly → tkaudt on the pipeline link.  Total size: 56 bytes. */
typedef struct {
    RawPayment raw;
    uint64_t   event_hash;
    uint8_t    pipeline_hops;
    uint8_t    duplicate;
    uint8_t    decision;
    uint8_t    decided_by[6];
} PaymentMessage;

#define PAYMENT_MSG_SIZE sizeof(PaymentMessage)

_Static_assert( sizeof(RawPayment)==32UL, "RawPayment must match Zig's process-link ABI" );
_Static_assert( offsetof(RawPayment, amount_cents)==16UL, "RawPayment.amount_cents ABI drift" );
_Static_assert( offsetof(RawPayment, account_id)==24UL, "RawPayment.account_id ABI drift" );
_Static_assert( sizeof(PaymentMessage)==56UL, "PaymentMessage must match Zig's process-link ABI" );
_Static_assert( offsetof(PaymentMessage, event_hash)==32UL, "PaymentMessage.event_hash ABI drift" );
_Static_assert( offsetof(PaymentMessage, decided_by)==43UL, "PaymentMessage.decided_by ABI drift" );

/* ─── Header (matches Zig audit.Header struct) ─── */

typedef struct {
    uint16_t  schema_version;   /* 0  - audit schema version (2) */
    uint8_t   _pad0[14];        /* 2  - align run_id to 8 */
    uint64_t  run_id;           /* 16 - topology run ID */
    uint64_t  seq;              /* 24 - sequence number within run */
    uint64_t  source_offset;    /* 32 - original source offset */
    uint8_t   tile_id[6];       /* 40 - producer tile id */
    uint8_t   _pad1[2];         /* 46 - align logical_actor_id */
    uint64_t  logical_actor_id; /* 48 - logical actor (0 for pipeline) */
    uint8_t   policy_version[32]; /* 56 - policy version string */
    uint8_t   _pad2[8];         /* 88 - align capability_envelope_id */
    uint64_t  capability_envelope_id; /* 96 - capability envelope reference (simplified stub) */
    uint64_t  timestamp_ns;     /* 112 - nanosecond timestamp */
    uint64_t  prev_hash;        /* 120 - hash chain link */
    uint64_t  record_hash;      /* 128 - hash of this record */
    uint8_t   version[64];      /* 136 - semver string, null-terminated */
    uint8_t   platform_tier[64]; /* 200 - e.g. "linux_full" */
    uint8_t   isolation_tier[64]; /* 264 - e.g. "retail" */
    uint8_t   release_digest[64]; /* 328 - git SHA or build digest */
    uint8_t   manifest_id[64];    /* 392 - which manifest was loaded */
} AuditHeader;

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

/* ─── AuditEvent (minimal layout for scratch allocation) ───
   Header + PolicyDecisionPayload union.
   Total size: 504 bytes. */
typedef struct {
    AuditHeader       header;         /* 0  - 392 bytes */
    RecordType        record_type;    /* 392 - union discriminant */
    uint8_t           _pad[4];        /* 393 - align payload */
    PolicyDecisionPayload policy_decision; /* 396 - union variant */
} AuditEvent;

#define AUDIT_EVENT_SIZE sizeof(AuditEvent)

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

#endif /* __AUDIT_SCHEMA_H__ */
