/* audit_schema.h — Shared C definition for the canonical audit event schema.
   Matches src/tickoni/schema/audit/audit.zig exactly.
   Both tk_audit_stem.c and future C code #include this. */

#ifndef __AUDIT_SCHEMA_H__
#define __AUDIT_SCHEMA_H__

#include <stdint.h>
#include <string.h>

/* Canonical schema version — must match Zig audit_schema_version. */
#define AUDIT_SCHEMA_VERSION 2

/* Seed value for FNV-1a hash chain. */
#define AUDIT_SEED 0xcbf29ce484222325ULL

/* Tile IDs used by pipeline stages to stamp msg.decided_by. */
#define TILE_ID_TKNORM "tknorm"
#define TILE_ID_TKDEDU "tkdedu"
#define TILE_ID_TKPOLY "tkpoly"

/* PolicyOutcome — must match all 7 values from Zig PolicyOutcome enum. */
typedef enum {
    POLICY_ALLOW,
    POLICY_DENY,
    POLICY_REQUIRE_APPROVAL,
    POLICY_MALFORMED_DROP,
    POLICY_DUPLICATE_DROP,
    POLICY_ESCALATE,
    POLICY_REQUIRE_MORE_EVIDENCE,
} PolicyOutcome;

/* PolicyDecisionPayload — matches Zig PolicyDecisionPayload. */
typedef struct {
    PolicyOutcome outcome;
    uint32_t rule_id;
    uint8_t failed_scope_dim[32];
    uint64_t source_event_hash;
    uint32_t catalog_schema_version;
    uint8_t taxonomy_id[32];
    uint32_t taxonomy_version;
    uint8_t classification_code[32];
} PolicyDecisionPayload;

/* AuditHeader — matches Zig Header struct field-for-field. */
typedef struct {
    uint16_t schema_version;
    uint64_t run_id;
    uint64_t seq;
    uint64_t source_offset;
    uint8_t tile_id[6];
    uint64_t logical_actor_id;
    uint8_t policy_version[32];
    /* 128-bit capability envelope ID — portable across GCC/Clang/MSVC. */
    uint8_t capability_envelope_id[16];
    uint64_t timestamp_ns;
    uint64_t prev_hash;
    uint64_t record_hash;
    uint8_t version[64];
    uint8_t platform_tier[64];
    uint8_t isolation_tier[64];
    uint8_t release_digest[64];
    uint8_t manifest_id[64];
} AuditHeader;

/* Layout helpers — C-side size/alignment so Zig can verify parity.
   audit_schema.h is the single source of truth for the Header layout. */
size_t audit_header_sizeof(void);
size_t audit_header_alignof(void);

/* AuditEvent — matches Zig AuditEvent struct. */
typedef struct {
    AuditHeader header;
    /* policy_decision payload — the only payload the stem tile uses. */
    PolicyDecisionPayload policy_decision;
} AuditEvent;

#endif /* __AUDIT_SCHEMA_H__ */
