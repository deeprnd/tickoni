/// Domain builder for the Tickoni build system.
///
/// Builds all domains in dependency order:
/// 1. Firedancer shim domains (compile Tickoni shim C, link Firedancer .a)
/// 2. Common domains (pure Zig modules)
/// 3. Tile domains (compose common + Firedancer shim domains)

const std = @import("std");
const builtin = @import("builtin");
const shims = @import("../lib/shims.zig");
const domain = @import("domain.zig");
const ballet = @import("ballet.zig");
const flamenco = @import("flamenco.zig");
const disco = @import("disco.zig");
const common = @import("common.zig");
const tiles = @import("tiles.zig");

/// Map from domain ID to built domain.
pub const DomainMap = domain.DomainMap;

/// Result of building all domains.
pub const AllDomains = struct {
    /// Firedancer shim domains (compiled C + linked Firedancer .a)
    /// Stored in a map keyed by FiredancerShimDomainId enum.
    firedancer: DomainMap,
    /// Common domains (pure Zig)
    common: domain.CommonDomains,
    /// Tile domains (composed from common + Firedancer shim)
    tiles: struct {
        audit: *std.Build.Module,
        policy: *std.Build.Module,
        model: *std.Build.Module,
        adapter: *std.Build.Module,
        topology: *std.Build.Module,
        case: *std.Build.Module,
        disp: *std.Build.Module,
        agent: *std.Build.Module,
        tool: *std.Build.Module,
        replay: *std.Build.Module,
        payment: *std.Build.Module,
    },
};

/// Build all Firedancer shim domains.
/// Returns a DomainMap keyed by FiredancerShimDomainId enum.
pub fn buildFiredancerShimDomains(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    lib_dir: []const u8,
) DomainMap {
    return DomainMap.init(.{
        .ballet = ballet.buildDomain(b, target, optimize, lib_dir),
        .flamenco = flamenco.buildDomain(b, target, optimize, lib_dir),
        .disco = disco.buildDomain(b, target, optimize, lib_dir),
    });
}

/// Build all common (pure Zig) domains.
pub fn buildCommonDomains(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) domain.CommonDomains {
    return common.buildDomains(b, target, optimize);
}

/// Build all tile domains.
/// Tiles compose common + Firedancer shim domains.
pub fn buildTileDomains(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    common_domains: domain.CommonDomains,
    firedancer_domains: DomainMap,
) struct {
    audit: *std.Build.Module,
    policy: *std.Build.Module,
    model: *std.Build.Module,
    adapter: *std.Build.Module,
    topology: *std.Build.Module,
    case: *std.Build.Module,
    disp: *std.Build.Module,
    agent: *std.Build.Module,
    tool: *std.Build.Module,
    replay: *std.Build.Module,
    payment: *std.Build.Module,
} {
    return tiles.buildTileDomains(b, target, optimize, common_domains, firedancer_domains);
}

/// Build all domains and return the complete result.
/// This is the main entry point called from build.zig.
pub fn buildAllDomains(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    lib_dir: []const u8,
) AllDomains {
    const firedancer = buildFiredancerShimDomains(b, target, optimize, lib_dir);
    const common_domains = buildCommonDomains(b, target, optimize);
    const tile_domains = buildTileDomains(b, target, optimize, common_domains, firedancer);
    return .{
        .firedancer = firedancer,
        .common = common_domains,
        .tiles = tile_domains,
    };
}
