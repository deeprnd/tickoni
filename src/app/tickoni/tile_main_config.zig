/// Fail-closed config handoff for stem tiles.
///
/// The supervisor writes `payment_pipeline.config` (tkpoly's signed policy
/// limit) and `tkmodl.config` (tkmodl's limits, allowlist and fixture table)
/// beside each child's topology.spec. tile_main.zig's `stemRun` calls these
/// loaders before the C harness starts, because neither privileged_init nor a
/// fragment callback may read a file. A missing, malformed, mismatched or
/// live-enabled file installs nothing and the child exits nonzero.
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const tiles = @import("tiles");

/// Reads the supervisor-written payment_pipeline.config beside this child's
/// topology.spec and pushes its signed `policy_limit_cents` into
/// tk_policy_stem.c through the C setter.
///
/// Requires the file and requires its pipeline event count to agree with the
/// TopologySpec the same child rebuilt its topology from: a disagreement means
/// the two halves of the handoff describe different runs, and the policy gate
/// and the pipeline's event budget would diverge. There is no default-limit
/// fallback — a financial limit this child could not read is a startup
/// failure, not a value to guess.
///
/// `dir` defaults to std.Io.Dir.cwd() — tests can pass a temp-dir handle
/// instead, since the unit-test std library is minimal and lacks cwd().
pub fn loadPolicyLimit(
    io: std.Io,
    spec: *const rt.launch_spec.LaunchSpec,
    topology_event_count: u64,
    dir: ?std.Io.Dir,
) !void {
    var path_buf: [rt.launch_spec.shmem_path_cap + 32]u8 = undefined;
    const path = if (spec.shmemPath().len > 0)
        try std.fmt.bufPrint(&path_buf, "{s}/payment_pipeline.config", .{spec.shmemPath()})
    else
        try std.fmt.bufPrint(&path_buf, "payment_pipeline.config", .{});
    // readProcessConfig owns the size/magic/version checks; this entrypoint
    // does not re-decode the file.
    const cfg = try tiles.process.readProcessConfig(io, dir orelse std.Io.Dir.cwd(), path);
    if (cfg.pipeline.event_count != topology_event_count) {
        return error.PolicyConfigEventCountMismatch;
    }
    c_abi.tkpoly.setPolicyLimitCents(cfg.pipeline.policy_limit_cents);
    std.debug.print(
        "[tile-main] stemRun: tkpoly policy_limit_cents={d} event_count={d}\n",
        .{ cfg.pipeline.policy_limit_cents, cfg.pipeline.event_count },
    );
}

/// Reads the supervisor-written tkmodl.config beside this child's
/// topology.spec and installs it in the C tile. `dir` defaults to cwd (tests
/// pass a temp dir).
pub fn loadModelConfig(
    io: std.Io,
    spec: *const rt.launch_spec.LaunchSpec,
    dir: ?std.Io.Dir,
) !void {
    var path_buf: [rt.launch_spec.shmem_path_cap + 32]u8 = undefined;
    const path = if (spec.shmemPath().len > 0)
        try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ spec.shmemPath(), c_abi.tkmodl.config_file_name })
    else
        try std.fmt.bufPrint(&path_buf, "{s}", .{c_abi.tkmodl.config_file_name});
    try c_abi.tkmodl.loadConfigFile(io, dir orelse std.Io.Dir.cwd(), path);
    std.debug.print("[tile-main] stemRun: tkmodl config loaded from {s}\n", .{path});
}

// ---------------------------------------------------------------------------
// P4.3 — Fail closed on invalid configuration handoff.
// ---------------------------------------------------------------------------
//
// These tests use a simple string path (no temp-dir realpath) because the
// unit-test std library is minimal: no fs.cwd / realPath.  The shmem_path
// is only used for string concatenation in loadPolicyLimit, not for real
// filesystem access — the test writes the config file via tmp.dir which
// uses std.testing.tmpDir.

test "tile_main_config: loadPolicyLimit fails on missing config file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const spec = try rt.launch_spec.LaunchSpec.init(.{
        .tile_idx = 0,
        .tile_id = rt.tile_ids.tkings,
        .cpu_placement = .floating,
        .workspace_name = try rt.link.WorkspaceName.parse("tkpay0"),
        .cnc_gaddr = 0,
        .shmem_path = "",
        .heartbeat_interval_ns = 1,
    });

    // loadPolicyLimit must fail — no config file exists at shmem_path.
    try std.testing.expectError(error.FileNotFound, loadPolicyLimit(
        std.testing.io,
        &spec,
        4,
        tmp.dir,
    ));
}

test "tile_main_config: loadPolicyLimit fails on truncated config file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const spec = try rt.launch_spec.LaunchSpec.init(.{
        .tile_idx = 0,
        .tile_id = rt.tile_ids.tkings,
        .cpu_placement = .floating,
        .workspace_name = try rt.link.WorkspaceName.parse("tkpay0"),
        .cnc_gaddr = 0,
        .shmem_path = "",
        .heartbeat_interval_ns = 1,
    });

    // Write a truncated config (only 4 bytes of a ~56-byte struct).
    var file = try tmp.dir.createFile(std.testing.io, "payment_pipeline.config", .{});
    try file.writePositionalAll(std.testing.io, &[_]u8{ 0x54, 0x4b, 0x50, 0x43 }, 0);
    file.close(std.testing.io);

    try std.testing.expectError(error.ProcessConfigTruncated, loadPolicyLimit(
        std.testing.io,
        &spec,
        4,
        tmp.dir,
    ));
}

test "tile_main_config: loadPolicyLimit fails on bad magic in config file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var file_struct = tiles.process.ProcessConfigFile{};
    file_struct.magic_field = 0xdeadbeef;
    var file = try tmp.dir.createFile(std.testing.io, "payment_pipeline.config", .{});
    try file.writePositionalAll(std.testing.io, std.mem.asBytes(&file_struct), 0);
    file.close(std.testing.io);

    const spec = try rt.launch_spec.LaunchSpec.init(.{
        .tile_idx = 0,
        .tile_id = rt.tile_ids.tkings,
        .cpu_placement = .floating,
        .workspace_name = try rt.link.WorkspaceName.parse("tkpay0"),
        .cnc_gaddr = 0,
        .shmem_path = "",
        .heartbeat_interval_ns = 1,
    });

    try std.testing.expectError(error.ProcessConfigBadMagic, loadPolicyLimit(
        std.testing.io,
        &spec,
        4,
        tmp.dir,
    ));
}

test "tile_main_config: loadPolicyLimit fails on unsupported version in config file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var file_struct = tiles.process.ProcessConfigFile{};
    file_struct.version_field = 0;
    var file = try tmp.dir.createFile(std.testing.io, "payment_pipeline.config", .{});
    try file.writePositionalAll(std.testing.io, std.mem.asBytes(&file_struct), 0);
    file.close(std.testing.io);

    const spec = try rt.launch_spec.LaunchSpec.init(.{
        .tile_idx = 0,
        .tile_id = rt.tile_ids.tkings,
        .cpu_placement = .floating,
        .workspace_name = try rt.link.WorkspaceName.parse("tkpay0"),
        .cnc_gaddr = 0,
        .shmem_path = "",
        .heartbeat_interval_ns = 1,
    });

    try std.testing.expectError(error.ProcessConfigUnsupportedVersion, loadPolicyLimit(
        std.testing.io,
        &spec,
        4,
        tmp.dir,
    ));
}

test "tile_main_config: loadPolicyLimit fails on mismatched event count" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const spec = try rt.launch_spec.LaunchSpec.init(.{
        .tile_idx = 0,
        .tile_id = rt.tile_ids.tkings,
        .cpu_placement = .floating,
        .workspace_name = try rt.link.WorkspaceName.parse("tkpay0"),
        .cnc_gaddr = 0,
        .shmem_path = "",
        .heartbeat_interval_ns = 1,
    });

    // Config says 4 events — mismatched with topology's 100.
    const cfg = tiles.process.ProcessRuntimeConfig{
        .pipeline = .{ .event_count = 4, .policy_limit_cents = 1_000 },
    };
    try tiles.process.writeProcessConfig(cfg, std.testing.io, tmp.dir, "payment_pipeline.config");

    try std.testing.expectError(error.PolicyConfigEventCountMismatch, loadPolicyLimit(
        std.testing.io,
        &spec,
        100, // topology says 100 events, config says 4
        tmp.dir,
    ));
}

// ---------------------------------------------------------------------------
// tkmodl.config handoff — fail closed (same contract as the policy limit):
// a missing, short, long, mis-magic'd, mis-versioned, or live-enabled file
// installs nothing and the child exits nonzero before the C harness runs.
// ---------------------------------------------------------------------------

fn modelSpec() !rt.launch_spec.LaunchSpec {
    return rt.launch_spec.LaunchSpec.init(.{
        .tile_idx = 0,
        .tile_id = rt.tile_ids.tkmodl,
        .cpu_placement = .floating,
        .workspace_name = try rt.link.WorkspaceName.parse("tkpay0"),
        .cnc_gaddr = 0,
        .shmem_path = "",
        .heartbeat_interval_ns = 1,
    });
}

fn writeModelConfigBytes(tmp: anytype, bytes: []const u8) !void {
    var file = try tmp.dir.createFile(std.testing.io, c_abi.tkmodl.config_file_name, .{});
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, bytes, 0);
}

fn validModelConfig() c_abi.tkmodl.TkModlRuntimeConfig {
    var cfg = std.mem.zeroes(c_abi.tkmodl.TkModlRuntimeConfig);
    cfg.magic = c_abi.tkmodl.config_magic;
    cfg.version = c_abi.tkmodl.config_version;
    return cfg;
}

test "tile_main_config: loadModelConfig accepts a valid tkmodl.config" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const spec = try modelSpec();
    const cfg = validModelConfig();
    try writeModelConfigBytes(&tmp, std.mem.asBytes(&cfg));
    try loadModelConfig(std.testing.io, &spec, tmp.dir);
}

test "tile_main_config: loadModelConfig fails on a missing file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const spec = try modelSpec();
    try std.testing.expectError(error.FileNotFound, loadModelConfig(std.testing.io, &spec, tmp.dir));
}

test "tile_main_config: loadModelConfig fails on a truncated file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const spec = try modelSpec();
    const cfg = validModelConfig();
    try writeModelConfigBytes(&tmp, std.mem.asBytes(&cfg)[0..16]);
    try std.testing.expectError(error.ConfigTruncated, loadModelConfig(std.testing.io, &spec, tmp.dir));
}

test "tile_main_config: loadModelConfig fails on trailing bytes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const spec = try modelSpec();
    const cfg = validModelConfig();
    var bytes: [@sizeOf(c_abi.tkmodl.TkModlRuntimeConfig) + 1]u8 = undefined;
    @memcpy(bytes[0..@sizeOf(c_abi.tkmodl.TkModlRuntimeConfig)], std.mem.asBytes(&cfg));
    bytes[bytes.len - 1] = 0;
    try writeModelConfigBytes(&tmp, &bytes);
    try std.testing.expectError(error.ConfigTrailingBytes, loadModelConfig(std.testing.io, &spec, tmp.dir));
}

test "tile_main_config: loadModelConfig fails on bad magic, bad version, and a live provider" {
    const spec = try modelSpec();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var cfg = validModelConfig();
    cfg.magic = 0xdeadbeef;
    try writeModelConfigBytes(&tmp, std.mem.asBytes(&cfg));
    try std.testing.expectError(error.BadMagic, loadModelConfig(std.testing.io, &spec, tmp.dir));

    cfg = validModelConfig();
    cfg.version = c_abi.tkmodl.config_version + 1;
    try writeModelConfigBytes(&tmp, std.mem.asBytes(&cfg));
    try std.testing.expectError(error.BadVersion, loadModelConfig(std.testing.io, &spec, tmp.dir));

    cfg = validModelConfig();
    cfg.live_provider_enabled = 1;
    try writeModelConfigBytes(&tmp, std.mem.asBytes(&cfg));
    try std.testing.expectError(error.LiveProviderEnabled, loadModelConfig(std.testing.io, &spec, tmp.dir));
}
