//! Parity between the retained Zig governance validator (`validator.zig`) and
//! the C helper the tkmodl stem tile runs (`tkmodl_validate`). The Zig
//! validator remains the behavioral reference for the in-process lane; the C
//! helper must return the same verdict, in the same branch order, for the same
//! scope, limits and allowlist. Placed here (not in c_abi/tkmodl.zig) so the
//! FFI module stays free of a dependency on the model schema.

const std = @import("std");
const c_abi = @import("c_abi");
const validator = @import("validator.zig");
const schema = @import("model_messages");

const tkmodl = c_abi.tkmodl;

const Case = struct {
    name: []const u8,
    /// Mutates a request that is valid under `baseConfig`.
    mutate: *const fn (req: *schema.TkModlRequest) void,
    /// Mutates the baseline configuration for this case.
    config: *const fn (cfg: *schema.TkModlConfig) void = noConfig,
};

fn noConfig(_: *schema.TkModlConfig) void {}
fn noMutate(_: *schema.TkModlRequest) void {}

fn baseConfig() schema.TkModlConfig {
    var c = schema.TkModlConfig{
        .live_provider_enabled = false,
        .hard_max_output_tokens = 1024,
        .hard_max_context_tokens = 4096,
        .hard_max_retry_count = 3,
        .hard_timeout_ms = 30_000,
        .per_run_token_budget = 2048,
    };
    c.allowed_model_ids[0] = "test-model";
    c.allowed_model_id_count = 1;
    return c;
}

fn baseRequest() schema.TkModlRequest {
    return .{
        .model_id = "test-model",
        .messages = &.{},
        .actor_role = "ops_reviewer",
        .workflow = "trading_control",
        .capability = "trading_order.propose",
        .capability_envelope_id = "capenv.fixture",
        .policy_version = "v1",
        .budget_id = "budget.fixture",
        .max_output_tokens = 512,
        .max_context_tokens = 2048,
        .retry_limit = 1,
        .replay_mode = .replay,
        .replay_substitution_id = 7,
    };
}

fn toWire(req: schema.TkModlRequest) !tkmodl.ModelRequestMsg {
    var m = std.mem.zeroes(tkmodl.ModelRequestMsg);
    m.version = tkmodl.wire_version;
    m.replay_mode = if (req.replay_mode == .replay) 1 else 0;
    m.retry_limit = req.retry_limit;
    m.max_context_tokens = req.max_context_tokens;
    m.max_output_tokens = req.max_output_tokens;
    m.replay_substitution_id = req.replay_substitution_id;
    try tkmodl.setField(&m.model_id, req.model_id);
    try tkmodl.setField(&m.actor_role, req.actor_role);
    try tkmodl.setField(&m.workflow, req.workflow);
    try tkmodl.setField(&m.capability, req.capability);
    try tkmodl.setField(&m.capability_envelope_id, req.capability_envelope_id);
    try tkmodl.setField(&m.policy_version, req.policy_version);
    try tkmodl.setField(&m.budget_id, req.budget_id);
    return m;
}

fn toWireConfig(cfg: schema.TkModlConfig) !tkmodl.TkModlRuntimeConfig {
    var w = std.mem.zeroes(tkmodl.TkModlRuntimeConfig);
    w.magic = tkmodl.config_magic;
    w.version = tkmodl.config_version;
    w.live_provider_enabled = @intFromBool(cfg.live_provider_enabled);
    w.hard_max_context_tokens = cfg.hard_max_context_tokens;
    w.hard_max_output_tokens = cfg.hard_max_output_tokens;
    w.hard_timeout_ms = cfg.hard_timeout_ms;
    w.per_run_token_budget = cfg.per_run_token_budget;
    w.hard_max_retry_count = cfg.hard_max_retry_count;
    w.allowed_model_count = cfg.allowed_model_id_count;
    for (cfg.allowed_model_ids[0..cfg.allowed_model_id_count], 0..) |id, i| {
        try tkmodl.setField(&w.allowed_model_ids[i], id);
    }
    return w;
}

/// Zig verdict -> ModelDecision tag (audit_schema.h).
fn wireTag(d: schema.TkModlDecision) u8 {
    return switch (d) {
        .allow_live => 0,
        .allow_replay => 1,
        .deny_missing_scope => 2,
        .deny_model_not_allowed => 3,
        .deny_budget_exhausted => 4,
        .deny_context_limit => 5,
        .deny_output_limit => 6,
        .deny_retry_limit => 7,
        .deny_live_provider_disabled => 8,
        .deny_replay_substitution_missing => 9,
    };
}

fn m_model(r: *schema.TkModlRequest) void {
    r.model_id = "";
}
fn m_budget(r: *schema.TkModlRequest) void {
    r.budget_id = "";
}
fn m_policy(r: *schema.TkModlRequest) void {
    r.policy_version = "";
}
fn m_envelope(r: *schema.TkModlRequest) void {
    r.capability_envelope_id = "";
}
fn m_capability(r: *schema.TkModlRequest) void {
    r.capability = "";
}
fn m_role(r: *schema.TkModlRequest) void {
    r.actor_role = "";
}
fn m_workflow(r: *schema.TkModlRequest) void {
    r.workflow = "";
}
fn m_model_other(r: *schema.TkModlRequest) void {
    r.model_id = "other-model";
}
fn m_output_over(r: *schema.TkModlRequest) void {
    r.max_output_tokens = 1025;
}
fn m_output_at(r: *schema.TkModlRequest) void {
    r.max_output_tokens = 1024;
}
fn m_context_over(r: *schema.TkModlRequest) void {
    r.max_context_tokens = 4097;
}
fn m_retry_over(r: *schema.TkModlRequest) void {
    r.retry_limit = 4;
}
fn m_live(r: *schema.TkModlRequest) void {
    r.replay_mode = .live;
}
fn m_no_substitution(r: *schema.TkModlRequest) void {
    r.replay_substitution_id = 0;
}
fn m_missing_and_over(r: *schema.TkModlRequest) void {
    // Precedence: missing scope wins over every limit.
    r.budget_id = "";
    r.max_output_tokens = 99999;
}
fn m_allowlist_and_over(r: *schema.TkModlRequest) void {
    // Precedence: the allowlist is checked before the output limit.
    r.model_id = "other-model";
    r.max_output_tokens = 99999;
}

fn c_budget_tight(c: *schema.TkModlConfig) void {
    // Output limit off; the per-run budget (512) is below the request's 512+1? no:
    // request is 512, budget 511 -> deny_budget_exhausted.
    c.hard_max_output_tokens = 0;
    c.per_run_token_budget = 511;
}
fn c_empty_allowlist(c: *schema.TkModlConfig) void {
    c.allowed_model_id_count = 0;
}
fn c_zero_limits(c: *schema.TkModlConfig) void {
    c.hard_max_output_tokens = 0;
    c.hard_max_context_tokens = 0;
    c.hard_max_retry_count = 0;
    c.per_run_token_budget = 0;
}

const cases = [_]Case{
    .{ .name = "allow_replay baseline", .mutate = noMutate },
    .{ .name = "missing model_id", .mutate = m_model },
    .{ .name = "missing budget_id", .mutate = m_budget },
    .{ .name = "missing policy_version", .mutate = m_policy },
    .{ .name = "missing capability_envelope_id", .mutate = m_envelope },
    .{ .name = "missing capability", .mutate = m_capability },
    .{ .name = "missing actor_role", .mutate = m_role },
    .{ .name = "missing workflow", .mutate = m_workflow },
    .{ .name = "model not allowed", .mutate = m_model_other },
    .{ .name = "output limit exceeded", .mutate = m_output_over },
    .{ .name = "output limit equality allowed", .mutate = m_output_at },
    .{ .name = "context limit exceeded", .mutate = m_context_over },
    .{ .name = "retry limit exceeded", .mutate = m_retry_over },
    .{ .name = "live request with provider disabled", .mutate = m_live },
    .{ .name = "replay without substitution id", .mutate = m_no_substitution },
    .{ .name = "missing scope outranks limits", .mutate = m_missing_and_over },
    .{ .name = "allowlist outranks output limit", .mutate = m_allowlist_and_over },
    .{ .name = "per-run budget exhausted", .mutate = noMutate, .config = c_budget_tight },
    .{ .name = "empty allowlist means no restriction", .mutate = m_model_other, .config = c_empty_allowlist },
    .{ .name = "zero limits mean no enforcement", .mutate = m_output_over, .config = c_zero_limits },
};

test "C tkmodl governance matches validator.zig for every branch and precedence" {
    for (cases) |case| {
        var cfg = baseConfig();
        case.config(&cfg);
        var req = baseRequest();
        case.mutate(&req);

        const expected = validator.validateTkModlRequest(cfg, req);

        const wire_cfg = try toWireConfig(cfg);
        const wire_req = try toWire(req);
        var scope_dim: [32]u8 = undefined;
        const got = tkmodl.validate(&wire_cfg, &wire_req, &scope_dim);

        std.testing.expectEqual(wireTag(expected), got) catch |err| {
            std.debug.print("parity mismatch in case \"{s}\"\n", .{case.name});
            return err;
        };
        switch (expected) {
            .deny_missing_scope => |dim| {
                try std.testing.expectEqualStrings(dim, std.mem.sliceTo(&scope_dim, 0));
            },
            else => try std.testing.expectEqual(@as(u8, 0), scope_dim[0]),
        }
    }
}
