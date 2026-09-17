/// System test lane strategy.
///
/// Extracts inline system test registration from build.zig into a callable
/// function. Preserves identical compile flags, linkage, and module structure.
/// Runs all proofs under src/tickoni/test/system.

const std = @import("std");
const codec = @import("../lib/codec.zig");
const shims = @import("../lib/shims.zig");

/// System modules passed in from build.zig.
pub const SystemModules = struct {
    investment_demo_mod: *std.Build.Module,
    investment_support_int_mod: *std.Build.Module,
    fd_lib_dir: []const u8,
};

/// Register all system test binaries. Called from build.zig.
pub fn strategy(
    b: *std.Build,
    sys_mods: SystemModules,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    system_step: *std.Build.Step,
) void {
    // System test: test_investment_demo_live.zig — live tkmodl smoke proof.
    const system_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/system/test_investment_demo_live.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "investment_demo", .module = sys_mods.investment_demo_mod },
            },
        }),
    });
    codec.linkTickoniCodec(b, system_test, sys_mods.fd_lib_dir);
    const run_system_test = shims.addPlainTestRun(b, system_test);
    system_step.dependOn(&run_system_test.step);

    // V1.3.S4: combined portfolio/cash demo. Fixture-backed and deterministic
    // (no live model, broker, or execution), but lives under
    // src/tickoni/test/system so it runs as part of the system-test lane
    // alongside the live tkmodl proof.
    const portfolio_cash_demo_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/system/test_portfolio_cash_demo.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "investment_demo", .module = sys_mods.investment_demo_mod },
                .{ .name = "investment_support", .module = sys_mods.investment_support_int_mod },
            },
        }),
    });
    codec.linkTickoniCodec(b, portfolio_cash_demo_test, sys_mods.fd_lib_dir);
    const run_portfolio_cash_demo_test = shims.addPlainTestRun(b, portfolio_cash_demo_test);
    system_step.dependOn(&run_portfolio_cash_demo_test.step);
}
