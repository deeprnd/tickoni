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
pub const version_ref: []const u8 = "doc/execution/V2.22.S7/version-sample.txt";

/// Reference to the doctor sample output.
pub const doctor_ref: []const u8 = "doc/execution/V2.22.S7/doctor-sample.txt";

/// Reference to the demo output.
pub const demo_ref: []const u8 = "doc/execution/V2.22.S7/demo-output.txt";

/// Reference to the audit JSONL sample.
pub const audit_ref: []const u8 = "doc/execution/V2.22.S7/audit-sample.jsonl";

/// Reference to the replay capsule sample.
pub const replay_ref: []const u8 = "doc/execution/V2.22.S7/replay-capsule.json";

/// Reference to the blocked flow diagnostic.
pub const blocked_flow_ref: []const u8 = "doc/execution/V2.22.S7/blocked-flow-output.txt";

/// Reference to the conformance result.
pub const conformance_ref: []const u8 = "doc/execution/V2.22.S7/conformance-result.json";

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

    /// Serialize this link as a JSON object to the given writer.
    pub fn toJson(self: EvidenceLink, writer: anytype) !void {
        log.warn("EvidenceLink.toJson() — TODO: implement JSON serialization", .{});
        try writer.beginObject();
        try writer.objectField("file_path");
        try writer.string(self.file_path);
        try writer.objectField("sha256_hash");
        try writer.string("not_implemented");
        try writer.endObject();
    }
};

/// A bundle of evidence references for a story closure.
pub const EvidenceBundle = struct {
    support_matrix_ref: []const u8 = "doc/knowledge/platform-tiers.md",
    version_ref: []const u8 = "doc/execution/V2.22.S7/version-sample.txt",
    doctor_ref: []const u8 = "doc/execution/V2.22.S7/doctor-sample.txt",
    demo_ref: []const u8 = "doc/execution/V2.22.S7/demo-output.txt",
    audit_ref: []const u8 = "doc/execution/V2.22.S7/audit-sample.jsonl",
    replay_ref: []const u8 = "doc/execution/V2.22.S7/replay-capsule.json",
    blocked_flow_ref: []const u8 = "doc/execution/V2.22.S7/blocked-flow-output.txt",
    conformance_ref: []const u8 = "doc/execution/V2.22.S7/conformance-result.json",

    pub fn init() EvidenceBundle {
        log.warn("EvidenceBundle.init() — scaffold, TODO: populate with actual artifacts", .{});
        return EvidenceBundle{};
    }

    /// Convert all references into an array of EvidenceLink entries.
    pub fn toLinks(self: *const EvidenceBundle, gpa: std.mem.Allocator) ![][].EvidenceLink {
        log.warn("EvidenceBundle.toLinks() — TODO: implement", .{});
        _ = self;
        _ = gpa;
        unreachable; // Not yet implemented
    }

    /// Serialize the entire bundle as JSON.
    pub fn toJson(self: *const EvidenceBundle, gpa: std.mem.Allocator, writer: anytype) !void {
        log.warn("EvidenceBundle.toJson() — TODO: implement", .{});
        _ = self;
        _ = gpa;
        try writer.beginObject();
        try writer.objectField("support_matrix");
        try writer.string(self.support_matrix_ref);
        try writer.objectField("version");
        try writer.string(self.version_ref);
        try writer.objectField("doctor");
        try writer.string(self.doctor_ref);
        try writer.objectField("demo");
        try writer.string(self.demo_ref);
        try writer.objectField("audit");
        try writer.string(self.audit_ref);
        try writer.objectField("replay");
        try writer.string(self.replay_ref);
        try writer.objectField("blocked_flow");
        try writer.string(self.blocked_flow_ref);
        try writer.objectField("conformance");
        try writer.string(self.conformance_ref);
        try writer.endObject();
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

    /// Serialize the index as a JSON object to the given writer.
    pub fn toJson(self: *const EvidenceIndex, writer: anytype) !void {
        log.warn("EvidenceIndex.toJson() — TODO: implement", .{});
        try writer.beginObject();
        try writer.objectField("title");
        try writer.string(self.title);
        try writer.objectField("version");
        try writer.string(self.version);
        try writer.objectField("generated_at");
        try writer.string(self.generated_at);
        try writer.objectField("links");
        try writer.beginArray();
        try writer.endArray();
        try writer.endObject();
    }
};

/// Compute SHA256 hash of a file's contents.
/// Returns hex-encoded hash string.
pub fn computeFileHash(gpa: std.mem.Allocator, file_path: []const u8) ![]u8 {
    log.warn("computeFileHash({s}) — TODO: implement actual SHA256 computation", .{file_path});
    _ = gpa;
    _ = file_path;
    return try gpa.dupe(u8, "not_implemented_hash_placeholder");
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "EvidenceBundle init returns default refs" {
    const bundle = EvidenceBundle.init();
    try std.testing.expectEqualStrings("doc/knowledge/platform-tiers.md", bundle.support_matrix_ref);
    try std.testing.expectEqualStrings("doc/execution/V2.22.S7/version-sample.txt", bundle.version_ref);
    try std.testing.expectEqualStrings("doc/execution/V2.22.S7/doctor-sample.txt", bundle.doctor_ref);
    try std.testing.expectEqualStrings("doc/execution/V2.22.S7/demo-output.txt", bundle.demo_ref);
    try std.testing.expectEqualStrings("doc/execution/V2.22.S7/audit-sample.jsonl", bundle.audit_ref);
    try std.testing.expectEqualStrings("doc/execution/V2.22.S7/replay-capsule.json", bundle.replay_ref);
    try std.testing.expectEqualStrings("doc/execution/V2.22.S7/blocked-flow-output.txt", bundle.blocked_flow_ref);
    try std.testing.expectEqualStrings("doc/execution/V2.22.S7/conformance-result.json", bundle.conformance_ref);
}

test "EvidenceBundle toJson produces valid JSON object" {
    const bundle = EvidenceBundle.init();
    var buffer: [1024]u8 = undefined;
    var writer = std.json.FmtWrite.init(&buffer);

    try bundle.toJson(&bundle, std.testing.allocator, &writer);
    const json_str = try std.fmt.allocPrint(std.testing.allocator, "{s}", .{writer.buffered()});
    defer std.testing.allocator.free(json_str);

    // Parse the JSON to validate it's well-formed
    const parsed = try std.json.parseFromJson(std.json.Value, json_str, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
}

test "EvidenceBundle toJson contains all required fields" {
    const bundle = EvidenceBundle.init();
    var buffer: [1024]u8 = undefined;
    var writer = std.json.FmtWrite.init(&buffer);

    try bundle.toJson(&bundle, std.testing.allocator, &writer);
    const json_str = try std.fmt.allocPrint(std.testing.allocator, "{s}", .{writer.buffered()});
    defer std.testing.allocator.free(json_str);

    try std.testing.expect(std.mem.indexOf(u8, json_str, "support_matrix") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "version") != null);
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

test "EvidenceLink toJson produces valid JSON object" {
    const path = "doc/execution/test-sample.json";
    const link = EvidenceLink.init(path);
    var buffer: [256]u8 = undefined;
    var writer = std.json.FmtWrite.init(&buffer);

    try link.toJson(&link, &writer);
    const json_str = try std.fmt.allocPrint(std.testing.allocator, "{s}", .{writer.buffered()});
    defer std.testing.allocator.free(json_str);

    const parsed = try std.json.parseFromJson(std.json.Value, json_str, .{});
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

test "EvidenceIndex toJson produces valid JSON object" {
    var index = try EvidenceIndex.init(
        std.testing.allocator,
        "Test Index",
        "1.0",
        "2026-08-11",
    );
    defer index.deinit(std.testing.allocator);

    var buffer: [512]u8 = undefined;
    var writer = std.json.FmtWrite.init(&buffer);
    try index.toJson(&index, &writer);
    const json_str = try std.fmt.allocPrint(std.testing.allocator, "{s}", .{writer.buffered()});
    defer std.testing.allocator.free(json_str);

    const parsed = try std.json.parseFromJson(std.json.Value, json_str, .{});
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

    var buffer: [512]u8 = undefined;
    var writer = std.json.FmtWrite.init(&buffer);
    try index.toJson(&index, &writer);
    const json_str = try std.fmt.allocPrint(std.testing.allocator, "{s}", .{writer.buffered()});
    defer std.testing.allocator.free(json_str);

    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"title\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"version\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"generated_at\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"links\"") != null);
}

test "empty bundle validation" {
    const bundle = EvidenceBundle.init();
    var buffer: [256]u8 = undefined;
    var writer = std.json.FmtWrite.init(&buffer);

    // Even with default refs, toJson should work
    try bundle.toJson(&bundle, std.testing.allocator, &writer);
    try std.testing.expect(writer.buffered().len > 0);
}

test "EvidenceBundle ref constants match plan" {
    try std.testing.expectEqualStrings(
        "doc/knowledge/platform-tiers.md",
        support_matrix_ref,
    );
    try std.testing.expectEqualStrings(
        "doc/execution/V2.22.S7/version-sample.txt",
        version_ref,
    );
}
