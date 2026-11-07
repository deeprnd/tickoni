// Re-export everything from the audit_schema module (types) and
// audit_codec module (build/format/hash functions) so consumers can
// use @import("audit") as a single entry point.
const audit_schema = @import("audit_schema");
const audit_codec = @import("audit_codec");

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
