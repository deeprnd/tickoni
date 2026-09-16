/// Test-only module definitions — delegated from build.zig.
/// These are b.createModule calls for modules that need separate instances
/// per compilation unit (test binaries, integration tests, etc.).
///
/// They depend on shared modules (passed as `shared`) for their imports.
const std = @import("std");
const modules = @import("modules.zig");

pub const TestModules = struct {
    adapter_messages: *std.Build.Module,
    audit_tile: *std.Build.Module,
    cards: *std.Build.Module,
    drift: *std.Build.Module,
    fixture_audit_gen: *std.Build.Module,
    fixture_portfolio: *std.Build.Module,
    impact: *std.Build.Module,
    mock_adapter: *std.Build.Module,
    mock_model: *std.Build.Module,
    model_messages: *std.Build.Module,
    trade_ticket: *std.Build.Module,
};

pub fn testModules(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    shared: modules.Shared,
) TestModules {
    const fixture_audit_gen_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/fixtures/fixture_audit_gen.zig"),
        .target = target,
        .optimize = optimize,
    });
    const audit_tile_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/audit/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "audit_codec", .module = shared.audit_codec },
            .{ .name = "audit_schema", .module = shared.audit_schema },
            .{ .name = "fixture_audit_gen", .module = fixture_audit_gen_mod },
        },
    });
    const fixture_portfolio_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/fixtures/portfolio/fixture_portfolio.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "basket", .module = shared.basket },
        },
    });
    const trade_ticket_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/trade_ticket.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "fixture_portfolio", .module = fixture_portfolio_mod },
            .{ .name = "thesis", .module = shared.thesis },
        },
    });
    const impact_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/impact.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "portfolio", .module = shared.portfolio },
        },
    });
    const cards_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/cards.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "impact", .module = impact_mod },
        },
    });
    const drift_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/drift.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "cards", .module = cards_mod },
        },
    });
    const model_messages_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/model/messages.zig"),
        .target = target,
        .optimize = optimize,
    });
    const mock_model_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/mocks/mock_model.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "model_messages", .module = model_messages_mod },
        },
    });
    const adapter_messages_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/adapter/messages.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });
    const mock_adapter_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/mocks/mock_adapter.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "fixture_portfolio", .module = fixture_portfolio_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
            .{ .name = "adapter_messages", .module = adapter_messages_mod },
        },
    });

    return TestModules{
        .adapter_messages = adapter_messages_mod,
        .audit_tile = audit_tile_mod,
        .cards = cards_mod,
        .drift = drift_mod,
        .fixture_audit_gen = fixture_audit_gen_mod,
        .fixture_portfolio = fixture_portfolio_mod,
        .impact = impact_mod,
        .mock_adapter = mock_adapter_mod,
        .mock_model = mock_model_mod,
        .model_messages = model_messages_mod,
        .trade_ticket = trade_ticket_mod,
    };
}
