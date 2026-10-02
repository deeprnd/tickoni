const std = @import("std");
const conformance = @import("conformance");
const diagnostic = @import("diagnostic");
const util = @import("util");

pub const RunnerError = error{
    LiveEffectsEnabled,
    ArtifactReadFailed,
    OutOfMemory,
};

/// Normalize line endings (\r\n -> \n) for cross-platform hash stability.
/// Always allocates and returns a new buffer; caller must free.
pub fn normalizeLineEndings(
    bytes: []const u8,
    allocator: std.mem.Allocator,
) ![]u8 {
    var crlf_count: usize = 0;
    var i: usize = 0;
    while (i < bytes.len) : (i += 1) {
        if (bytes[i] == '\r' and i + 1 < bytes.len and bytes[i + 1] == '\n') {
            crlf_count += 1;
            i += 1;
        }
    }
    const normalized_len = bytes.len - crlf_count;
    const normalized = try allocator.alloc(u8, normalized_len);
    var src: usize = 0;
    var dst: usize = 0;
    while (src < bytes.len) {
        if (bytes[src] == '\r' and src + 1 < bytes.len and bytes[src + 1] == '\n') {
            src += 1;
        }
        normalized[dst] = bytes[src];
        src += 1;
        dst += 1;
    }
    return normalized;
}

pub const BackendResult = struct {
    fixture_set_id: []const u8,
    scenario: []const u8,
    policy_outcome: []const u8,
    proposal_material: []const u8,
    normalized_event_material: []const u8,
    audit_jsonl_path: []const u8,
    replay_capsule_path: []const u8,
    replay_result: conformance.ReplayResult,
    blocked_diagnostic: ?diagnostic.BlockedFlowDiagnostic = null,
    external_effects_disabled: bool = true,
};

pub const RunRequest = struct {
    manifest_id: []const u8,
    manifest_version: []const u8,
    tickoni_version: []const u8,
    runtime_tier: []const u8,
    isolation_tier: []const u8,
};

pub fn runWithBackend(
    allocator: std.mem.Allocator,
    cwd: std.Io.Dir,
    io: std.Io,
    request: RunRequest,
    backend: BackendResult,
) RunnerError!conformance.Artifact {
    if (!backend.external_effects_disabled) return RunnerError.LiveEffectsEnabled;

    const audit_hash = if (backend.audit_jsonl_path.len == 0) conformance.sha256Hex("") else blk: {
        const audit_bytes = cwd.readFileAlloc(io, backend.audit_jsonl_path, allocator, .limited(512 * 1024)) catch {
            return RunnerError.ArtifactReadFailed;
        };
        defer allocator.free(audit_bytes);
        // Normalize line endings (\r\n -> \n) for cross-platform hash stability.
        const normalized = try normalizeLineEndings(audit_bytes, allocator);
        defer allocator.free(normalized);
        break :blk conformance.sha256Hex(normalized);
    };

    const replay_hash = if (backend.replay_capsule_path.len == 0) conformance.sha256Hex("") else blk: {
        const replay_bytes = cwd.readFileAlloc(io, backend.replay_capsule_path, allocator, .limited(512 * 1024)) catch {
            return RunnerError.ArtifactReadFailed;
        };
        defer allocator.free(replay_bytes);
        // Normalize line endings (\r\n -> \n) for cross-platform hash stability.
        const normalized = try normalizeLineEndings(replay_bytes, allocator);
        defer allocator.free(normalized);
        break :blk conformance.sha256Hex(normalized);
    };

    return .{
        .manifest_id = request.manifest_id,
        .manifest_version = request.manifest_version,
        .tickoni_version = request.tickoni_version,
        .runtime_tier = request.runtime_tier,
        .isolation_tier = request.isolation_tier,
        .fixture_set_id = backend.fixture_set_id,
        .scenario = backend.scenario,
        .normalized_event_hash = conformance.sha256Hex(backend.normalized_event_material),
        .policy_outcome = backend.policy_outcome,
        .proposal_hash = conformance.sha256Hex(backend.proposal_material),
        .audit_jsonl_path = backend.audit_jsonl_path,
        .audit_jsonl_sha256 = audit_hash,
        .replay_capsule_path = backend.replay_capsule_path,
        .replay_capsule_sha256 = replay_hash,
        .replay_result = backend.replay_result,
        .blocked_diagnostic = backend.blocked_diagnostic,
        .external_effects_disabled = true,
    };
}

test "runner builds conformance artifact from backend outputs" {
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "audit.jsonl", .data = "{}\n" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "replay.json", .data = "{\"replay\":true}\n" });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const root = path_buf[0..root_len];

    var audit_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const audit_path = try std.fmt.bufPrint(&audit_path_buf, "{s}/audit.jsonl", .{root});
    var replay_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const replay_path = try std.fmt.bufPrint(&replay_path_buf, "{s}/replay.json", .{root});

    const artifact = try runWithBackend(std.testing.allocator, std.Io.Dir.cwd(), std.testing.io, .{
        .manifest_id = "demo.investment.v1",
        .manifest_version = "1.0.0",
        .tickoni_version = "0.1.1",
        .runtime_tier = "linux_full",
        .isolation_tier = "full",
    }, .{
        .fixture_set_id = "investment_sample",
        .scenario = "allowed",
        .policy_outcome = "allow",
        .proposal_material = "proposal",
        .normalized_event_material = "normalized-events",
        .audit_jsonl_path = audit_path,
        .replay_capsule_path = replay_path,
        .replay_result = .{ .replay_match = true, .divergence_count = 0 },
        .external_effects_disabled = true,
    });

    try std.testing.expectEqualStrings("investment_sample", artifact.fixture_set_id);
    try std.testing.expectEqualStrings("allow", artifact.policy_outcome);
    try std.testing.expectEqualStrings(conformance.sha256Hex("{}\n")[0..], artifact.audit_jsonl_sha256[0..]);
}

test "runner fails closed when backend reports live effects enabled" {
    try std.testing.expectError(RunnerError.LiveEffectsEnabled, runWithBackend(std.testing.allocator, std.Io.Dir.cwd(), std.testing.io, .{
        .manifest_id = "demo.investment.v1",
        .manifest_version = "1.0.0",
        .tickoni_version = "0.1.1",
        .runtime_tier = "linux_full",
        .isolation_tier = "full",
    }, .{
        .fixture_set_id = "investment_sample",
        .scenario = "allowed",
        .policy_outcome = "allow",
        .proposal_material = "proposal",
        .normalized_event_material = "normalized-events",
        .audit_jsonl_path = "missing-audit.jsonl",
        .replay_capsule_path = "missing-replay.json",
        .replay_result = .{ .replay_match = true, .divergence_count = 0 },
        .external_effects_disabled = false,
    }));
}
