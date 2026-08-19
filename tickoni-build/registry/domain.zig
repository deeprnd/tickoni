/// Domain struct: a named, compilable unit with optional archive and module.
///
/// Each domain has:
///   - name: unique identifier (e.g. "ballet", "c_abi", "audit")
///   - archive: optional static archive (for c_builder domains)
///   - module: the Zig module (for all domains)
///   - strategy: how it was built (c_builder, zig_module, composite)

const std = @import("std");
const base = @import("../strategy/base.zig");

/// A single domain result with its name, optional archive, module, and strategy.
pub const Domain = struct {
    name: []const u8,
    archive: ?*std.Build.Step.Compile,
    module: *std.Build.Module,
    strategy: base.Strategy,
};
