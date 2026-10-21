# Plan: Decouple CLI build from test lanes

## Problem

The CLI executable (`tickoni`) is built inside `if (build_tests)` in `build.zig`, gated by `-Dtest=true`, and requires the full `investment_fixture_mod` dependency graph (13+ modules) that exists only for integration tests. This couples build to test, which is wrong — the CLI binary should build unconditionally (like the supervisor), and test lanes should run against the already-installed binary.

## Current broken state

- `helpers.zig: createCliExe` signature stripped of `investment_fixture` parameter
- `build.zig:189` still calls old 6-arg `createCliExe(b, investment_fixture_mod, ...)` — will fail to compile
- `build.zig:64-192` contains dead module wiring (13+ integration modules) only to feed the old CLI call
- `build-lib/lanes/cli.zig` references `exe_install` in body but parameter still in signature

## Goal

CLI builds unconditionally via default_step (like supervisor). Test lanes run against installed binary. No build/test coupling.

## Steps

### Step 1: Remove dead `if (build_tests)` block in `build.zig`

Lines 65–192 contain 13+ integration module creations (adapter_messages, model_messages, mock_model, adapter_int, model_int, tkpoly_int, tool_int, replay_int, investment_support, investment_fixture) + stale CLI call. All of this exists only to feed `createCliExe(b, investment_fixture_mod, ...)` which is dead code — `factory.zig` already creates `investment_fixture_mod` for integration tests.

Remove lines 65–192 (module wiring + stale CLI call). Keep:
- Line 195: `test_lanes.registerTestLanes(b, ...)` — this is the correct test registration
- Line 194 comment: `// Unit + integration + system lanes`

After removal, `build.zig` will have:
```zig
// Check + fixture verification
const check_step = helpers.createCheckStep(b, target);
helpers.createVerifyFixtureStep(b, check_step);

// Unit + integration + system lanes
if (build_tests) {
    test_lanes.registerTestLanes(b, check_step, shared, tm, target, optimize, fd_lib_dir, exe, exe_install);
}
```

### Step 2: Clean up `build-lib/lanes/cli.zig`

Remove `exe_install` from function signature and parameter usage:

```zig
pub fn strategy(
    b: *std.Build,
    test_step: *std.Build.Step,
    run_cmd: *std.Build.Step.Run,
    // REMOVED: exe_install: *std.Build.Step.InstallArtifact,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,
) void
```

Body already has `exe_install` references removed (dependOn, addArtifactArg). Verify the body is clean.

### Step 3: Update `build-lib/build_test_lanes.zig` call site

Line 40: remove `exe_install` from `cli_lane.strategy(...)` call:

```zig
// Before:
cli_lane.strategy(b, test_step, run_tests_cmd, exe_install, target, optimize, fd_lib_dir);

// After:
cli_lane.strategy(b, test_step, run_tests_cmd, target, optimize, fd_lib_dir);
```

### Step 4: Verify existing justfile recipes

Already correct from prior changes:
- `just/test/unit.just` `test-unit-cli-linux-x86` runs `test-cli-parser` only
- `just/test/integration.just` `test-integration-cli-linux-x86` runs `test-cli-main`
- `test-integration-cli` routes via platform to `linux-x86`
- `test-integration-all` includes `test-integration-cli`
- `test-cli-all` removed from `just/test/all.just`

No changes needed.

## Final flow

- `build-all` → `build-tk` → `zig build` → supervisor + CLI (unconditional, default_step)
- `test-unit-all` → `test-unit-cli` → `zig build -Dtest=true test-cli-parser` (unit only)
- `test-integration-all` → `test-integration-cli` → `zig build -Dtest=true test-cli-main` (integration, binary already installed)

## Verification

- `zig build` compiles supervisor + CLI without errors
- `zig build -Dtest=true test-cli-parser` runs parser unit tests
- `zig build -Dtest=true test-cli-main` runs integration tests against installed binary
- `just test-unit-all && just test-integration-all` passes end to end
