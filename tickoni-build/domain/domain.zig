/// Domain system types for the Tickoni build system.
///
/// A domain is a named, compilable unit that may depend on other domains.
/// Domains are classified into three types:
/// 1. Firedancer shim domains (Tickoni shim C + pre-built Firedancer .a)
/// 2. Common domains (pure Zig, no C shims, no archives)
/// 3. Tile domains (composite: common + Firedancer shim domains)

const std = @import("std");
const shims = @import("../lib/shims.zig");
const enums = std.enums;

/// Firedancer shim domain — one compiled static archive + one Zig module.
/// The domain name is a runtime value (Domain enum), not a struct field.
pub const FiredancerShimDomain = struct {
    /// Static archive (e.g., libtickoni_ballet.a)
    archive: *std.Build.Step.Compile,
    /// Zig module that can be imported by other domains
    module: *std.Build.Module,
};

/// Firedancer shim domain name — extends as new shim domains are added.
pub const FiredancerShimDomainId = enum {
    /// ballet: compiles ballet.c, links libfd_ballet.a + libfd_util.a
    ballet,
    /// flamenco: compiles tango.c, util.c, wksp.c, sandbox.c, os.c
    /// links libfd_tango.a + libfd_util.a
    flamenco,
    /// disco: compiles topo_run.c, topob.c, tile_run.c + platform variants
    /// links libfd_disco.a
    disco,
    // Add new shim domains here as enum values.

    /// All shim domains for iteration.
    pub const all = [_]FiredancerShimDomainId{ .ballet, .flamenco, .disco };

    /// Library name for linking (e.g., "ballet", "flamenco", "disco").
    pub fn libName(self: FiredancerShimDomainId) []const u8 {
        return switch (self) {
            .ballet => "ballet",
            .flamenco => "flamenco",
            .disco => "disco",
        };
    }

    /// Static archive name (e.g., "libtickoni_ballet.a").
    pub fn archiveName(self: FiredancerShimDomainId) []const u8 {
        return switch (self) {
            .ballet => "libtickoni_ballet",
            .flamenco => "libtickoni_flamenco",
            .disco => "libtickoni_disco",
        };
    }

    /// Display name for error messages.
    pub fn name(self: FiredancerShimDomainId) []const u8 {
        return switch (self) {
            .ballet => "ballet",
            .flamenco => "flamenco",
            .disco => "disco",
        };
    }
};

/// Domain map type — maps FiredancerShimDomainId to FiredancerShimDomain.
pub const DomainMap = enums.EnumMap(FiredancerShimDomainId, FiredancerShimDomain);

/// Common domains result — pure Zig modules, no archives.
pub const CommonDomains = struct {
    c_abi: *std.Build.Module,
    util: *std.Build.Module,
};
