/// Thin Zig wrapper over tk_model_stem.c — the Firedancer stem tile for tkmodl
/// (fixture/replay only).
///
/// Exposes the C stem tile's public symbols (run tile descriptor, scratch
/// footprint, governance helper, configuration entry point) as extern
/// declarations with Zig-native wrappers. The wire and configuration structs
/// come from the one C definition (audit_schema.h, via translate-c) — nothing
/// here mirrors a C struct by hand.
const std = @import("std");
const audit_mod = @import("audit_mod");

pub const ModelRequestMsg = audit_mod.ModelRequestMsg;
pub const ModelResultMsg = audit_mod.ModelResultMsg;
pub const ModelAuditMsg = audit_mod.ModelAuditMsg;
pub const TkModlRuntimeConfig = audit_mod.TkModlRuntimeConfig;
pub const TkModlFixtureEntry = audit_mod.TkModlFixtureEntry;

/// Opaque handle for fd_topo_run_tile_t. Only shim code knows the real layout.
pub const TopoRunTile = opaque {};

extern fn tk_get_model_run_name() [*:0]const u8;
extern fn tk_get_model_run_tile() ?*TopoRunTile;
extern fn tk_get_model_run_run() ?*anyopaque;
extern fn tk_get_model_run_scratch_align() ?*anyopaque;
extern fn tk_get_model_run_scratch_footprint() ?*anyopaque;
extern fn tk_get_model_run_privileged_init() ?*anyopaque;
extern fn tk_get_model_run_unprivileged_init() ?*anyopaque;
extern fn tkmodl_tile_scratch_footprint() usize;
extern fn tkmodl_tile_scratch_align() usize;
extern fn tkmodl_set_event_count(event_count: u64) void;
extern fn tkmodl_configure(cfg: ?*const TkModlRuntimeConfig) c_int;
extern fn tkmodl_validate(cfg: *const TkModlRuntimeConfig, req: *const ModelRequestMsg, scope_dim_out: ?*[32]u8) u8;
extern fn tkmodl_request_well_formed(req: *const ModelRequestMsg) c_int;
extern fn tkmodl_ctx_processed(scratch: ?*anyopaque) usize;
extern fn tkmodl_ctx_allowed(scratch: ?*anyopaque) usize;
extern fn tkmodl_ctx_denied(scratch: ?*anyopaque) usize;
extern fn tk_topob_tickoni_tile_scratch_footprint(tile_name: [*:0]const u8) usize;

/// Result of `configure`, mirroring the TKMODL_CFG_* codes.
pub const ConfigError = error{
    NullConfig,
    BadMagic,
    BadVersion,
    LiveProviderEnabled,
    AllowlistBound,
    FixtureBound,
    Unknown,
};

pub const config_magic: u32 = audit_mod.TKMODL_CONFIG_MAGIC;
pub const config_version: u16 = audit_mod.TKMODL_CONFIG_VERSION;
pub const wire_version: u16 = audit_mod.TKMODL_WIRE_VERSION;

pub fn getModelRunName() [*:0]const u8 {
    return tk_get_model_run_name();
}

pub fn getModelRunTile() ?*TopoRunTile {
    return tk_get_model_run_tile();
}

pub fn getModelRun() ?*anyopaque {
    return tk_get_model_run_run();
}

pub fn getModelRunScratchAlign() ?*anyopaque {
    return tk_get_model_run_scratch_align();
}

pub fn getModelRunScratchFootprint() ?*anyopaque {
    return tk_get_model_run_scratch_footprint();
}

pub fn getModelRunPrivilegedInit() ?*anyopaque {
    return tk_get_model_run_privileged_init();
}

pub fn getModelRunUnprivilegedInit() ?*anyopaque {
    return tk_get_model_run_unprivileged_init();
}

pub fn modelScratchFootprint() usize {
    return tkmodl_tile_scratch_footprint();
}

pub fn modelScratchAlign() usize {
    return tkmodl_tile_scratch_align();
}

/// Sets the shutdown gate. The supervisor and every child must pass the
/// identical value.
pub fn setEventCount(event_count: u64) void {
    tkmodl_set_event_count(event_count);
}

/// Validates and stores the runtime configuration for this process. Nothing is
/// stored on error.
pub fn configure(cfg: *const TkModlRuntimeConfig) ConfigError!void {
    return switch (tkmodl_configure(cfg)) {
        0 => {},
        1 => error.NullConfig,
        2 => error.BadMagic,
        3 => error.BadVersion,
        4 => error.LiveProviderEnabled,
        5 => error.AllowlistBound,
        6 => error.FixtureBound,
        else => error.Unknown,
    };
}

/// Governance verdict (a `ModelDecision` tag) for one request. For
/// MODEL_DENY_MISSING_SCOPE, `scope_dim_out` receives the missing field name.
pub fn validate(cfg: *const TkModlRuntimeConfig, req: *const ModelRequestMsg, scope_dim_out: ?*[32]u8) u8 {
    return tkmodl_validate(cfg, req, scope_dim_out);
}

pub fn requestWellFormed(req: *const ModelRequestMsg) bool {
    return tkmodl_request_well_formed(req) != 0;
}

pub fn ctxProcessed(scratch: ?*anyopaque) u64 {
    return tkmodl_ctx_processed(scratch);
}

pub fn ctxAllowed(scratch: ?*anyopaque) u64 {
    return tkmodl_ctx_allowed(scratch);
}

pub fn ctxDenied(scratch: ?*anyopaque) u64 {
    return tkmodl_ctx_denied(scratch);
}

/// Name of the supervisor-written configuration file, beside
/// payment_pipeline.config and topology.spec.
pub const config_file_name = "tkmodl.config";

pub const ConfigFileError = error{ ConfigTruncated, ConfigTrailingBytes } || ConfigError;

/// Writes `cfg` verbatim. Its own magic/version fields are the file's header.
pub fn writeConfigFile(io: std.Io, dir: std.Io.Dir, sub_path: []const u8, cfg: *const TkModlRuntimeConfig) !void {
    // std.Io.Dir treats an absolute sub_path as relative to `dir`; resolve it
    // from the filesystem root instead (c_abi cannot import runtime/file_io).
    var file = if (sub_path.len > 0 and sub_path[0] == '/')
        try std.Io.Dir.createFileAbsolute(io, sub_path, .{})
    else
        try dir.createFile(io, sub_path, .{});
    defer file.close(io);
    try file.writePositionalAll(io, std.mem.asBytes(cfg), 0);
}

/// Reads and validates the configuration file, then installs it with
/// `configure`. Fails closed: a missing, short, long, mis-versioned or
/// live-enabled file installs nothing.
pub fn loadConfigFile(io: std.Io, dir: std.Io.Dir, sub_path: []const u8) !void {
    var file = if (sub_path.len > 0 and sub_path[0] == '/')
        try std.Io.Dir.openFileAbsolute(io, sub_path, .{})
    else
        try dir.openFile(io, sub_path, .{});
    defer file.close(io);
    var cfg: TkModlRuntimeConfig = undefined;
    const buf = std.mem.asBytes(&cfg);
    const n = try file.readPositionalAll(io, buf, 0);
    if (n != buf.len) return error.ConfigTruncated;
    var extra: [1]u8 = undefined;
    if ((try file.readPositionalAll(io, &extra, buf.len)) != 0) return error.ConfigTrailingBytes;
    try configure(&cfg);
}

/// Copies `src` into a fixed-width NUL-padded wire field. Fails if the value
/// would not leave a terminating NUL.
pub fn setField(dst: []u8, src: []const u8) error{FieldTooLong}!void {
    if (src.len >= dst.len) return error.FieldTooLong;
    @memset(dst, 0);
    @memcpy(dst[0..src.len], src);
}

// ---------------------------------------------------------------------------
// Tests: identity, fixed scratch, wire layout, and configuration contract.
// Governance parity with the retained Zig validator lives in
// tiles/model/validator_parity.zig so this module stays dependency-free.
// ---------------------------------------------------------------------------

fn baseConfig() TkModlRuntimeConfig {
    var cfg = std.mem.zeroes(TkModlRuntimeConfig);
    cfg.magic = config_magic;
    cfg.version = config_version;
    return cfg;
}

test "tkmodl tile identity — name is TILE_ID_TKMODL" {
    try std.testing.expectEqualStrings("tkmodl", std.mem.sliceTo(tk_get_model_run_name(), 0));
}

test "tkmodl tile identity — run, init and scratch callbacks are non-null" {
    try std.testing.expect(tk_get_model_run_run() != null);
    try std.testing.expect(tk_get_model_run_privileged_init() != null);
    try std.testing.expect(tk_get_model_run_unprivileged_init() != null);
    try std.testing.expect(tk_get_model_run_scratch_align() != null);
    try std.testing.expect(tk_get_model_run_scratch_footprint() != null);
}

test "tkmodl scratch align — describes the context block, not fd_stem's stack scratch" {
    // The context holds u64s, pointers and the configuration; 8-byte aligned
    // on current supported targets. 128 (FD_STEM_SCRATCH_ALIGN) here means
    // .scratch_align was wired to the stem-generated callback instead.
    try std.testing.expectEqual(@as(usize, 8), tkmodl_tile_scratch_align());
}

test "tkmodl scratch footprint — aligned, larger than the placeholder, and fixed" {
    const footprint = modelScratchFootprint();
    try std.testing.expect(footprint > 1);
    try std.testing.expectEqual(@as(usize, 0), footprint % modelScratchAlign());
    // The context embeds the staged request and the bounded configuration.
    try std.testing.expect(footprint >= @sizeOf(ModelRequestMsg) + @sizeOf(TkModlRuntimeConfig));
    for ([_]u64{ 0, 1, 32 }) |event_count| {
        setEventCount(event_count);
        try std.testing.expectEqual(footprint, modelScratchFootprint());
    }
}

test "tkmodl scratch footprint — topob wrapper matches the direct call" {
    try std.testing.expectEqual(
        tkmodl_tile_scratch_footprint(),
        tk_topob_tickoni_tile_scratch_footprint("tkmodl"),
    );
}

test "tkmodl wire records fit the declared link MTUs" {
    // Bounds from the decision record: request 1024, result 256, audit 256.
    try std.testing.expect(@sizeOf(ModelRequestMsg) <= 1024);
    try std.testing.expect(@sizeOf(ModelResultMsg) <= 256);
    try std.testing.expect(@sizeOf(ModelAuditMsg) <= 256);
}

test "tkmodl configure — accepts a fixture/replay configuration" {
    const cfg = baseConfig();
    try configure(&cfg);
}

test "tkmodl configure — rejects a live provider (fixture/replay only)" {
    var cfg = baseConfig();
    cfg.live_provider_enabled = 1;
    try std.testing.expectError(error.LiveProviderEnabled, configure(&cfg));
}

test "tkmodl configure — rejects bad magic, bad version, and over-bound tables" {
    var cfg = baseConfig();
    cfg.magic = 0xdeadbeef;
    try std.testing.expectError(error.BadMagic, configure(&cfg));

    cfg = baseConfig();
    cfg.version = config_version + 1;
    try std.testing.expectError(error.BadVersion, configure(&cfg));

    cfg = baseConfig();
    cfg.allowed_model_count = audit_mod.TKMODL_MAX_ALLOWED_MODELS + 1;
    try std.testing.expectError(error.AllowlistBound, configure(&cfg));

    cfg = baseConfig();
    cfg.fixture_count = audit_mod.TKMODL_FIXTURE_CAP + 1;
    try std.testing.expectError(error.FixtureBound, configure(&cfg));
}

fn goodRequest() ModelRequestMsg {
    var req = std.mem.zeroes(ModelRequestMsg);
    req.version = wire_version;
    req.replay_mode = audit_mod.TKMODL_REPLAY_MODE_REPLAY;
    req.request_id = 1;
    req.replay_substitution_id = 7;
    setField(&req.model_id, "fixture.model") catch unreachable;
    setField(&req.actor_role, "reviewer") catch unreachable;
    setField(&req.workflow, "trading_control") catch unreachable;
    setField(&req.capability, "trading_order.propose") catch unreachable;
    setField(&req.capability_envelope_id, "capenv.fixture") catch unreachable;
    setField(&req.policy_version, "v1") catch unreachable;
    setField(&req.budget_id, "budget.fixture") catch unreachable;
    return req;
}

test "tkmodl wire shape — a well-formed request passes" {
    const req = goodRequest();
    try std.testing.expect(requestWellFormed(&req));
}

test "tkmodl wire shape — wrong version, bad replay mode and unterminated fields are rejected" {
    var req = goodRequest();
    req.version = wire_version + 1;
    try std.testing.expect(!requestWellFormed(&req));

    req = goodRequest();
    req.replay_mode = 2;
    try std.testing.expect(!requestWellFormed(&req));

    // A field filled to its full width has no terminating NUL.
    req = goodRequest();
    @memset(&req.model_id, 'x');
    try std.testing.expect(!requestWellFormed(&req));
    req = goodRequest();
    @memset(&req.budget_id, 'x');
    try std.testing.expect(!requestWellFormed(&req));
}

test "tkmodl setField — rejects a value that leaves no terminator" {
    var buf: [4]u8 = undefined;
    try setField(&buf, "abc");
    try std.testing.expectError(error.FieldTooLong, setField(&buf, "abcd"));
}
