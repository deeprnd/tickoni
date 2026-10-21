const investment_fixture = @import("investment_fixture");
const std = @import("std");

test "system demo live: real tkmodl, allowed, blocked, restricted, replay proof" {
    const allocator = std.testing.allocator;

    const live_config = investment_fixture.LiveConfig{
        .endpoint = investment_fixture.default_endpoint,
        .model_id = investment_fixture.default_model_id,
        .use_fixture = true,
    };

    try investment_fixture.runSystemSuite(allocator, std.testing.io, live_config);
}
