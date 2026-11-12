const audit = @import("audit/mod.zig");

pub const max_binary_len = audit.max_binary_len;
pub const ParsedBinary = audit.ParsedBinary;
pub const buildEvent = audit.buildEvent;
pub const computeRecordHash = audit.computeRecordHash;
pub const auditEventsEql = audit.auditEventsEql;
pub const checkSchemaVersion = audit.checkSchemaVersion;
pub const parseRecordType = audit.parseRecordType;
pub const peekBinaryLen = audit.peekBinaryLen;
pub const formatBinary = audit.formatBinary;
pub const parseBinary = audit.parseBinary;
pub const formatJsonLine = audit.formatJsonLine;
pub const jsonl = audit.jsonl;
