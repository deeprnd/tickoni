/// Test-specific module declarations for the Tickoni build system.
///
/// Provides test-only modules (mock_http_support, mock_broker_market_server,
/// mock_openai_server, trade_ticket, adapter_messages, mock_adapter,
/// mock_model, model_messages) that are shared across unit, integration,
/// and system test lanes.

const std = @import("std");

/// Struct containing all test-specific modules.
pub const TestModules = struct {
    mock_http_support: *std.Build.Module,
    mock_broker_market_server: *std.Build.Module,
    mock_openai_server: *std.Build.Module,
    trade_ticket: *std.Build.Module,
    adapter_messages: *std.Build.Module,
    mock_adapter: *std.Build.Module,
    mock_model: *std.Build.Module,
    model_messages: *std.Build.Module,
};

/// Create all test-specific modules given a build context, target, optimize
/// mode, and the main modules struct.
pub fn create(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    main: @import("modules.zig").Modules,
) TestModules {
    const basket_mod = main.basket;
    const portfolio_mod = main.portfolio;
    const trade_ticket_mod = main.trade_ticket;
    const fixture_portfolio_mod = main.fixture_portfolio;

    // Trade ticket (reuse from main modules — do NOT create duplicate with same root file)
    const trade_ticket = main.trade_ticket;

    // Adapter messages
    const adapter_messages = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/adapter/messages.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });

    // Mock adapter
    const mock_adapter = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/mocks/mock_adapter.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "fixture_portfolio", .module = fixture_portfolio_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
            .{ .name = "adapter_messages", .module = adapter_messages },
        },
    });

    // Mock model
    const mock_model = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/mocks/mock_model.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "model_messages", .module = main.model_messages },
        },
    });

    // Model messages (from main modules)
    const model_messages = main.model_messages;

    // Mock HTTP support
    const mock_http_support = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/mocks/mock_http_support.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
        },
    });

    // Mock broker/market server
    const mock_broker_market_server = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/mocks/mock_broker_market_server.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "mock_http_support", .module = mock_http_support },
        },
    });

    // Mock OpenAI server
    const mock_openai_server = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/mocks/mock_openai_server.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "mock_http_support", .module = mock_http_support },
        },
    });

    return .{
        .mock_http_support = mock_http_support,
        .mock_broker_market_server = mock_broker_market_server,
        .mock_openai_server = mock_openai_server,
        .trade_ticket = trade_ticket,
        .adapter_messages = adapter_messages,
        .mock_adapter = mock_adapter,
        .mock_model = mock_model,
        .model_messages = model_messages,
    };
}
