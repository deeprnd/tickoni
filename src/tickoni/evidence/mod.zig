/// Evidence linking module for V2.22.S7.
///
/// Provides structs for linking evidence artifacts to roadmap stories:
/// - EvidenceBundle — aggregate of evidence references
/// - EvidenceLink — single file reference with SHA256 hash
/// - EvidenceIndex — index document with links and metadata
///
/// Current implementation is a scaffold with NotImplemented errors.
/// Full serialization and hash computation are marked TODO.
const std = @import("std");

pub const log = std.log.scoped(.evidence);

/// Reference to a support matrix document.
pub const support_matrix_ref: []const u8 = "doc/knowledge/platform-tiers.md";

/// Reference to the version/sample output.
pub const version_ref: []const u8 = "doc/execution/audits/stories/V2.22.S7-version-output.md";

/// Reference to the doctor sample output.
pub const doctor_ref: []const u8 = "doc/execution/audits/stories/V2.22.S7-doctor-output.md";

/// Reference to the demo output.
pub const demo_ref: []const u8 = "doc/execution/audits/stories/V2.22.S7-demo-output.md";

/// Reference to the audit JSONL sample.
pub const audit_ref: []const u8 = "doc/execution/audits/stories/V2.22.S7-audit-sample.md";

/// Reference to the replay capsule sample.
pub const replay_ref: []const u8 = "doc/execution/audits/stories/V2.22.S7-replay-capsule.md";

/// Reference to the blocked flow diagnostic.
pub const blocked_flow_ref: []const u8 = "doc/execution/audits/stories/V2.22.S7-blocked-flow.md";

/// Reference to the conformance result.
pub const conformance_ref: []const u8 = "doc/execution/audits/stories/V2.22.S7-conformance-result.md";

/// A single evidence link referencing a file path and its SHA256 hash.
pub const EvidenceLink = struct {
    file_path: []const u8,
    sha256_hash: [64]u8, // hex-encoded SHA256 (64 hex chars)

    pub fn init(file_path: []const u8) EvidenceLink {
        log.warn("EvidenceLink.init({s}) — TODO: compute SHA256 hash", .{file_path});
        return EvidenceLink{
            .file_path = file_path,
            .sha256_hash = undefined,
        };
    }

    /// Serialize this link as JSON bytes to an allocator.
    pub fn toJson(self: EvidenceLink, gpa: std.mem.Allocator) ![]u8 {
        log.warn("EvidenceLink.toJson() — TODO: implement JSON serialization", .{});
        var buf = try std.ArrayList(u8).initCapacity(gpa, 0);
        errdefer buf.deinit(gpa);
        try buf.append(gpa, '{');
        try buf.appendSlice(gpa, "\"file_path\":\"");
        try buf.appendSlice(gpa, self.file_path);
        try buf.appendSlice(gpa, "\",\"sha256_hash\":\"not_implemented\"}");
        return buf.toOwnedSlice(gpa);
    }
};

/// A bundle of evidence references for a story closure.
pub const EvidenceBundle = struct {
    support_matrix_ref: []const u8 = "doc/knowledge/platform-tiers.md",
    version_ref: []const u8 = "doc/execution/audits/stories/V2.22.S7-version-output.md",
    doctor_ref: []const u8 = "doc/execution/audits/stories/V2.22.S7-doctor-output.md",
    demo_ref: []const u8 = "doc/execution/audits/stories/V2.22.S7-demo-output.md",
    audit_ref: []const u8 = "doc/execution/audits/stories/V2.22.S7-audit-sample.md",
    replay_ref: []const u8 = "doc/execution/audits/stories/V2.22.S7-replay-capsule.md",
    blocked_flow_ref: []const u8 = "doc/execution/audits/stories/V2.22.S7-blocked-flow.md",
    conformance_ref: []const u8 = "doc/execution/audits/stories/V2.22.S7-conformance-result.md",

    pub fn init() EvidenceBundle {
        log.warn("EvidenceBundle.init() — scaffold, TODO: populate with actual artifacts", .{});
        return EvidenceBundle{};
    }

    /// Convert all references into an array of EvidenceLink entries.
    pub fn toLinks(self: *const EvidenceBundle, gpa: std.mem.Allocator) ![]EvidenceLink {
        _ = self;
        _ = gpa;
        unreachable; // Not yet implemented
    }

    /// Serialize the entire bundle as JSON bytes to an allocator.
    pub fn toJson(self: *const EvidenceBundle, gpa: std.mem.Allocator) ![]u8 {
        var buf = try std.ArrayList(u8).initCapacity(gpa, 0);
        errdefer buf.deinit(gpa);
        try buf.append(gpa, '{');
        try buf.appendSlice(gpa, "\"support_matrix\":\"");
        try buf.appendSlice(gpa, self.support_matrix_ref);
        try buf.appendSlice(gpa, "\",\"version\":\"");
        try buf.appendSlice(gpa, self.version_ref);
        try buf.appendSlice(gpa, "\",\"doctor\":\"");
        try buf.appendSlice(gpa, self.doctor_ref);
        try buf.appendSlice(gpa, "\",\"demo\":\"");
        try buf.appendSlice(gpa, self.demo_ref);
        try buf.appendSlice(gpa, "\",\"audit\":\"");
        try buf.appendSlice(gpa, self.audit_ref);
        try buf.appendSlice(gpa, "\",\"replay\":\"");
        try buf.appendSlice(gpa, self.replay_ref);
        try buf.appendSlice(gpa, "\",\"blocked_flow\":\"");
        try buf.appendSlice(gpa, self.blocked_flow_ref);
        try buf.appendSlice(gpa, "\",\"conformance\":\"");
        try buf.appendSlice(gpa, self.conformance_ref);
        try buf.appendSlice(gpa, "\"}");
        return buf.toOwnedSlice(gpa);
    }
};

/// An evidence index document that lists all evidence links with metadata.
pub const EvidenceIndex = struct {
    title: []const u8,
    version: []const u8,
    generated_at: []const u8,
    links: []EvidenceLink,

    pub fn init(gpa: std.mem.Allocator, title: []const u8, version: []const u8, generated_at: []const u8) !EvidenceIndex {
        log.warn("EvidenceIndex.init() — TODO: implement hash computation for links", .{});
        return EvidenceIndex{
            .title = try gpa.dupe(u8, title),
            .version = try gpa.dupe(u8, version),
            .generated_at = try gpa.dupe(u8, generated_at),
            .links = try gpa.alloc(EvidenceLink, 0),
        };
    }

    pub fn deinit(self: *EvidenceIndex, gpa: std.mem.Allocator) void {
        gpa.free(self.title);
        gpa.free(self.version);
        gpa.free(self.generated_at);
        gpa.free(self.links);
    }

    /// Add a link to the evidence index.
    pub fn addLink(self: *EvidenceIndex, gpa: std.mem.Allocator, link: EvidenceLink) !void {
        log.warn("EvidenceIndex.addLink() — TODO: implement with hash computation", .{});
        self.links = try gpa.realloc(self.links, self.links.len + 1);
        self.links[self.links.len - 1] = link;
    }

    /// Serialize the index as JSON bytes to an allocator.
    pub fn toJson(self: *const EvidenceIndex, gpa: std.mem.Allocator) ![]u8 {
        log.warn("EvidenceIndex.toJson() — TODO: implement", .{});
        var buf = try std.ArrayList(u8).initCapacity(gpa, 0);
        errdefer buf.deinit(gpa);
        try buf.append(gpa, '{');
        try buf.appendSlice(gpa, "\"title\":\"");
        try buf.appendSlice(gpa, self.title);
        try buf.appendSlice(gpa, "\",\"version\":\"");
        try buf.appendSlice(gpa, self.version);
        try buf.appendSlice(gpa, "\",\"generated_at\":\"");
        try buf.appendSlice(gpa, self.generated_at);
        try buf.appendSlice(gpa, "\",\"links\":[]");
        try buf.append(gpa, '}');
        return buf.toOwnedSlice(gpa);
    }
};

/// Compute SHA256 hash of a file's contents.
/// Returns hex-encoded hash string.
pub fn computeFileHash(gpa: std.mem.Allocator, file_path: []const u8) ![]u8 {
    log.warn("computeFileHash({s}) — TODO: implement actual SHA256 computation", .{file_path});
    return try gpa.dupe(u8, "not_implemented_hash_placeholder");
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "EvidenceBundle init returns default refs" {
    const bundle = EvidenceBundle.init();
    try std.testing.expectEqualStrings("doc/knowledge/platform-tiers.md", bundle.support_matrix_ref);
    try std.testing.expectEqualStrings("doc/execution/audits/stories/V2.22.S7-version-output.md", bundle.version_ref);
    try std.testing.expectEqualStrings("doc/execution/audits/stories/V2.22.S7-doctor-output.md", bundle.doctor_ref);
    try std.testing.expectEqualStrings("doc/execution/audits/stories/V2.22.S7-demo-output.md", bundle.demo_ref);
    try std.testing.expectEqualStrings("doc/execution/audits/stories/V2.22.S7-audit-sample.md", bundle.audit_ref);
    try std.testing.expectEqualStrings("doc/execution/audits/stories/V2.22.S7-replay-capsule.md", bundle.replay_ref);
    try std.testing.expectEqualStrings("doc/execution/audits/stories/V2.22.S7-blocked-flow.md", bundle.blocked_flow_ref);
    try std.testing.expectEqualStrings("doc/execution/audits/stories/V2.22.S7-conformance-result.md", bundle.conformance_ref);
}

test "EvidenceBundle toJson produces valid JSON" {
    const bundle = EvidenceBundle.init();
    const json_str = try bundle.toJson(std.testing.allocator);
    defer std.testing.allocator.free(json_str);

    // Parse the JSON to validate it's well-formed
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        json_str,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
}

test "EvidenceBundle toJson contains all required fields" {
    const bundle = EvidenceBundle.init();
    const json_str = try bundle.toJson(std.testing.allocator);
    defer std.testing.allocator.free(json_str);

    try std.testing.expect(std.mem.indexOf(u8, json_str, "support_matrix") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"version\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "doctor") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "audit") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "replay") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "blocked_flow") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "conformance") != null);
}

test "EvidenceLink init creates valid link" {
    const path = "doc/execution/test-sample.json";
    const link = EvidenceLink.init(path);
    try std.testing.expectEqualStrings(path, link.file_path);
}

test "EvidenceLink toJson produces valid JSON" {
    const path = "doc/execution/test-sample.json";
    const link = EvidenceLink.init(path);
    const json_str = try link.toJson(std.testing.allocator);
    defer std.testing.allocator.free(json_str);

    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        json_str,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "file_path") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "sha256_hash") != null);
}

test "EvidenceIndex init allocates and deinit frees" {
    var index = try EvidenceIndex.init(
        std.testing.allocator,
        "V2.22.S7 Evidence Index",
        "1.0",
        "2026-08-11",
    );
    defer index.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("V2.22.S7 Evidence Index", index.title);
    try std.testing.expectEqualStrings("1.0", index.version);
    try std.testing.expectEqualStrings("2026-08-11", index.generated_at);
    try std.testing.expectEqual(@as(usize, 0), index.links.len);
}

test "EvidenceIndex addLink grows links array" {
    var index = try EvidenceIndex.init(
        std.testing.allocator,
        "Test Index",
        "1.0",
        "2026-08-11",
    );
    defer index.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), index.links.len);
    const link = EvidenceLink.init("test.txt");
    try index.addLink(std.testing.allocator, link);
    try std.testing.expectEqual(@as(usize, 1), index.links.len);
}

test "EvidenceIndex toJson produces valid JSON" {
    var index = try EvidenceIndex.init(
        std.testing.allocator,
        "Test Index",
        "1.0",
        "2026-08-11",
    );
    defer index.deinit(std.testing.allocator);

    const json_str = try index.toJson(std.testing.allocator);
    defer std.testing.allocator.free(json_str);

    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        json_str,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
}

test "EvidenceIndex toJson contains all metadata fields" {
    var index = try EvidenceIndex.init(
        std.testing.allocator,
        "Test Index",
        "1.0",
        "2026-08-11",
    );
    defer index.deinit(std.testing.allocator);

    const json_str = try index.toJson(std.testing.allocator);
    defer std.testing.allocator.free(json_str);

    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"title\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"version\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"generated_at\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"links\"") != null);
}

test "empty bundle validation" {
    const bundle = EvidenceBundle.init();
    const json_str = try bundle.toJson(std.testing.allocator);
    defer std.testing.allocator.free(json_str);
    try std.testing.expect(json_str.len > 0);
}

test "EvidenceBundle ref constants match plan" {
    try std.testing.expectEqualStrings(
        "doc/knowledge/platform-tiers.md",
        support_matrix_ref,
    );
    try std.testing.expectEqualStrings(
        "doc/execution/audits/stories/V2.22.S7-version-output.md",
        version_ref,
    );
}
