const demo = @import("investment_demo");
const std = @import("std");
const builtin = @import("builtin");

/// Helper to read an env var from the global environment.
/// On Windows, std.c.environ is not available (it's POSIX-only), so we
/// return null and rely on the caller's default values.
fn getEnv(name: []const u8) ?[]const u8 {
    if (builtin.os.tag == .windows) return null;
    const env = std.c.environ;
    var count: usize = 0;
    while (env[count] != null) : (count += 1) {}
    for (env[0..count]) |entry| {
        const kv = entry orelse continue;
        const span = std.mem.span(kv);
        if (std.mem.startsWith(u8, span, name) and span.len > name.len and span[name.len] == '=') {
            return span[name.len + 1 ..];
        }
    }
    return null;
}

test "system demo live: real tkmodl, allowed, blocked, restricted, replay proof" {
    const allocator = std.testing.allocator;
    const model_id = (getEnv("TK_LLM_MODEL_ID") orelse demo.default_model_id);
    const endpoint = (getEnv("TK_LLM_ENDPOINT") orelse demo.default_endpoint);

    // Default to fixture-backed (deterministic, no llama.cpp required).
    // Set TK_LIVE_TEST=1 to force live mode for manual CI debugging.
    var live_config = demo.LiveConfig{
        .endpoint = endpoint,
        .model_id = model_id,
        .use_fixture = true,
    };
    if (getEnv("TK_LIVE_TEST")) |v| {
        if (std.mem.eql(u8, v, "1")) {
            live_config.use_fixture = false;
        }
    }

    try demo.runSystemSuite(allocator, std.testing.io, live_config);
}
