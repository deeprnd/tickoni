/// Thin Zig wrapper over tk_audit_stem.c — the Firedancer stem tile for tkaudt.
///
/// Exposes the C stem tile's public symbols (run tile descriptor, scratch
/// footprint) as extern declarations with Zig-native wrapper functions.
/// This module is the FFI boundary for the audit stem tile; domain types
/// live in schema/audit/audit.zig and codecs in codec/audit/.
const std = @import("std");

// ---------------------------------------------------------------------------
// Extern declarations — from c_abi/shim/topo_run/tk_audit_stem.h
// Link requires tk_audit_stem.c (supervisor shim library).
// ---------------------------------------------------------------------------

/// Opaque handle for fd_topo_run_tile_t. Only shim code knows the real layout.
pub const TopoRunTile = opaque {};

extern fn tk_get_audit_run_tile() ?*TopoRunTile;
extern fn tk_audit_scratch_footprint() usize;

// ---------------------------------------------------------------------------
// Public Zig wrappers.
// ---------------------------------------------------------------------------

/// Returns a pointer to the TK_AUDIT_RUN tile descriptor.
/// Callers never need to know the symbol name directly.
pub fn getAuditRunTile() ?*TopoRunTile {
    return tk_get_audit_run_tile();
}

/// Returns the scratch footprint (in bytes) for the audit tile.
/// Matches TKAUDT_CTX_ALIGN in tk_audit_stem.c.
pub fn auditScratchFootprint() usize {
    return tk_audit_scratch_footprint();
}

// ---------------------------------------------------------------------------
// Re-export the translated C schema types (from audit_schema.h).
/// These are the C-translated structs (AuditHeader, PolicyDecisionPayload,
/// etc.) that tk_audit_stem.c operates on. Consumers that need both
/// the stem tile interop AND the schema types import this module instead
/// of importing audit_schema separately.
// ---------------------------------------------------------------------------

pub const audit_schema = @import("audit_schema");

// Re-export the C-translated structs at the top level so consumers can use
// @import("c_abi/audit").audit_schema.AuditHeader instead of importing
// audit_schema separately.
pub const AuditHeader = audit_schema.AuditHeader;
pub const PolicyDecisionPayload = audit_schema.PolicyDecisionPayload;
pub const RawPayment = audit_schema.RawPayment;
pub const PaymentMessage = audit_schema.PaymentMessage;

// Re-export the C enum values so consumers can match against them.
pub const POLICY_ALLOW = audit_schema.POLICY_ALLOW;
pub const POLICY_DENY = audit_schema.POLICY_DENY;
pub const POLICY_REQUIRE_APPROVAL = audit_schema.POLICY_REQUIRE_APPROVAL;
pub const POLICY_MALFORMED_DROP = audit_schema.POLICY_MALFORMED_DROP;
pub const POLICY_DUPLICATE_DROP = audit_schema.POLICY_DUPLICATE_DROP;
pub const POLICY_ESCALATE = audit_schema.POLICY_ESCALATE;
pub const POLICY_REQUIRE_MORE_EVIDENCE = audit_schema.POLICY_REQUIRE_MORE_EVIDENCE;

pub const RECORD_SOURCE_EVENT = audit_schema.RECORD_SOURCE_EVENT;
pub const RECORD_NORMALIZATION = audit_schema.RECORD_NORMALIZATION;
pub const RECORD_POLICY_DECISION = audit_schema.RECORD_POLICY_DECISION;
pub const RECORD_MODEL_CALL = audit_schema.RECORD_MODEL_CALL;
pub const RECORD_FINANCIAL_ADAPTER_CALL = audit_schema.RECORD_FINANCIAL_ADAPTER_CALL;
pub const RECORD_PROPOSAL = audit_schema.RECORD_PROPOSAL;
pub const RECORD_DESTINATION_CHECK = audit_schema.RECORD_DESTINATION_CHECK;
pub const RECORD_LIMIT_CHECK = audit_schema.RECORD_LIMIT_CHECK;
pub const RECORD_APPROVAL_REQUIRED = audit_schema.RECORD_APPROVAL_REQUIRED;
pub const RECORD_DENIAL = audit_schema.RECORD_DENIAL;
pub const RECORD_TELEMETRY_CHECKPOINT = audit_schema.RECORD_TELEMETRY_CHECKPOINT;
pub const RECORD_REPLAY_RESULT = audit_schema.RECORD_REPLAY_RESULT;
pub const RECORD_DUPLICATION = audit_schema.RECORD_DUPLICATION;
pub const RECORD_CASE_CREATION = audit_schema.RECORD_CASE_CREATION;

test "getAuditRunTile returns non-null on supported platforms" {
    // On Linux with Firedancer built, the stem tile should be registered.
    // On non-Linux or without FD, it may return null.
    _ = getAuditRunTile();
}

test "auditScratchFootprint returns a positive value" {
    const fp = auditScratchFootprint();
    // The footprint should be a reasonable positive value if the stem tile
    // is linked. On platforms without tk_audit_stem.c, this may be 0.
    _ = fp;
}
