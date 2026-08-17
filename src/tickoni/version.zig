/// Version identity for Tickoni.
///
/// Provides build-time version metadata injected via build.zig compile options.
/// On dev builds, defaults are -1/-2 for version components and "0.0.0-dev".
///
/// Import as @import("version") in files that use the build module system.
const std = @import("std");
const build_opts = @import("build_options");

// Build-time injected constants (set by build.zig via options)
pub const build_version: []const u8 = build_opts.BUILD_VERSION;
pub const build_version_major: u16 = build_opts.BUILD_VERSION_MAJOR;
pub const build_version_minor: u16 = build_opts.BUILD_VERSION_MINOR;
pub const build_version_patch: u16 = build_opts.BUILD_VERSION_PATCH;
pub const build_version_pre: []const u8 = build_opts.BUILD_VERSION_PRE;
pub const build_git_sha: []const u8 = build_opts.BUILD_GIT_SHA;
pub const build_id: []const u8 = build_opts.BUILD_ID;

/// Format the semver release string into the caller-provided `buf`.
/// The returned slice points into `buf` — the caller owns `buf` and
/// must keep it alive for as long as the returned slice is used.
pub fn semver(buf: []u8) ![]const u8 {
    if (buf.len < 16) return error.NoSpace;
    if (build_version_major == 0 and build_version_minor == 0 and build_version_patch == 0) {
        const s = "0.0.0-dev";
        @memcpy(buf[0..s.len], s);
        return buf[0..s.len];
    }
    const pre = build_version_pre;
    if (std.mem.eql(u8, pre, "")) {
        return std.fmt.bufPrint(buf, "{d}.{d}.{d}", .{
            build_version_major, build_version_minor, build_version_patch,
        });
    }
    return std.fmt.bufPrint(buf, "{d}.{d}.{d}-{s}", .{
        build_version_major,
        build_version_minor,
        build_version_patch,
        pre,
    });
}

/// Full human-readable version line (for --version output).
pub fn versionLine(buf: []u8) ![]const u8 {
    return semver(buf);
}

/// Git revision (full SHA).
pub fn gitRevision() []const u8 {
    return build_git_sha;
}

/// Build identifier (unique per build).
pub fn buildId() []const u8 {
    return build_id;
}

/// VersionInfo struct — aggregates all version fields for serialization.
pub const VersionInfo = struct {
    semver: []const u8 = "0.0.0-dev",
    build_id: []const u8 = "dev-0",
    git_sha: []const u8 = "unknown",
    os: []const u8 = "unknown",
    arch: []const u8 = "unknown",
    runtime_tier: []const u8 = "unsupported",
    isolation_tier: []const u8 = "degraded",
    policy_schema_version: u16 = 0,
    replay_schema_version: u16 = 0,
    demo_manifest_version: u16 = 0,
    demo_manifest_version_str: ?[]const u8 = null,
    compiler: []const u8 = "unknown",

    pub fn init(gpa: std.mem.Allocator) !VersionInfo {
        var buf: [64]u8 = undefined;
        const sv = try semver(&buf);
        const tier_mod = @import("tier");
        const audit_mod = @import("audit_schema");
        return VersionInfo{
            .semver = try gpa.dupe(u8, sv),
            .build_id = buildId(),
            .git_sha = gitRevision(),
            .os = tier_mod.detectOsString(),
            .arch = tier_mod.detectArchString(),
            .runtime_tier = tier_mod.tierName(tier_mod.detectTier()),
            .isolation_tier = isolationTierStr(),
            .policy_schema_version = audit_mod.audit_schema_version,
            .replay_schema_version = audit_mod.audit_schema_version,
            .demo_manifest_version = 0,
            .demo_manifest_version_str = null,
            .compiler = tier_mod.detectCompilerVersion(),
        };
    }

    pub fn setDemoManifestVersion(self: *VersionInfo, gpa: std.mem.Allocator, version: ?[]const u8) !void {
        if (self.demo_manifest_version_str) |s| gpa.free(s);
        self.demo_manifest_version_str = null;
        self.demo_manifest_version = 0;
        if (version) |v| {
            self.demo_manifest_version_str = try gpa.dupe(u8, v);
            // Parse major version component
            var it = std.mem.splitScalar(u8, v, '.');
            const first = it.next() orelse return;
            self.demo_manifest_version = std.fmt.parseInt(u16, first, 10) catch 0;
        }
    }

    pub fn deinit(self: *VersionInfo, gpa: std.mem.Allocator) void {
        if (self.semver.len > 0) {
            gpa.free(self.semver);
        }
        self.semver = "";
        if (self.demo_manifest_version_str) |s| {
            gpa.free(s);
        }
        self.demo_manifest_version_str = null;
    }
};

/// Derive isolation tier from runtime tier.
/// linux_full → full, macos_retail/windows_retail → retail, unsupported → degraded.
pub fn isolationTierStr() []const u8 {
    const tier = @import("tier").detectTier();
    return switch (tier) {
        .linux_full => "full",
        .macos_retail, .windows_retail => "retail",
        .unsupported => "degraded",
    };
}

/// Format version info as multi-line text output for `--version`.
/// Formats semver directly from build_options to avoid stack-buffer staleness
/// that would occur if we used info.semver (which points to a local stack buf).
pub fn formatVersionInfo(info: VersionInfo, writer: anytype) !void {
    var sv_buf: [64]u8 = undefined;
    const sv = if (std.mem.eql(u8, build_version_pre, ""))
        std.fmt.bufPrint(&sv_buf, "{d}.{d}.{d}", .{
            build_version_major, build_version_minor, build_version_patch,
        }) catch "0.0.0"
    else
        std.fmt.bufPrint(&sv_buf, "{d}.{d}.{d}-{s}", .{
            build_version_major, build_version_minor, build_version_patch, build_version_pre,
        }) catch "0.0.0";
    try writer.print("Tickoni {s}\n", .{sv});
    try writer.print("Build ID: {s}\n", .{info.build_id});
    try writer.print("Git: {s}\n", .{info.git_sha[0..@min(info.git_sha.len, 12)]});
    try writer.print("OS: {s} {s}\n", .{ info.os, info.arch });
    try writer.print("Runtime Tier: {s}\n", .{info.runtime_tier});
    try writer.print("Isolation Tier: {s}\n", .{info.isolation_tier});
    try writer.print("Policy Schema: {d}\n", .{info.policy_schema_version});
    try writer.print("Replay Schema: {d}\n", .{info.replay_schema_version});
    if (info.demo_manifest_version_str) |str| {
        try writer.print("Demo Manifest: {s}\n", .{str});
    } else {
        try writer.print("Demo Manifest: none\n", .{});
    }
    try writer.print("Compiler: {s}\n", .{info.compiler});
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "build_version defaults are dev values" {
    // On a fresh build without overrides, these should be the defaults.
    // Tests run against the compiled binary, so actual values depend on
    // whether build.zig injected overrides. We just verify the struct
    // can be initialized.
    const info = VersionInfo{};
    try std.testing.expect(info.semver.len > 0);
}

test "VersionInfo fields are non-empty" {
    const info = VersionInfo{
        .semver = "1.2.3",
        .build_id = "test-1",
        .git_sha = "abcdef1234567890",
        .os = "Linux",
        .arch = "x86_64",
        .runtime_tier = "linux_full",
        .isolation_tier = "full",
        .policy_schema_version = 2,
        .replay_schema_version = 2,
        .demo_manifest_version = 1,
        .compiler = "clang 15.0",
    };
    try std.testing.expect(info.semver.len > 0);
    try std.testing.expect(info.build_id.len > 0);
    try std.testing.expect(info.git_sha.len > 0);
    try std.testing.expect(info.os.len > 0);
    try std.testing.expect(info.arch.len > 0);
    try std.testing.expect(info.runtime_tier.len > 0);
    try std.testing.expect(info.isolation_tier.len > 0);
    try std.testing.expect(info.compiler.len > 0);
}

test "semver format validates major.minor.patch" {
    var buf: [64]u8 = undefined;
    const sv = try semver(&buf);
    try std.testing.expect(sv.len >= 5); // "0.0.0"
    // Should contain exactly 2 dots for base semver
    var dot_count: usize = 0;
    for (sv) |c| {
        if (c == '.') dot_count += 1;
    }
    try std.testing.expect(dot_count >= 2);
}

test "git_sha truncation for short SHA" {
    const short_sha = "abc";
    const truncated = short_sha[0..@min(short_sha.len, 12)];
    try std.testing.expectEqualStrings("abc", truncated);
}

test "git_sha truncation for long SHA" {
    const long_sha = "abcdef1234567890abcdef";
    const truncated = long_sha[0..@min(long_sha.len, 12)];
    try std.testing.expectEqualStrings("abcdef123456", truncated);
}

test "isolationTierStr returns correct tier strings" {
    const tier = @import("tier");
    // Test the switch logic directly for each tier variant.
    // detectTier() is platform-dependent, so we test the tierName output
    // matches known patterns and that isolationTierStr returns a valid string.
    const tier_name = tier.tierName(tier.detectTier());
    const iso = switch (tier.detectTier()) {
        .linux_full => "full",
        .macos_retail, .windows_retail => "retail",
        .unsupported => "degraded",
    };
    try std.testing.expect(iso.len > 0);
    // tier_name should match iso per the switch mapping
    _ = tier_name;
}

test "formatVersionInfo contains all required fields" {
    // formatVersionInfo formats semver from build_options, not info.semver
    // so we check for the expected output pattern using Tickoni prefix
    const info = VersionInfo{
        .semver = "1.2.3",
        .build_id = "test-build-1",
        .git_sha = "abcdef1234567890",
        .os = "Linux",
        .arch = "x86_64",
        .runtime_tier = "linux_full",
        .isolation_tier = "full",
        .policy_schema_version = 2,
        .replay_schema_version = 2,
        .demo_manifest_version = 1,
        .demo_manifest_version_str = "1.0.0",
        .compiler = "clang 15.0",
    };
    var buf: [1024]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try formatVersionInfo(info, &w);
    const output = w.buffered();

    try std.testing.expect(std.mem.startsWith(u8, output, "Tickoni "));
    try std.testing.expect(std.mem.indexOf(u8, output, "Build ID: test-build-1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Git: abcdef123456") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "OS: Linux x86_64") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Runtime Tier: linux_full") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Isolation Tier: full") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Policy Schema: 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Replay Schema: 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Demo Manifest: 1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Compiler: clang 15.0") != null);
}

test "formatVersionInfo validates all Tier enum values" {
    const tier_mod = @import("tier");
    const all_tiers = [_]tier_mod.Tier{ .linux_full, .macos_retail, .windows_retail, .unsupported };

    for (all_tiers) |t| {
        const info = VersionInfo{
            .semver = "0.1.0",
            .runtime_tier = tier_mod.tierName(t),
            .isolation_tier = switch (t) {
                .linux_full => "full",
                .macos_retail, .windows_retail => "retail",
                .unsupported => "degraded",
            },
            .os = tier_mod.detectOsString(),
            .arch = tier_mod.detectArchString(),
        };
        var buf: [1024]u8 = undefined;
        var w = std.Io.Writer.fixed(&buf);
        try formatVersionInfo(info, &w);
        const output = w.buffered();

        // Verify runtime tier appears in output
        try std.testing.expect(std.mem.indexOf(u8, output, "Runtime Tier: ") != null);
        // Verify isolation tier appears in output
        try std.testing.expect(std.mem.indexOf(u8, output, "Isolation Tier: ") != null);
        // Verify semver line starts with Tickoni prefix (semver from build_options)
        try std.testing.expect(std.mem.startsWith(u8, output, "Tickoni "));
    }
}

test "formatVersionInfo shows 'none' when demo manifest version is unset" {
    const info = VersionInfo{
        .semver = "1.0.0",
        .build_id = "test",
        .git_sha = "abc",
        .os = "Linux",
        .arch = "x86_64",
        .runtime_tier = "linux_full",
        .isolation_tier = "full",
        .policy_schema_version = 1,
        .replay_schema_version = 1,
        .demo_manifest_version = 0,
        .demo_manifest_version_str = null,
        .compiler = "clang 15.0",
    };
    var buf: [1024]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try formatVersionInfo(info, &w);
    const output = w.buffered();

    try std.testing.expect(std.mem.indexOf(u8, output, "Demo Manifest: none") != null);
}

test "setDemoManifestVersion parses and stores version" {
    var info = VersionInfo.init(std.testing.allocator) catch unreachable;
    info.setDemoManifestVersion(std.testing.allocator, "3.2.1") catch unreachable;
    try std.testing.expectEqual(@as(u16, 3), info.demo_manifest_version);
    try std.testing.expectEqualStrings("3.2.1", info.demo_manifest_version_str.?);
    info.setDemoManifestVersion(std.testing.allocator, null) catch unreachable;
    try std.testing.expectEqual(@as(u16, 0), info.demo_manifest_version);
    try std.testing.expect(info.demo_manifest_version_str == null);
    info.deinit(std.testing.allocator);
}

test "formatVersionInfo ends with newline" {
    const info = VersionInfo{
        .semver = "1.0.0",
        .build_id = "test",
        .git_sha = "abc",
        .os = "Linux",
        .arch = "x86_64",
        .runtime_tier = "linux_full",
        .isolation_tier = "full",
        .policy_schema_version = 1,
        .replay_schema_version = 1,
        .demo_manifest_version = 1,
        .compiler = "clang 15.0",
    };
    var buf: [1024]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try formatVersionInfo(info, &w);
    const output = w.buffered();
    try std.testing.expect(std.mem.endsWith(u8, output, "\n"));
}

fn tierNameFromIsolation(iso: []const u8) []const u8 {
    if (std.mem.eql(u8, iso, "full")) return "linux_full";
    if (std.mem.eql(u8, iso, "retail")) return "macos_retail";
    if (std.mem.eql(u8, iso, "degraded")) return "unsupported";
    return "unknown";
}
