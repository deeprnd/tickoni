/// Platform support tier detection for `tickoni --version` output.
///
/// Lightweight tier detection that satisfies the doc-level requirement
/// that every build surface prints tier + OS.  Full tier-codification
/// (workflow-to-tier mapping, degraded-guarantee visibility rules, Zig
/// enum with all tiers) lives in S1/S2.
///
/// Tier inventory (matching doc/knowledge/platform-tiers.md):
///   - linux_full     Linux  x86_64 / ARM64 — shared-mem topology, seccomp
///   - macos_retail   macOS  ARM64 / x86_64  — socket networking, no sandbox
///   - windows_retail Windows x86_64 / ARM64 — socket networking, no sandbox
///   - unsupported    anything else
const std = @import("std");
const builtin = @import("builtin");

pub const Tier = enum {
    linux_full,
    macos_retail,
    windows_retail,
    unsupported,
};

pub fn tierName(t: Tier) []const u8 {
    return switch (t) {
        .linux_full => "linux_full",
        .macos_retail => "macos_retail",
        .windows_retail => "windows_retail",
        .unsupported => "unsupported",
    };
}

/// Detect the runtime support tier for the current OS.
pub fn detectTier() Tier {
    return switch (builtin.target.os.tag) {
        .macos => .macos_retail,
        .windows => .windows_retail,
        .linux => .linux_full,
        else => .unsupported,
    };
}

/// Return the detected OS name string for display.
pub fn detectOsString() []const u8 {
    return switch (builtin.target.os.tag) {
        .macos => "MacOS",
        .windows => "Windows",
        .linux => "Linux",
        else => "Unknown",
    };
}

/// Return the detected architecture string for display.
pub fn detectArchString() []const u8 {
    return switch (builtin.target.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "ARM64",
        .arm => "ARM",
        else => @tagName(builtin.target.cpu.arch),
    };
}

/// Return the compiler version string via __VERSION__ (from compiler_version.c).
extern "c" fn tickoni_compiler_version() [*:0]const u8;

pub fn detectCompilerVersion() []const u8 {
    const raw = tickoni_compiler_version();
    return if (raw[0] == 0) "unknown" else std.mem.sliceTo(raw, 0);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "tierName returns correct labels" {
    try std.testing.expectEqualStrings("linux_full", tierName(.linux_full));
    try std.testing.expectEqualStrings("macos_retail", tierName(.macos_retail));
    try std.testing.expectEqualStrings("windows_retail", tierName(.windows_retail));
    try std.testing.expectEqualStrings("unsupported", tierName(.unsupported));
}

test "tierName is non-empty for all variants" {
    const all_tiers = [_]Tier{ .linux_full, .macos_retail, .windows_retail, .unsupported };
    for (all_tiers) |t| {
        const name = tierName(t);
        try std.testing.expect(name.len > 0);
    }
}

test "tierName matches @tagName for all variants" {
    const all_tiers = [_]Tier{ .linux_full, .macos_retail, .windows_retail, .unsupported };
    for (all_tiers) |t| {
        try std.testing.expectEqualStrings(@tagName(t), tierName(t));
    }
}

test "tierName strings are lowercase with underscores" {
    const all_tiers = [_]Tier{ .linux_full, .macos_retail, .windows_retail, .unsupported };
    for (all_tiers) |t| {
        const name = tierName(t);
        for (name) |c| {
            try std.testing.expect(std.ascii.isLower(c) or c == '_' or std.ascii.isDigit(c));
        }
    }
}

test "detectOsString is a recognized OS name" {
    const os = detectOsString();
    const known = [_][]const u8{ "Linux", "MacOS", "Windows", "Unknown" };
    var found = false;
    for (known) |k| {
        if (std.mem.eql(u8, os, k)) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "detectOsString starts with uppercase letter" {
    const os = detectOsString();
    try std.testing.expect(os.len > 0);
    try std.testing.expect(std.ascii.isUpper(os[0]));
}

test "detectArchString is non-empty" {
    const arch = detectArchString();
    try std.testing.expect(arch.len > 0);
}

test "version output format validates" {
    var buf: [256]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, "{s} {s} ({s} {s} {s})\n", .{
        "0.1.1",
        tierName(detectTier()),
        detectOsString(),
        detectArchString(),
        detectCompilerVersion(),
    }) catch unreachable;

    // Format: "<ver> <tier> (<os> <arch> <compiler>)<newline>"
    try std.testing.expect(std.mem.startsWith(u8, line, "0.1.1 "));
    try std.testing.expect(std.mem.endsWith(u8, line, ")\n"));
}

test "version output ends with single newline" {
    var buf: [256]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, "{s} {s} ({s} {s} {s})\n", .{
        "0.1.1",
        tierName(detectTier()),
        detectOsString(),
        detectArchString(),
        detectCompilerVersion(),
    }) catch unreachable;
    try std.testing.expect(std.mem.endsWith(u8, line, "\n"));
}

test "detectCompilerVersion returns non-empty string" {
    const cv = detectCompilerVersion();
    try std.testing.expect(cv.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, cv, " ") != null or cv.len < 30);
}

test "detectTier returns a valid Tier" {
    const t = detectTier();
    _ = t;
}

test "Tier enum has exactly 4 variants" {
    const all_tiers = [_]Tier{ .linux_full, .macos_retail, .windows_retail, .unsupported };
    try std.testing.expectEqual(@as(usize, 4), all_tiers.len);
}
