const demo = @import("investment_demo");
const std = @import("std");

test "system demo live: real tkmodl, allowed, blocked, restricted, replay proof" {
    const allocator = std.testing.allocator;
    const test_env = std.process.Environ.Map{};
    const model_id = try demo.envOrDefault(allocator, &test_env, "TK_LLM_MODEL_ID", demo.default_model_id);
    defer allocator.free(model_id);
    const endpoint = try demo.envOrDefault(allocator, &test_env, "TK_LLM_ENDPOINT", demo.default_endpoint);
    defer allocator.free(endpoint);

    // Default to fixture-backed (deterministic, no llama.cpp required).
    // Set TK_LIVE_TEST=1 to force live mode for manual CI debugging.
    var live_config = demo.LiveConfig{
        .endpoint = endpoint,
        .model_id = model_id,
        .use_fixture = true,
    };
    if (std.process.getEnvVarOwned(allocator, "TK_LIVE_TEST")) |v| {
        defer allocator.free(v);
        if (std.mem.eql(u8, v, "1")) {
            live_config.use_fixture = false;
        }
    }

    try demo.runSystemSuite(allocator, std.testing.io, live_config);
}
