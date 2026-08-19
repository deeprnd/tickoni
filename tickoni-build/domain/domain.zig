/// Domain system types for the Tickoni build system.
///
/// A domain is a named, compilable unit that may depend on other domains.
/// Domains are classified into three types:
/// 1. Firedancer shim domains (Tickoni shim C + pre-built Firedancer .a)
/// 2. Common domains (pure Zig, no C shims, no archives)
/// 3. Tile domains (composite: common + Firedancer shim domains)

const std = @import("std");
const shims = @import("../lib/shims.zig");

/// Domain types supported by the build system.
pub const DomainType = enum {
    /// Firedancer shim domain: Tickoni shim C compiled once, links Firedancer .a
    firedancer_shim,
    /// Pure Zig domain: no C compilation, no archives
    common,
    /// Tile domain: composes common + Firedancer shim domains
    tile,
};

/// A domain definition — what C shim files it has, which Firedancer .a to link,
/// and which other domains it depends on.
pub const DomainDef = struct {
    name: []const u8,
    domain_type: DomainType,
    /// Tickoni shim C source files (relative to repo root)
    shim_files: []const []const u8,
    /// Firedancer library names to link (e.g., "ballet", "tango", "util")
    fd_libs: []const []const u8,
    /// Common (pure Zig) domain dependencies
    common_deps: []const []const u8,
    /// Firedancer shim domain dependencies
    firedancer_deps: []const []const u8,
};

/// Firedancer shim domain result — a compiled static archive and a Zig module
/// for importing the C symbols.
pub const FiredancerShimDomains = struct {
    /// Static archive (e.g., libtickoni_ballet.a)
    archive: *std.Build.Step.Compile,
    /// Zig module that can be imported by other domains
    module: *std.Build.Module,
};

/// Ballet domain result.
pub const BalletDomains = FiredancerShimDomains;

/// Flamenco domain result.
pub const FlamencoDomains = FiredancerShimDomains;

/// Disco domain result.
pub const DiscoDomains = FiredancerShimDomains;

/// Common domains result — pure Zig modules, no archives.
pub const CommonDomains = struct {
    c_abi: *std.Build.Module,
    util: *std.Build.Module,
};

/// All domains result — the complete set of compiled domains.
pub const AllDomains = struct {
    ballet: BalletDomains,
    flamenco: FlamencoDomains,
    disco: DiscoDomains,
    common: CommonDomains,
};
