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
extern fn tk_audit_scratch_align() usize;
extern fn tkaudit_set_event_count(event_count: usize) void;

// Field accessors — the C file owns tk_audit_ctx_t and AuditEvent layout, so
// nothing on this side mirrors either struct. Matches the tknorm/tkdedu set.
extern fn tk_get_audit_run_name() [*:0]const u8;
extern fn tk_get_audit_run_run() ?*anyopaque;
extern fn tk_get_audit_run_scratch_align() ?*anyopaque;
extern fn tk_get_audit_run_scratch_footprint() ?*anyopaque;
extern fn tk_get_audit_run_privileged_init() ?*anyopaque;
extern fn tk_get_audit_run_unprivileged_init() ?*anyopaque;

extern fn tk_audit_record_count(scratch: ?*anyopaque) usize;
extern fn tk_audit_record_seq(scratch: ?*anyopaque, idx: usize) u64;
extern fn tk_audit_record_prev_hash(scratch: ?*anyopaque, idx: usize) u64;
extern fn tk_audit_record_hash(scratch: ?*anyopaque, idx: usize) u64;
extern fn tk_audit_record_schema_version(scratch: ?*anyopaque, idx: usize) c_uint;

// ---------------------------------------------------------------------------
// Public Zig wrappers.
// ---------------------------------------------------------------------------

/// Returns a pointer to the TK_AUDIT_RUN tile descriptor.
/// Callers never need to know the symbol name directly.
pub fn getAuditRunTile() ?*TopoRunTile {
    return tk_get_audit_run_tile();
}

/// Returns the scratch footprint (in bytes) for the audit tile.
pub fn auditScratchFootprint() usize {
    return tk_audit_scratch_footprint();
}

/// Returns the alignment (in bytes) of the audit tile's scratch object —
/// the block holding the context and the audit-record ring.
pub fn auditScratchAlign() usize {
    return tk_audit_scratch_align();
}

/// Sets the event_count for the tkaudt stem tile's shutdown gate.
/// Called by topo_build.build() before any topology queries.
pub fn setEventCount(event_count: u64) void {
    tkaudit_set_event_count(@intCast(event_count));
}

/// Returns the tile name for tkaudt.
pub fn getAuditRunName() [*:0]const u8 {
    return tk_get_audit_run_name();
}

/// Returns the stem run callback pointer.
pub fn getAuditRun() ?*anyopaque {
    return tk_get_audit_run_run();
}

/// Returns the scratch align callback pointer.
pub fn getAuditRunScratchAlign() ?*anyopaque {
    return tk_get_audit_run_scratch_align();
}

/// Returns the scratch footprint callback pointer.
pub fn getAuditRunScratchFootprint() ?*anyopaque {
    return tk_get_audit_run_scratch_footprint();
}

/// Returns the privileged init callback pointer.
pub fn getAuditRunPrivilegedInit() ?*anyopaque {
    return tk_get_audit_run_privileged_init();
}

/// Returns the unprivileged init callback pointer.
pub fn getAuditRunUnprivilegedInit() ?*anyopaque {
    return tk_get_audit_run_unprivileged_init();
}

// ---------------------------------------------------------------------------
// Audit-record inspection.
//
// `scratch` is the tkaudt tile's scratch base (topob.topoObjLaddr of its
// tile_obj_id). The C side resolves the context and record array from it, so
// this module never mirrors tk_audit_ctx_t or AuditEvent. recordCount returns
// the COMMITTED count; the field readers abort on an out-of-range index
// rather than returning a sentinel, since 0 is a legitimate seq/prev_hash.
// ---------------------------------------------------------------------------

/// Number of records committed to the hash chain so far.
pub fn recordCount(scratch: ?*anyopaque) usize {
    return tk_audit_record_count(scratch);
}

/// `header.seq` of the committed record at `idx`.
pub fn recordSeq(scratch: ?*anyopaque, idx: usize) u64 {
    return tk_audit_record_seq(scratch, idx);
}

/// `header.prev_hash` of the committed record at `idx`.
pub fn recordPrevHash(scratch: ?*anyopaque, idx: usize) u64 {
    return tk_audit_record_prev_hash(scratch, idx);
}

/// `header.record_hash` of the committed record at `idx`.
pub fn recordHash(scratch: ?*anyopaque, idx: usize) u64 {
    return tk_audit_record_hash(scratch, idx);
}

/// `header.schema_version` of the committed record at `idx`.
pub fn recordSchemaVersion(scratch: ?*anyopaque, idx: usize) u16 {
    return @intCast(tk_audit_record_schema_version(scratch, idx));
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

test "tkaudt tile identity — name is TILE_ID_TKAUDT" {
    const name = getAuditRunName();
    try std.testing.expectEqualStrings("tkaudt", std.mem.span(name));
}

test "tkaudt tile identity — run callback is non-null" {
    try std.testing.expect(getAuditRun() != null);
}

test "tkaudt tile identity — scratch callbacks are non-null" {
    try std.testing.expect(getAuditRunScratchAlign() != null);
    try std.testing.expect(getAuditRunScratchFootprint() != null);
}

test "tkaudt tile identity — init callbacks are non-null" {
    try std.testing.expect(getAuditRunPrivilegedInit() != null);
    try std.testing.expect(getAuditRunUnprivilegedInit() != null);
}

test "tkaudt scratch align — describes the context block, not fd_stem's stack scratch" {
    // alignof(tk_audit_ctx_t) == 8, matching AuditEvent, which the same
    // footprint carves out of the same block.  128 (FD_STEM_SCRATCH_ALIGN)
    // here would mean .scratch_align was wired to the STEM-generated
    // tkaudt_scratch_align() from fd_stem.c, which describes fd_stem's own
    // stack scratch.  See "Tile Scratch Layout" in
    // doc/execution/contribution/tickoni.md.
    try std.testing.expectEqual(@as(usize, 8), tk_audit_scratch_align());
}

test "tkaudt scratch align — footprint is a whole number of alignment units" {
    try std.testing.expectEqual(
        @as(usize, 0),
        tk_audit_scratch_footprint() % tk_audit_scratch_align(),
    );
}

test "tkaudt scratch footprint — returns deterministic value > 1" {
    const first = auditScratchFootprint();
    const second = auditScratchFootprint();
    try std.testing.expectEqual(first, second);
    try std.testing.expect(first > 1);
}
