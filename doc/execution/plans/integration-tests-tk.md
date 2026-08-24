# Integration Tests — test-integration-tk

All integration test binaries wired into `just test-integration-tk` (Zig `zig build test-integration`).

| testname | skipped | passed |
|----------|---------|--------|
| model_tile_http_test | UNSKIPPED | PASS |
| replay_integration_test | UNSKIPPED | PASS |
| decision_cards_integration_test | SKIP | FAIL |
| mock_servers_test | SKIP | FAIL |
| link_bounds_test | SKIP | FAIL |
| process_demo_parity_test | SKIP | FAIL |
| process_topology_test | SKIP | FAIL |
| process_topology_linux_test | SKIP | FAIL |
| process_pipeline_test | SKIP | FAIL |
| process_cpu_placement_test | SKIP | FAIL |
| process_cpu_placement_linux_test | SKIP | FAIL |
| test_investment_allowed_trade | SKIP | FAIL |
| test_investment_blocked_limits | SKIP | FAIL |
| test_investment_input_policy_denials | SKIP | FAIL |
| test_investment_restricted_instrument | SKIP | FAIL |

## Source

Defined in `tickoni-build/test/integration_specs.zig`, registered via
`integration_specs.registerIntegrationSpecs()`. The justfile target
`test-integration-tk` runs `zig build -Dtest=true test-integration`, which
triggers the `test-integration` step in `build.zig` (line 190).
