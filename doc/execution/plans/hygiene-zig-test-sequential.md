# Plan: Use native `zig build test` for unit tests

## Problem

Unit tests are wired to run via a bash script (`contrib/test/run_test_series.sh`)
that discovers compiled binaries and runs them sequentially. This was created to
work around a `--listen=-` problem, but `--listen=-` is never used in this
project. Zig's default `zig build test` already runs tests sequentially and
propagates exit codes correctly.

## Current flow

```
build_test_lanes.zig → createRunTestsCmd(b) → "run-tests" step
                          │
unit.zig.strategy() → registerRunTest(test_step, run_cmd)
                          │         └─ addArtifactArg → bash run_test_series.sh
                          └─ test_step.dependOn(&t.step)
```

`run_test_series.sh` does a `find .zig-cache/o/ -name test` and runs each
binary sequentially. This reimplements what Zig already does natively.

## What Zig does natively

`b.addRunArtifact(test)` compiles the test binary AND runs it. Zig runs tests
sequentially by default. The integration lane's "static tests" already use this
correctly — see `lanes/integration.zig:84`.

## Changes

### 1. `build-lib/lanes/unit.zig`

- Remove `run_cmd` parameter from `strategy()`.
- Remove `test_step` parameter from `strategy()` (compilation happens inside
  `addRunArtifact`).
- For each test: replace the two-phase compile + bash-run with
  `b.addRunArtifact(test)` and `step.dependOn(&test_step.step)`.

### 2. `build-lib/build_test_lanes.zig`

- Remove `run_tests_cmd = lane.createRunTestsCmd(b)` call.
- Remove the `run-tests` step (no longer needed).
- Remove `run_cmd` parameter from `build_lane.strategy()` call.
- Keep the `test` step as a compile-only step (use `test_step.dependOn(&t.step)`
  instead of the old `registerRunTest`).

### 3. `build-lib/lane.zig`

- Delete `createRunTestsCmd()` function (or leave it dead — option to remove).
- Remove `run_cmd` from `TestBuilder.registerRunTest` signature and update
  callers.

### 4. `build-lib/lib/shims.zig`

- No changes needed. `addPlainTestRun()` is still used by integration/system
  process-mode tests and system lane — those have a different problem (supervisor
  binary dependency).

## Integration and system tests (unchanged)

- **Integration static tests** — already use `b.addRunArtifact()` natively. No change.
- **Integration process-mode tests** — use `shims.addPlainTestRun()` because they
  depend on the supervisor binary being installed first. Separate problem, not in
  scope.
- **System tests** — use `shims.addPlainTestRun()`. Not in scope for this change.

## Verification

```
zig build -Dtest=true test          # compiles unit test binaries
zig build -Dtest=true run-tests     # step will be removed
just test-unit-tk-linux-x86         # should run unit tests natively
```

## Files changed

- `build-lib/lanes/unit.zig`
- `build-lib/build_test_lanes.zig`
- `build-lib/lane.zig`

## Files preserved (no changes)

- `contrib/test/run_test_series.sh`
- `scripts/test-integration-sequential.sh` (dead code, but not touched per request)
