/// Common domains: pure Zig modules, no C compilation, no archives.
///
/// These are the foundational Zig modules that tile domains compose with.
/// Each domain is a separate Zig module that can be imported by tile domains.

const std = @import("std");
const domain = @import("domain.zig");

/// Build all common (pure Zig) domains.
pub fn buildDomains(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) domain.CommonDomains {
    const result = buildCommonDomains(b, target, optimize);
    return result;
}

/// Build all common domains and return them as CommonDomains struct.
fn buildCommonDomains(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) domain.CommonDomains {
    // c_abi domain: src/tickoni/c_abi/*.zig
    const c_abi = b.createModule(.{
        .root_source_file = b.path("src/tickoni/c_abi/mod.zig"),
        .target = target,
        .optimize = optimize,
    });

    // util domain: src/tickoni/util/*.zig
    const util = b.createModule(.{
        .root_source_file = b.path("src/tickoni/util/mod.zig"),
        .target = target,
        .optimize = optimize,
    });

    return .{
        .c_abi = c_abi,
        .util = util,
    };
}
