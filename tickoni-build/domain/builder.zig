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

/// Result of building all domains.
pub const AllDomains = struct {
    /// Firedancer shim domains (compiled C + linked Firedancer .a)
    ballet: domain.BalletDomains,
    flamenco: domain.FlamencoDomains,
    disco: domain.DiscoDomains,
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

/// Build all Firedancer shim domains in the correct order.
/// Each domain is compiled from Tickoni shim C and linked against
/// pre-built Firedancer .a archives.
pub fn buildFiredancerShimDomains(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,
) struct {
    ballet: domain.BalletDomains,
    flamenco: domain.FlamencoDomains,
    disco: domain.DiscoDomains,
} {
    const result = .{
        .ballet = ballet.buildDomains(b, target, optimize, fd_lib_dir),
        .flamenco = flamenco.buildDomains(b, target, optimize, fd_lib_dir),
        .disco = disco.buildDomains(b, target, optimize, fd_lib_dir),
    };
    return result;
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
    firedancer: struct {
        ballet: domain.BalletDomains,
        flamenco: domain.FlamencoDomains,
        disco: domain.DiscoDomains,
    },
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
    return tiles.buildTileDomains(b, target, optimize, common_domains, firedancer);
}

/// Build all domains and return the complete result.
/// This is the main entry point called from build.zig.
pub fn buildAllDomains(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,
) AllDomains {
    const firedancer = buildFiredancerShimDomains(b, target, optimize, fd_lib_dir);
    const common_domains = buildCommonDomains(b, target, optimize);
    const tile_domains = buildTileDomains(b, target, optimize, common_domains, firedancer);
    return .{
        .ballet = firedancer.ballet,
        .flamenco = firedancer.flamenco,
        .disco = firedancer.disco,
        .common = common_domains,
        .tiles = tile_domains,
    };
}
