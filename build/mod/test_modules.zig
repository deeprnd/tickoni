/// Test-only module declarations for the Tickoni build system.
///
/// Creates test-specific modules that are not needed at runtime.

const std = @import("std");

/// Test-only modules indexed by name.
pub const TestModules = struct {
    mock_http_support: *std.Build.Module,
    mock_broker_market_server: *std.Build.Module,
    mock_openai_server: *std.Build.Module,
    trade_ticket: *std.Build.Module,
    model_messages: *std.Build.Module,
    mock_model: *std.Build.Module,
    adapter_messages: *std.Build.Module,
    mock_adapter: *std.Build.Module,
};

/// Creates test-only modules and returns them in a TestModules struct.
pub fn testModules(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) TestModules {
    const mock_http_support = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/mocks/mock_http_support.zig"),
        .target = target,
        .optimize = optimize,
    });
    const mock_broker_market_server = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/mocks/mock_broker_market_server.zig"),
        .target = target,
        .optimize = optimize,
    });
    const mock_openai_server = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/mocks/mock_openai_server.zig"),
        .target = target,
        .optimize = optimize,
    });

    return TestModules{
        .mock_http_support = mock_http_support,
        .mock_broker_market_server = mock_broker_market_server,
        .mock_openai_server = mock_openai_server,
        .trade_ticket = undefined, // Will be set from shared modules
        .model_messages = undefined,
        .mock_model = undefined,
        .adapter_messages = undefined,
        .mock_adapter = undefined,
    };
}
