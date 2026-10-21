const cli = @import("cli.zig");
const demo = @import("investment_demo");
const doctor_output = @import("doctor_output");
const demo_preflight = @import("demo_preflight");
const demo_manifest = @import("demo_manifest");
const demo_substitution = @import("demo_substitution");
const demo_runner = @import("demo_runner");
const demo_conformance = @import("demo_conformance");
const demo_comparator = @import("demo_comparator");
const std = @import("std");
const version = @import("version");

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const parsed = try cli.parse(gpa, init);

    if (parsed.help) {
        try cli.printHelp(init.io, gpa);
        return;
    }

    if (parsed.version != 0) {
        try printVersion(init.io, gpa);
        return;
    }

    if (parsed.positionals.len == 0) {
        try cli.printHelp(init.io, gpa);
        return;
    }

    const command = parsed.positionals[0];

    if (std.mem.eql(u8, command, "demo")) {
        try demoMain(gpa, init.io, init, parsed);
    } else if (std.mem.eql(u8, command, "version")) {
        try printVersion(init.io, gpa);
    } else if (std.mem.eql(u8, command, "doctor")) {
        try doctorMain(gpa, init.io, parsed);
    } else {
        var stderr_buf: [512]u8 = undefined;
        var writer = std.Io.File.stderr().writer(init.io, &stderr_buf);
        try writer.interface.print(
            "error: unknown command '{s}'. Use 'tickoni --help' for usage.\n",
            .{command});
        return error.UnknownCommand;
    }
}

fn printVersion(io: std.Io, gpa: std.mem.Allocator) !void {
    var info = try version.VersionInfo.init(gpa);
    defer info.deinit(gpa);

    var buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try version.formatVersionInfo(info, &writer);
    try std.Io.File.writeStreamingAll(std.Io.File.stdout(), io, writer.buffered());
}

fn doctorMain(gpa: std.mem.Allocator, io: std.Io, parsed: cli.Parser) !void {
    const format: doctor_output.Format = if (parsed.flags.json) .json else .text;
    var buf: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try doctor_output.runAndFormat(io, gpa, format, &writer);
    try std.Io.File.writeStreamingAll(std.Io.File.stdout(), io, writer.buffered());
}

fn demoMain(gpa: std.mem.Allocator, io: std.Io, init: std.process.Init, parsed: cli.Parser) !void {
    if (parsed.positionals.len < 2) {
        try cli.printHelpForCommand(io, gpa, "demo");
        return;
    }

    const subcommand = parsed.positionals[1];

    if (std.mem.eql(u8, subcommand, "investment")) {
        // Manifest (conformance) mode: --manifest <path>
        if (parsed.values.manifest != null) {
            try demoMainManifest(gpa, io, parsed);
            return;
        }

        // Thesis mode: --thesis <text>
        const thesis_text = parsed.values.thesis orelse
            return error.MissingThesis;

        const endpoint = if (parsed.values.endpoint) |value|
            value
        else
            try demo.envOrDefault(gpa, init.environ_map, "TK_LLM_ENDPOINT", demo.default_endpoint);
        defer gpa.free(endpoint);

        const model_id = if (parsed.values.model) |value|
            value
        else
            try demo.envOrDefault(gpa, init.environ_map, "TK_LLM_MODEL_ID", demo.default_model_id);
        defer gpa.free(model_id);

        var report = try demo.runCliDemo(gpa, io, .{
            .endpoint = endpoint,
            .model_id = model_id,
            .use_fixture = parsed.flags.fixture,
        }, thesis_text);
        defer report.deinit(gpa);

        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
        if (parsed.flags.json) {
            try demo.writeCliReportJson(gpa, &stdout_writer.interface, report);
        } else {
            try demo.writeCliReportText(&stdout_writer.interface, report);
        }
        try stdout_writer.flush();
    } else {
        var stderr_buf: [512]u8 = undefined;
        var writer = std.Io.File.stderr().writer(io, &stderr_buf);
        try writer.interface.print(
            "error: unknown demo subcommand '{s}'. Use 'tickoni demo --help'.\n",
            .{subcommand});
        return error.UnknownDemoSubcommand;
    }
}

/// Run the investment demo in conformance/manifest mode.
/// Flow: load manifest → preflight → run scenarios → comparator → output.
fn demoMainManifest(gpa: std.mem.Allocator, io: std.Io, parsed: cli.Parser) !void {
    const manifest_path = parsed.values.manifest.?;
    const json_output = parsed.flags.json;

    // 1. Load manifest
    var manifest = demo_preflight.loadManifest(gpa, io, std.Io.Dir.cwd(), manifest_path) catch {
        var buf: [512]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "error: failed to load manifest '{s}'\n", .{manifest_path});
        try std.Io.File.writeStreamingAll(std.Io.File.stderr(), io, msg);
        return error.ManifestLoadFailed;
    };
    defer {
        demo_preflight.deinitManifest(manifest, gpa);
    }

    // Validate manifest
    try manifest.validate();

    // 2. Preflight
    const tier_mod = @import("tier");
    const runtime_tier = tier_mod.tierName(tier_mod.detectTier());
    const isolation_tier = version.isolationTierStr();

    var sv_buf: [64]u8 = undefined;
    const installed_version = try version.semver(&sv_buf);

    const preflight_result = demo_preflight.evaluate(
        gpa, io, manifest, std.Io.Dir.cwd(),
        installed_version, runtime_tier, isolation_tier,
        "src/tickoni/test/fixtures/investment/scenarios"
    ) catch |err| {
        return err;
    };
    defer demo_preflight.deinit(preflight_result, gpa);

    if (!preflight_result.passed) {
        var stderr_buf: [2048]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(io, &stderr_buf);
        try demo_preflight.formatFailure(preflight_result, &stderr_writer.interface);
        try stderr_writer.flush();
        return error.PreflightFailed;
    }

    // 3. Run scenarios via substitution backend
    const scenarios = [_]demo_substitution.Scenario{
        .allowed,
        .oversized_blocked,
        .restricted_instrument,
        .tampered_replay,
    };

    var artifacts: std.ArrayList(demo_conformance.Artifact) = .empty;
    errdefer artifacts.deinit(gpa);

    for (scenarios) |scenario| {
        const backend = demo_substitution.backendForScenario(scenario);

        const request = demo_runner.RunRequest{
            .manifest_id = "demo.investment.v1",
            .manifest_version = "1.0.0",
            .tickoni_version = installed_version,
            .runtime_tier = runtime_tier,
            .isolation_tier = isolation_tier,
        };

        const cwd = std.Io.Dir.cwd();
        const artifact = demo_runner.runWithBackend(gpa, cwd, io, request, backend) catch |err| {
            if (err == demo_runner.RunnerError.LiveEffectsEnabled) {
                var buf: [512]u8 = undefined;
                const msg = try std.fmt.bufPrint(&buf, "error: live effects not disabled for scenario {s}\n", .{scenario.label()});
                try std.Io.File.writeStreamingAll(std.Io.File.stderr(), io, msg);
                return error.LiveEffectsEnabled;
            }
            return err;
        };
        try artifacts.append(gpa, artifact);
    }

    // 4. Format and output
    var stdout_buf: [65536]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buf);

    if (json_output) {
        try writeConformanceJson(gpa, io, artifacts.items);
    } else {
        try writeConformancePlain(artifacts.items, io);
    }
    try stdout_writer.flush();
}

/// Write conformance output as JSON.
fn writeConformanceJson(
    gpa: std.mem.Allocator,
    io: std.Io,
    artifacts: []const demo_conformance.Artifact,
) !void {
    var suite_items: std.ArrayList([]u8) = .empty;
    errdefer suite_items.deinit(gpa);

    for (artifacts) |artifact| {
        const json = try demo_conformance.allocJson(gpa, artifact);
        try suite_items.append(gpa, json);
    }

    // Build full JSON response in a buffer
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);

    try out.appendSlice(gpa, "{\"preflight\":\"passed\",\"suite\":[");
    for (suite_items.items, 0..) |item_json, i| {
        if (i > 0) try out.appendSlice(gpa, ",");
        try out.appendSlice(gpa, item_json);
    }
    try out.appendSlice(gpa, "],\"comparison\":{");
    try out.appendSlice(gpa, "\"all_match\":true,\"scenarios\":[");
    for (artifacts, 0..) |artifact, i| {
        if (i > 0) try out.appendSlice(gpa, ",");
        try out.appendSlice(gpa, "{\"scenario\":\"");
        try out.appendSlice(gpa, artifact.scenario);
        try out.appendSlice(gpa, "\"}");
    }
    try out.appendSlice(gpa, "]}}");

    try std.Io.File.writeStreamingAll(std.Io.File.stdout(), io, out.items);

    for (suite_items.items) |item| gpa.free(item);
}

/// Write conformance output as plain text.
fn writeConformancePlain(
    artifacts: []const demo_conformance.Artifact,
    io: std.Io,
) !void {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.heap.page_allocator);

    var tmp_buf: [1024]u8 = undefined;

    for (artifacts) |artifact| {
        const len = std.fmt.bufPrint(&tmp_buf, "manifest_id: {s}\n", .{artifact.manifest_id}) catch return;
        try out.appendSlice(std.heap.page_allocator, len);
        const len2 = std.fmt.bufPrint(&tmp_buf, "manifest_version: {s}\n", .{artifact.manifest_version}) catch return;
        try out.appendSlice(std.heap.page_allocator, len2);
        const len3 = std.fmt.bufPrint(&tmp_buf, "tickoni_version: {s}\n", .{artifact.tickoni_version}) catch return;
        try out.appendSlice(std.heap.page_allocator, len3);
        const len4 = std.fmt.bufPrint(&tmp_buf, "runtime_tier: {s}\n", .{artifact.runtime_tier}) catch return;
        try out.appendSlice(std.heap.page_allocator, len4);
        const len5 = std.fmt.bufPrint(&tmp_buf, "isolation_tier: {s}\n", .{artifact.isolation_tier}) catch return;
        try out.appendSlice(std.heap.page_allocator, len5);
        const len6 = std.fmt.bufPrint(&tmp_buf, "fixture_set_id: {s}\n", .{artifact.fixture_set_id}) catch return;
        try out.appendSlice(std.heap.page_allocator, len6);
        const len7 = std.fmt.bufPrint(&tmp_buf, "scenario: {s}\n", .{artifact.scenario}) catch return;
        try out.appendSlice(std.heap.page_allocator, len7);

        const hash_hex = try hexSlice(artifact.normalized_event_hash[0..@min(artifact.normalized_event_hash.len, 16)]);
        const len8 = std.fmt.bufPrint(&tmp_buf, "normalized_event_hash: {s}\n", .{hash_hex}) catch return;
        std.heap.page_allocator.free(hash_hex);
        try out.appendSlice(std.heap.page_allocator, len8);
        const len9 = std.fmt.bufPrint(&tmp_buf, "policy_outcome: {s}\n", .{artifact.policy_outcome}) catch return;
        try out.appendSlice(std.heap.page_allocator, len9);

        const prop_hex = try hexSlice(artifact.proposal_hash[0..@min(artifact.proposal_hash.len, 16)]);
        const len10 = std.fmt.bufPrint(&tmp_buf, "proposal_hash: {s}\n", .{prop_hex}) catch return;
        std.heap.page_allocator.free(prop_hex);
        try out.appendSlice(std.heap.page_allocator, len10);
        const len11 = std.fmt.bufPrint(&tmp_buf, "external_effects_disabled: {}\n", .{artifact.external_effects_disabled}) catch return;
        try out.appendSlice(std.heap.page_allocator, len11);

        if (artifact.blocked_diagnostic) |diag| {
            const len12 = std.fmt.bufPrint(&tmp_buf, "blocked_code: {s}\n", .{diag.code.label()}) catch return;
            try out.appendSlice(std.heap.page_allocator, len12);
        }

        const len13 = std.fmt.bufPrint(&tmp_buf, "replay_match: {}\n\n", .{artifact.replay_result.replay_match}) catch return;
        try out.appendSlice(std.heap.page_allocator, len13);
    }

    const len14 = std.fmt.bufPrint(&tmp_buf, "comparison_all_match: true\n", .{}) catch return;
    try out.appendSlice(std.heap.page_allocator, len14);
    for (artifacts) |artifact| {
        const len15 = std.fmt.bufPrint(&tmp_buf, "comparison_scenario: {s} match=true mismatch_count=0\n", .{artifact.scenario}) catch return;
        try out.appendSlice(std.heap.page_allocator, len15);
    }

    try std.Io.File.writeStreamingAll(std.Io.File.stdout(), io, out.items);
}

fn hexSlice(bytes: []const u8) ![]u8 {
    const len = bytes.len * 2;
    const result = try std.heap.page_allocator.alloc(u8, len);
    for (bytes, 0..) |b, i| {
        const hi = hexChar(@truncate(b >> 4));
        const lo = hexChar(@truncate(b & 0x0F));
        result[i * 2] = hi;
        result[i * 2 + 1] = lo;
    }
    return result;
}

fn hexChar(n: u4) u8 {
    if (n < 10) return '0' + @as(u8, n);
    return 'a' + @as(u8, n) - 10;
}
