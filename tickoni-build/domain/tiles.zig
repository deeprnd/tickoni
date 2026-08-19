/// Tile domains: composite domains that import common + Firedancer shim domains.
///
/// Each tile declares which domain dependencies it pulls in.
/// The builder creates a Zig module for each tile, wiring imports accordingly.
/// Adding/removing a tile = one entry here.

const std = @import("std");
const domain = @import("domain.zig");

pub const DomainMap = domain.DomainMap;

/// Tile domain definition — source file and domain dependencies.
pub const TileDef = struct {
    name: []const u8,
    /// Zig source file root for this tile (relative to repo root)
    source_file: []const u8,
    /// Common (pure Zig) domain names this tile imports
    common_dep_names: []const []const u8,
    /// Firedancer shim domain names this tile imports
    firedancer_dep_names: []const []const u8,
};

/// All tile definitions, organized by domain name.
/// This is the single source of truth for tile configuration.
pub const tile_definitions = struct {
    pub const all: []const TileDef = &.{
        .{
            .name = "audit",
            .source_file = "src/tickoni/tiles/audit/mod.zig",
            .common_dep_names = &.{ "c_abi", "util", "logger" },
            .firedancer_dep_names = &.{ "ballet" },
        },
        .{
            .name = "policy",
            .source_file = "src/tickoni/tiles/policy/mod.zig",
            .common_dep_names = &.{ "c_abi", "util", "logger" },
            .firedancer_dep_names = &.{ "ballet" },
        },
        .{
            .name = "model",
            .source_file = "src/tickoni/tiles/model/mod.zig",
            .common_dep_names = &.{ "c_abi", "util", "logger" },
            .firedancer_dep_names = &.{ "ballet" },
        },
        .{
            .name = "adapter",
            .source_file = "src/tickoni/tiles/adapter/mod.zig",
            .common_dep_names = &.{ "c_abi", "util", "logger" },
            .firedancer_dep_names = &.{ "ballet", "flamenco" },
        },
        .{
            .name = "topology",
            .source_file = "src/tickoni/tiles/topology/mod.zig",
            .common_dep_names = &.{ "c_abi", "util", "logger" },
            .firedancer_dep_names = &.{ "ballet", "flamenco", "disco" },
        },
        .{
            .name = "case",
            .source_file = "src/tickoni/tiles/case/mod.zig",
            .common_dep_names = &.{ "c_abi", "util", "logger" },
            .firedancer_dep_names = &.{ "ballet" },
        },
        .{
            .name = "disp",
            .source_file = "src/tickoni/tiles/disp/mod.zig",
            .common_dep_names = &.{ "c_abi", "util", "logger" },
            .firedancer_dep_names = &.{ "ballet" },
        },
        .{
            .name = "agent",
            .source_file = "src/tickoni/tiles/agent/mod.zig",
            .common_dep_names = &.{ "c_abi", "util", "logger" },
            .firedancer_dep_names = &.{ "ballet" },
        },
        .{
            .name = "tool",
            .source_file = "src/tickoni/tiles/tool/mod.zig",
            .common_dep_names = &.{ "c_abi", "util", "logger" },
            .firedancer_dep_names = &.{ "ballet" },
        },
        .{
            .name = "replay",
            .source_file = "src/tickoni/tiles/replay/mod.zig",
            .common_dep_names = &.{ "c_abi", "util", "logger" },
            .firedancer_dep_names = &.{ "ballet" },
        },
        .{
            .name = "payment",
            .source_file = "src/tickoni/tiles/payment_pipeline/mod.zig",
            .common_dep_names = &.{ "c_abi", "util", "logger" },
            .firedancer_dep_names = &.{ "ballet", "flamenco" },
        },
    };
};

/// Build all tile domains.
/// Each tile domain imports its common + Firedancer shim dependencies,
/// and provides a Zig module that can be imported by other tiles or the supervisor.
pub fn buildTileDomains(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    common: domain.CommonDomains,
    firedancer: DomainMap,
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
    const all_tiles = tile_definitions.all;

    // First, build all common domain modules (these are the import names)
    const import_names = buildImportNames(common, firedancer);

    var tiles = struct {
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
    }{};

    // Build each tile domain
    for (all_tiles) |tile| {
        var imports: [64]std.Build.Module.Import = undefined;
        var import_count: usize = 0;

        // Add common domain imports
        for (tile.common_dep_names) |dep_name| {
            if (std.mem.eql(u8, dep_name, "c_abi")) {
                imports[import_count] = .{ .name = dep_name, .module = import_names.c_abi };
            } else if (std.mem.eql(u8, dep_name, "util")) {
                imports[import_count] = .{ .name = dep_name, .module = import_names.util };
            } else if (std.mem.eql(u8, dep_name, "logger")) {
                imports[import_count] = .{ .name = dep_name, .module = import_names.logger };
            } else if (std.mem.eql(u8, dep_name, "runtime")) {
                imports[import_count] = .{ .name = dep_name, .module = import_names.runtime };
            }
            import_count += 1;
        }

        // Add Firedancer shim domain imports using the enum map
        for (tile.firedancer_dep_names) |dep_name| {
            // Convert string dep name to enum ID
            const dep_id = firedancerShimDomainIdFromName(dep_name) orelse unreachable;
            imports[import_count] = .{ .name = dep_name, .module = firedancer.get(dep_id).module };
            import_count += 1;
        }

        // Create the tile module
        const tile_mod = b.createModule(.{
            .root_source_file = b.path(tile.source_file),
            .target = target,
            .optimize = optimize,
            .imports = &imports[0..import_count].*,
        });

        // Assign to the correct field (if-else blocks, not statements)
        if (std.mem.eql(u8, tile.name, "audit")) {
            tiles.audit = tile_mod;
        } else if (std.mem.eql(u8, tile.name, "policy")) {
            tiles.policy = tile_mod;
        } else if (std.mem.eql(u8, tile.name, "model")) {
            tiles.model = tile_mod;
        } else if (std.mem.eql(u8, tile.name, "adapter")) {
            tiles.adapter = tile_mod;
        } else if (std.mem.eql(u8, tile.name, "topology")) {
            tiles.topology = tile_mod;
        } else if (std.mem.eql(u8, tile.name, "case")) {
            tiles.case = tile_mod;
        } else if (std.mem.eql(u8, tile.name, "disp")) {
            tiles.disp = tile_mod;
        } else if (std.mem.eql(u8, tile.name, "agent")) {
            tiles.agent = tile_mod;
        } else if (std.mem.eql(u8, tile.name, "tool")) {
            tiles.tool = tile_mod;
        } else if (std.mem.eql(u8, tile.name, "replay")) {
            tiles.replay = tile_mod;
        } else if (std.mem.eql(u8, tile.name, "payment")) {
            tiles.payment = tile_mod;
        }
    }

    return tiles;
}

/// Convert a string domain name to a FiredancerShimDomainId enum.
fn firedancerShimDomainIdFromName(name: []const u8) ?domain.FiredancerShimDomainId {
    if (std.mem.eql(u8, name, "ballet")) return .ballet;
    if (std.mem.eql(u8, name, "flamenco")) return .flamenco;
    if (std.mem.eql(u8, name, "disco")) return .disco;
    return null;
}

/// Build the import name struct by building all common + Firedancer modules.
fn buildImportNames(
    common: domain.CommonDomains,
    firedancer: DomainMap,
) struct {
    c_abi: *std.Build.Module,
    util: *std.Build.Module,
    logger: *std.Build.Module,
    runtime: *std.Build.Module,
    ballet: *std.Build.Module,
    flamenco: *std.Build.Module,
    disco: *std.Build.Module,
} {
    return .{
        .c_abi = common.c_abi,
        .util = common.util,
        .logger = common.util, // logger imports util, same module for now
        .runtime = common.util, // runtime imports util, same module for now
        .ballet = firedancer.get(.ballet).module,
        .flamenco = firedancer.get(.flamenco).module,
        .disco = firedancer.get(.disco).module,
    };
}
