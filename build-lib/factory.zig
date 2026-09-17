/// ModuleFactory for shared integration test modules.
///
/// Both unit.zig and integration.zig create the same set of modules
/// (policy, model, adapter, tool, replay, investment_support, etc.).
/// This factory eliminates that duplication by providing a single
/// source of truth for each module's root_source_file and import graph.
///
/// Module pointers are created once and shared across the graph.

const std = @import("std");
const modules = @import("mod/modules.zig");
const test_mod = @import("mod/test_modules.zig");

/// Result of factory.createIntModules(): the full set of integration
/// modules needed by integration tests.
pub const IntegrationModules = struct {
    tkpoly_int_mod: *std.Build.Module,
    model_int_mod: *std.Build.Module,
    adapter_int_mod: *std.Build.Module,
    tool_int_mod: *std.Build.Module,
    case_int_mod: *std.Build.Module,
    disp_int_mod: *std.Build.Module,
    agent_int_mod: *std.Build.Module,
    replay_int_mod: *std.Build.Module,
    investment_audit_int_mod: *std.Build.Module,
    investment_support_int_mod: *std.Build.Module,
    investment_demo_test_mod: *std.Build.Module,
    investment_demo_mod: *std.Build.Module,
    supervisor_named_mod: *std.Build.Module,
    mock_http_support_mod: *std.Build.Module,
    mock_broker_market_server_mod: *std.Build.Module,
    mock_openai_server_mod: *std.Build.Module,
    exe: ?*std.Build.Step.Compile,
    shared_audit_tile: *std.Build.Module,
    shared_basket: *std.Build.Module,
    shared_portfolio: *std.Build.Module,
    shared_thesis: *std.Build.Module,
    shared_trade_ticket: *std.Build.Module,
    shared_runtime: *std.Build.Module,
    shared_c_abi: *std.Build.Module,
    shared_util: *std.Build.Module,
    shared_topologies: *std.Build.Module,
};

/// ModuleFactory encapsulates the creation of all integration-test
/// shared modules. Both unit.zig and integration.zig create a
/// ModuleFactory and call createIntModules().

pub const ModuleFactory = struct {
    b: *std.Build,
    shared: modules.Shared,
    tm: test_mod.TestModules,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,

    pub fn init(
        b: *std.Build,
        shared: modules.Shared,
        tm: test_mod.TestModules,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
    ) ModuleFactory {
        return ModuleFactory{
            .b = b,
            .shared = shared,
            .tm = tm,
            .target = target,
            .optimize = optimize,
        };
    }

    /// Create all integration modules in one call. Module pointers
    /// are created once and shared across the graph. `exe` is optional
    /// — it is stored in the result struct but only read by the
    /// integration lane; unit lane ignores it.
    pub fn createIntModules(
        self: *const ModuleFactory,
        exe: ?*std.Build.Step.Compile,
    ) IntegrationModules {
        // Create modules in dependency order.
        const tkpoly_int_mod = self.b.createModule(.{
            .root_source_file = self.b.path("src/tickoni/tiles/policy/mod.zig"),
            .target = self.target,
            .optimize = self.optimize,
            .imports = &.{
                .{ .name = "basket", .module = self.shared.basket },
                .{ .name = "portfolio", .module = self.shared.portfolio },
                .{ .name = "thesis", .module = self.shared.thesis },
                .{ .name = "trade_ticket", .module = self.tm.trade_ticket },
                .{ .name = "c_abi", .module = self.shared.c_abi },
                .{ .name = "audit_codec", .module = self.shared.audit_codec },
                .{ .name = "audit_schema", .module = self.shared.audit_schema },
                .{ .name = "runtime", .module = self.shared.runtime },
            },
        });

        const model_int_mod = self.b.createModule(.{
            .root_source_file = self.b.path("src/tickoni/tiles/model/mod.zig"),
            .target = self.target,
            .optimize = self.optimize,
            .imports = &.{
                .{ .name = "model_messages", .module = self.tm.model_messages },
                .{ .name = "mock_model", .module = self.tm.mock_model },
                .{ .name = "c_abi", .module = self.shared.c_abi },
                .{ .name = "fixture_paths", .module = self.shared.fixture_paths },
            },
        });

        const adapter_int_mod = self.b.createModule(.{
            .root_source_file = self.b.path("src/tickoni/tiles/adapter/mod.zig"),
            .target = self.target,
            .optimize = self.optimize,
            .imports = &.{
                .{ .name = "basket", .module = self.shared.basket },
                .{ .name = "portfolio", .module = self.shared.portfolio },
                .{ .name = "fixture_portfolio", .module = self.tm.fixture_portfolio },
                .{ .name = "trade_ticket", .module = self.tm.trade_ticket },
                .{ .name = "adapter_messages", .module = self.tm.adapter_messages },
                .{ .name = "fixture_paths", .module = self.shared.fixture_paths },
            },
        });

        const tool_int_mod = self.b.createModule(.{
            .root_source_file = self.b.path("src/tickoni/tiles/tool/mod.zig"),
            .target = self.target,
            .optimize = self.optimize,
            .imports = &.{
                .{ .name = "adapter", .module = adapter_int_mod },
                .{ .name = "basket", .module = self.shared.basket },
                .{ .name = "portfolio", .module = self.shared.portfolio },
                .{ .name = "fixture_portfolio", .module = self.tm.fixture_portfolio },
                .{ .name = "trade_ticket", .module = self.tm.trade_ticket },
            },
        });

        const case_int_mod = self.b.createModule(.{
            .root_source_file = self.b.path("src/tickoni/tiles/case/mod.zig"),
            .target = self.target,
            .optimize = self.optimize,
        });

        const disp_int_mod = self.b.createModule(.{
            .root_source_file = self.b.path("src/tickoni/tiles/disp/mod.zig"),
            .target = self.target,
            .optimize = self.optimize,
        });

        const agent_int_mod = self.b.createModule(.{
            .root_source_file = self.b.path("src/tickoni/tiles/agent/mod.zig"),
            .target = self.target,
            .optimize = self.optimize,
            .imports = &.{
                .{ .name = "adapter", .module = adapter_int_mod },
                .{ .name = "mock_adapter", .module = self.tm.mock_adapter },
                .{ .name = "basket", .module = self.shared.basket },
                .{ .name = "capability", .module = self.shared.capability },
                .{ .name = "disp", .module = disp_int_mod },
                .{ .name = "model", .module = model_int_mod },
                .{ .name = "mock_model", .module = self.tm.mock_model },
                .{ .name = "portfolio", .module = self.shared.portfolio },
                .{ .name = "tkpoly", .module = tkpoly_int_mod },
                .{ .name = "tool", .module = tool_int_mod },
                .{ .name = "trade_ticket", .module = self.tm.trade_ticket },
            },
        });

        const replay_int_mod = self.b.createModule(.{
            .root_source_file = self.b.path("src/tickoni/tiles/replay/mod.zig"),
            .target = self.target,
            .optimize = self.optimize,
            .imports = &.{
                .{ .name = "adapter", .module = adapter_int_mod },
                .{ .name = "basket", .module = self.shared.basket },
                .{ .name = "c_abi", .module = self.shared.c_abi },
                .{ .name = "drift", .module = self.tm.drift },
                .{ .name = "model", .module = model_int_mod },
                .{ .name = "portfolio", .module = self.shared.portfolio },
                .{ .name = "tkpoly", .module = tkpoly_int_mod },
                .{ .name = "trade_ticket", .module = self.tm.trade_ticket },
                .{ .name = "fixture_paths", .module = self.shared.fixture_paths },
            },
        });

        const investment_audit_int_mod = self.b.createModule(.{
            .root_source_file = self.b.path("src/tickoni/test/demo/investment/audit_trace.zig"),
            .target = self.target,
            .optimize = self.optimize,
            .imports = &.{
                .{ .name = "audit_tile", .module = self.shared.audit_tile },
                .{ .name = "basket", .module = self.shared.basket },
                .{ .name = "drift", .module = self.tm.drift },
                .{ .name = "model", .module = model_int_mod },
                .{ .name = "portfolio", .module = self.shared.portfolio },
                .{ .name = "replay", .module = replay_int_mod },
                .{ .name = "thesis", .module = self.shared.thesis },
                .{ .name = "trade_ticket", .module = self.tm.trade_ticket },
            },
        });

        const investment_support_int_mod = self.b.createModule(.{
            .root_source_file = self.b.path("src/tickoni/test/demo/investment/support.zig"),
            .target = self.target,
            .optimize = self.optimize,
            .imports = &.{
                .{ .name = "basket", .module = self.shared.basket },
                .{ .name = "thesis", .module = self.shared.thesis },
                .{ .name = "trade_ticket", .module = self.tm.trade_ticket },
            },
        });

        const investment_demo_test_mod = self.b.createModule(.{
            .root_source_file = self.b.path("src/tickoni/test/demo/investment/mod.zig"),
            .target = self.target,
            .optimize = self.optimize,
            .imports = &.{
                .{ .name = "adapter", .module = adapter_int_mod },
                .{ .name = "basket", .module = self.shared.basket },
                .{ .name = "cards", .module = self.tm.cards },
                .{ .name = "drift", .module = self.tm.drift },
                .{ .name = "impact", .module = self.tm.impact },
                .{ .name = "investment_support", .module = investment_support_int_mod },
                .{ .name = "model", .module = model_int_mod },
                .{ .name = "portfolio", .module = self.shared.portfolio },
                .{ .name = "replay", .module = replay_int_mod },
                .{ .name = "thesis", .module = self.shared.thesis },
                .{ .name = "tkpoly", .module = tkpoly_int_mod },
                .{ .name = "tool", .module = tool_int_mod },
                .{ .name = "trade_ticket", .module = self.tm.trade_ticket },
            },
        });

        const investment_demo_mod = self.b.createModule(.{
            .root_source_file = self.b.path("src/tickoni/test/demo/investment/mod.zig"),
            .target = self.target,
            .optimize = self.optimize,
            .imports = &.{
                .{ .name = "adapter", .module = adapter_int_mod },
                .{ .name = "basket", .module = self.shared.basket },
                .{ .name = "cards", .module = self.tm.cards },
                .{ .name = "drift", .module = self.tm.drift },
                .{ .name = "impact", .module = self.tm.impact },
                .{ .name = "investment_support", .module = investment_support_int_mod },
                .{ .name = "model", .module = model_int_mod },
                .{ .name = "portfolio", .module = self.shared.portfolio },
                .{ .name = "replay", .module = replay_int_mod },
                .{ .name = "thesis", .module = self.shared.thesis },
                .{ .name = "tkpoly", .module = tkpoly_int_mod },
                .{ .name = "tool", .module = tool_int_mod },
                .{ .name = "trade_ticket", .module = self.tm.trade_ticket },
            },
        });

        const mock_http_support_mod = self.b.createModule(.{
            .root_source_file = self.b.path("src/tickoni/test/mocks/mock_http_support.zig"),
            .target = self.target,
            .optimize = self.optimize,
        });

        const mock_broker_market_server_mod = self.b.createModule(.{
            .root_source_file = self.b.path("src/tickoni/test/mocks/mock_broker_market_server.zig"),
            .target = self.target,
            .optimize = self.optimize,
            .imports = &.{
                .{ .name = "mock_http_support", .module = mock_http_support_mod },
            },
        });

        const mock_openai_server_mod = self.b.createModule(.{
            .root_source_file = self.b.path("src/tickoni/test/mocks/mock_openai_server.zig"),
            .target = self.target,
            .optimize = self.optimize,
            .imports = &.{
                .{ .name = "mock_http_support", .module = mock_http_support_mod },
            },
        });

        const supervisor_named_mod = self.b.addModule("supervisor", .{
            .root_source_file = self.b.path("src/app/tickoni/supervisor.zig"),
            .target = self.target,
            .optimize = self.optimize,
            .imports = &.{
                .{ .name = "runtime", .module = self.shared.runtime },
                .{ .name = "tiles", .module = self.shared.tiles },
                .{ .name = "c_abi", .module = self.shared.c_abi },
                .{ .name = "util", .module = self.shared.util },
                .{ .name = "topologies", .module = self.shared.topologies },
                .{ .name = "logger", .module = self.shared.logger },
            },
        });

        return IntegrationModules{
            .tkpoly_int_mod = tkpoly_int_mod,
            .model_int_mod = model_int_mod,
            .adapter_int_mod = adapter_int_mod,
            .tool_int_mod = tool_int_mod,
            .case_int_mod = case_int_mod,
            .disp_int_mod = disp_int_mod,
            .agent_int_mod = agent_int_mod,
            .replay_int_mod = replay_int_mod,
            .investment_audit_int_mod = investment_audit_int_mod,
            .investment_support_int_mod = investment_support_int_mod,
            .investment_demo_test_mod = investment_demo_test_mod,
            .investment_demo_mod = investment_demo_mod,
            .supervisor_named_mod = supervisor_named_mod,
            .mock_http_support_mod = mock_http_support_mod,
            .mock_broker_market_server_mod = mock_broker_market_server_mod,
            .mock_openai_server_mod = mock_openai_server_mod,
            .exe = exe,
            .shared_audit_tile = self.shared.audit_tile,
            .shared_basket = self.shared.basket,
            .shared_portfolio = self.shared.portfolio,
            .shared_thesis = self.shared.thesis,
            .shared_trade_ticket = self.tm.trade_ticket,
            .shared_runtime = self.shared.runtime,
            .shared_c_abi = self.shared.c_abi,
            .shared_util = self.shared.util,
            .shared_topologies = self.shared.topologies,
        };
    }
};
