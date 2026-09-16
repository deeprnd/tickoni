/// Shared module declarations — extracted from build.zig.
/// Single-instance modules used by both the exe and test binaries.
const std = @import("std");

pub const Shared = struct {
    c_abi: *std.Build.Module,
    util: *std.Build.Module,
    logger: *std.Build.Module,
    runtime: *std.Build.Module,
    topologies: *std.Build.Module,
    audit_schema: *std.Build.Module,
    audit_codec: *std.Build.Module,
    audit_tile: *std.Build.Module,
    tier: *std.Build.Module,
    version: *std.Build.Module,
    version_opts: *std.Build.Step.Options,
    fixture_paths: *std.Build.Module,
    doctor_checks: *std.Build.Module,
    doctor_output: *std.Build.Module,
    demo_manifest: *std.Build.Module,
    demo_semver: *std.Build.Module,
    demo_diagnostic: *std.Build.Module,
    demo_preflight: *std.Build.Module,
    demo_cli: *std.Build.Module,
    demo_conformance: *std.Build.Module,
    demo_comparator: *std.Build.Module,
    demo_runner: *std.Build.Module,
    demo_substitution: *std.Build.Module,
    classification: *std.Build.Module,
    capability: *std.Build.Module,
    thesis: *std.Build.Module,
    catalog_schema: *std.Build.Module,
    catalog: *std.Build.Module,
    basket: *std.Build.Module,
    portfolio: *std.Build.Module,
    tiles: *std.Build.Module,
};

pub fn modules(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) Shared {
    const c_abi_mod = b.addModule("c_abi", .{
        .root_source_file = b.path("src/tickoni/c_abi/c_abi.zig"),
        .target = target,
        .optimize = optimize,
    });
    const util_mod = b.addModule("util", .{
        .root_source_file = b.path("src/tickoni/util/util.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c_abi", .module = c_abi_mod },
        },
    });
    const logger_mod = b.addModule("logger", .{
        .root_source_file = b.path("src/tickoni/logger.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "util", .module = util_mod },
        },
    });
    const runtime_mod = b.addModule("runtime", .{
        .root_source_file = b.path("src/tickoni/runtime/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c_abi", .module = c_abi_mod },
            .{ .name = "util", .module = util_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });
    const topologies_named_mod = b.addModule("topologies", .{
        .root_source_file = b.path("src/app/tickoni/topologies.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "runtime", .module = runtime_mod },
        },
    });
    const audit_schema_mod = b.addModule("audit_schema", .{
        .root_source_file = b.path("src/tickoni/schema/audit/audit.zig"),
        .target = target,
        .optimize = optimize,
    });
    const audit_codec_mod = b.addModule("audit_codec", .{
        .root_source_file = b.path("src/tickoni/codec/audit.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c_abi", .module = c_abi_mod },
            .{ .name = "audit_schema", .module = audit_schema_mod },
        },
    });
    const audit_tile_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/audit/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "audit_codec", .module = audit_codec_mod },
            .{ .name = "audit_schema", .module = audit_schema_mod },
        },
    });
    const tier_mod = b.addModule("tier", .{
        .root_source_file = b.path("src/tickoni/util/tier.zig"),
        .target = target,
        .optimize = optimize,
    });
    const build_version_option = b.option([]const u8, "version", "Build version string") orelse "0.1.0";
    var bv_major: u16 = 0;
    var bv_minor: u16 = 0;
    var bv_patch: u16 = 0;
    var bv_pre: []const u8 = "dev";
    {
        const parts = std.mem.splitScalar(u8, build_version_option, '.');
        var parts_it = parts;
        if (parts_it.next()) |s| bv_major = std.fmt.parseInt(u16, s, 10) catch 0;
        if (parts_it.next()) |s| bv_minor = std.fmt.parseInt(u16, s, 10) catch 0;
        if (parts_it.next()) |s| {
            if (std.mem.indexOf(u8, s, "-")) |dash| {
                bv_patch = std.fmt.parseInt(u16, s[0..dash], 10) catch 0;
                bv_pre = s[dash + 1 ..];
            } else {
                bv_patch = std.fmt.parseInt(u16, s, 10) catch 0;
            }
        }
    }

    const version_opts = b.addOptions();
    version_opts.addOption([]const u8, "BUILD_VERSION", build_version_option);
    version_opts.addOption(u16, "BUILD_VERSION_MAJOR", bv_major);
    version_opts.addOption(u16, "BUILD_VERSION_MINOR", bv_minor);
    version_opts.addOption(u16, "BUILD_VERSION_PATCH", bv_patch);
    version_opts.addOption([]const u8, "BUILD_VERSION_PRE", bv_pre);
    version_opts.addOption([]const u8, "BUILD_GIT_SHA", "unknown");
    version_opts.addOption([]const u8, "BUILD_ID", "dev-unknown");

    const version_mod = b.addModule("version", .{
        .root_source_file = b.path("src/tickoni/version.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "tier", .module = tier_mod },
            .{ .name = "audit_schema", .module = audit_schema_mod },
            .{ .name = "build_options", .module = version_opts.createModule() },
        },
    });

    const fixture_paths = b.addOptions();
    fixture_paths.addOption([]const u8, "FIXTURE_INVESTMENT_SCENARIOS", "src/tickoni/test/fixtures/investment/scenarios");
    fixture_paths.addOption([]const u8, "FIXTURE_PORTFOLIO", "src/tickoni/test/fixtures/portfolio");
    fixture_paths.addOption([]const u8, "FIXTURE_CLASSIFICATION_PROTO", "src/tickoni/schema/proto/classification/classification.proto");
    fixture_paths.addOption([]const u8, "FIXTURE_THESIS_PROTO", "src/tickoni/schema/proto/consumer_money/thesis.proto");
    fixture_paths.addOption([]const u8, "FIXTURE_BASKET_PROTO", "src/tickoni/schema/proto/consumer_money/basket.proto");
    const fixture_paths_mod = b.addModule("fixture_paths", .{
        .root_source_file = b.path("src/tickoni/test/fixtures/fixture_paths.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "build_options", .module = fixture_paths.createModule() },
        },
    });
    const doctor_checks_mod = b.addModule("doctor_checks", .{
        .root_source_file = b.path("src/tickoni/doctor/checks.zig"),
        .target = target,
        .optimize = optimize,
    });
    const doctor_output_mod = b.addModule("doctor_output", .{
        .root_source_file = b.path("src/tickoni/doctor/output.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "doctor_checks", .module = doctor_checks_mod },
            .{ .name = "tier", .module = tier_mod },
        },
    });
    const demo_manifest_mod = b.addModule("demo_manifest", .{
        .root_source_file = b.path("src/tickoni/demo/manifest.zig"),
        .target = target,
        .optimize = optimize,
    });
    const demo_semver_mod = b.addModule("demo_semver", .{
        .root_source_file = b.path("src/tickoni/demo/semver.zig"),
        .target = target,
        .optimize = optimize,
    });
    const demo_diagnostic_mod = b.addModule("demo_diagnostic", .{
        .root_source_file = b.path("src/tickoni/demo/diagnostic.zig"),
        .target = target,
        .optimize = optimize,
    });
    const demo_preflight_mod = b.addModule("demo_preflight", .{
        .root_source_file = b.path("src/tickoni/demo/preflight.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "demo_manifest", .module = demo_manifest_mod },
            .{ .name = "demo_semver", .module = demo_semver_mod },
            .{ .name = "diagnostic", .module = demo_diagnostic_mod },
        },
    });
    const demo_cli_mod = b.addModule("demo_cli", .{
        .root_source_file = b.path("src/tickoni/demo/cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    const demo_conformance_mod = b.addModule("demo_conformance", .{
        .root_source_file = b.path("src/tickoni/demo/conformance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "diagnostic", .module = demo_diagnostic_mod },
        },
    });
    const demo_comparator_mod = b.addModule("demo_comparator", .{
        .root_source_file = b.path("src/tickoni/demo/comparator.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "conformance", .module = demo_conformance_mod },
        },
    });
    const demo_runner_mod = b.addModule("demo_runner", .{
        .root_source_file = b.path("src/tickoni/demo/runner.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "conformance", .module = demo_conformance_mod },
            .{ .name = "diagnostic", .module = demo_diagnostic_mod },
        },
    });
    const demo_substitution_mod = b.addModule("demo_substitution", .{
        .root_source_file = b.path("src/tickoni/demo/substitution.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "diagnostic", .module = demo_diagnostic_mod },
            .{ .name = "runner", .module = demo_runner_mod },
        },
    });

    const classification_mod = b.addModule("classification", .{
        .root_source_file = b.path("src/tickoni/schema/classification/classification.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "fixture_paths", .module = fixture_paths_mod },
        },
    });
    const capability_mod = b.addModule("capability", .{
        .root_source_file = b.path("src/tickoni/schema/capability/capability.zig"),
        .target = target,
        .optimize = optimize,
    });
    const thesis_mod = b.addModule("thesis", .{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/thesis.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "classification", .module = classification_mod },
            .{ .name = "c_abi", .module = c_abi_mod },
            .{ .name = "fixture_paths", .module = fixture_paths_mod },
        },
    });
    const catalog_schema_mod = b.addModule("catalog_schema", .{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/catalog_schema.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "thesis", .module = thesis_mod },
        },
    });
    const catalog_mod = b.addModule("catalog", .{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/catalog.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "thesis", .module = thesis_mod },
            .{ .name = "classification", .module = classification_mod },
            .{ .name = "catalog_schema", .module = catalog_schema_mod },
        },
    });
    const basket_mod = b.addModule("basket", .{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/basket.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "thesis", .module = thesis_mod },
            .{ .name = "catalog", .module = catalog_mod },
            .{ .name = "c_abi", .module = c_abi_mod },
            .{ .name = "fixture_paths", .module = fixture_paths_mod },
        },
    });
    const portfolio_mod = b.addModule("portfolio", .{
        .root_source_file = b.path("src/tickoni/schema/portfolio/portfolio.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
        },
    });
    const tiles_mod = b.addModule("tiles", .{
        .root_source_file = b.path("src/tickoni/tiles/payment_pipeline/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "audit_tile", .module = audit_tile_mod },
            .{ .name = "audit_codec", .module = audit_codec_mod },
            .{ .name = "audit_schema", .module = audit_schema_mod },
            .{ .name = "runtime", .module = runtime_mod },
            .{ .name = "c_abi", .module = c_abi_mod },
            .{ .name = "util", .module = util_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    return Shared{
        .c_abi = c_abi_mod,
        .util = util_mod,
        .logger = logger_mod,
        .runtime = runtime_mod,
        .topologies = topologies_named_mod,
        .audit_schema = audit_schema_mod,
        .audit_codec = audit_codec_mod,
        .audit_tile = audit_tile_mod,
        .tier = tier_mod,
        .version = version_mod,
        .version_opts = version_opts,
        .fixture_paths = fixture_paths_mod,
        .doctor_checks = doctor_checks_mod,
        .doctor_output = doctor_output_mod,
        .demo_manifest = demo_manifest_mod,
        .demo_semver = demo_semver_mod,
        .demo_diagnostic = demo_diagnostic_mod,
        .demo_preflight = demo_preflight_mod,
        .demo_cli = demo_cli_mod,
        .demo_conformance = demo_conformance_mod,
        .demo_comparator = demo_comparator_mod,
        .demo_runner = demo_runner_mod,
        .demo_substitution = demo_substitution_mod,
        .classification = classification_mod,
        .capability = capability_mod,
        .thesis = thesis_mod,
        .catalog_schema = catalog_schema_mod,
        .catalog = catalog_mod,
        .basket = basket_mod,
        .portfolio = portfolio_mod,
        .tiles = tiles_mod,
    };
}
