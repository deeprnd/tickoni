const demo = @import("investment_demo");
const std = @import("std");

test "system demo live: real tkmodl, allowed, blocked, restricted, replay proof" {
    const allocator = std.testing.allocator;

    // Env vars (TK_LLM_MODEL_ID, TK_LLM_ENDPOINT, TK_LIVE_TEST) are only
    // available via init.environ_map in main(). Tests use defaults — env
    // vars are for manual CI debugging only.
    const live_config = demo.LiveConfig{
        .endpoint = demo.default_endpoint,
        .model_id = demo.default_model_id,
        .use_fixture = true,
    };

    try demo.runSystemSuite(allocator, std.testing.io, live_config);
}
