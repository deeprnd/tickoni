/// Domain Strategy trait — abstract interface for building domains.
///
/// Three implementations:
///   - c_builder.zig:     Compile C source files into a static archive, link object deps
///   - zig_module.zig:    Create a Zig module from a root source file
///   - composite.zig:     Create a Zig module from a root source file, import dependencies
///
/// Strategy dispatch is pure: switch (config.strategy) { .c_builder => ..., ... }.
/// No hardcoded paths — everything comes from the config.

const std = @import("std");

/// Build result for any strategy: an archive (optional) and a module.
pub const DomainResult = struct {
    archive: ?*std.Build.Step.Compile,
    module: *std.Build.Module,
};

/// Strategy type enum.
pub const Strategy = enum {
    c_builder,
    zig_module,
    composite,
};
