// Re-export everything from the audit_schema module (types) and
// audit_codec module (build/format/hash functions) so consumers can
// use @import("audit") as a single entry point.
const audit_schema = @import("audit_schema");
const audit_codec = @import("audit_codec");
const c_abi_audit = @import("c_abi_audit");

pub const audit_schema_version = audit_schema.audit_schema_version;
pub const PolicyOutcome = audit_schema.PolicyOutcome;
pub const LimitType = audit_schema.LimitType;
pub const RecordType = audit_schema.RecordType;
pub const SourceEventPayload = audit_schema.SourceEventPayload;
pub const NormalizationPayload = audit_schema.NormalizationPayload;
pub const PolicyDecisionPayload = audit_schema.PolicyDecisionPayload;
pub const ModelCallPayload = audit_schema.ModelCallPayload;
pub const FinancialAdapterCallPayload = audit_schema.FinancialAdapterCallPayload;
pub const ProposalPayload = audit_schema.ProposalPayload;
pub const DestinationCheckPayload = audit_schema.DestinationCheckPayload;
pub const LimitCheckPayload = audit_schema.LimitCheckPayload;
pub const ApprovalRequiredPayload = audit_schema.ApprovalRequiredPayload;
pub const DenialPayload = audit_schema.DenialPayload;
pub const TelemetryCheckpointPayload = audit_schema.TelemetryCheckpointPayload;
pub const ReplayResultPayload = audit_schema.ReplayResultPayload;
pub const DeduplicationPayload = audit_schema.DeduplicationPayload;
pub const CaseCreationPayload = audit_schema.CaseCreationPayload;
pub const Header = audit_schema.Header;
pub const AuditEvent = audit_schema.AuditEvent;

pub const max_binary_len = audit_codec.max_binary_len;
pub const ParsedBinary = audit_codec.ParsedBinary;
pub const buildEvent = audit_codec.buildEvent;
pub const computeRecordHash = audit_codec.computeRecordHash;
pub const auditEventsEql = audit_codec.auditEventsEql;
pub const checkSchemaVersion = audit_codec.checkSchemaVersion;
pub const parseRecordType = audit_codec.parseRecordType;
pub const peekBinaryLen = audit_codec.peekBinaryLen;
pub const formatBinary = audit_codec.formatBinary;
pub const formatJsonLine = audit_codec.formatJsonLine;
pub const parseBinary = audit_codec.parseBinary;

// ─── C interop (tk_audit_stem.c) ────────────────────────────────────────────
// Thin Zig wrappers over the C stem tile. Consumers that need the stem
// tile interop (run tile descriptor, scratch footprint) use these.
// Domain types and codecs are above; C interop stays separate in this
// module for clarity, but everything is accessible via @import("audit").

/// Opaque handle for fd_topo_run_tile_t. Only shim code knows the real layout.
pub const TopoRunTile = c_abi_audit.TopoRunTile;

/// Returns a pointer to the TK_AUDIT_RUN tile descriptor.
pub const getAuditRunTile = c_abi_audit.getAuditRunTile;

/// Returns the scratch footprint (in bytes) for the audit tile.
pub const auditScratchFootprint = c_abi_audit.auditScratchFootprint;
