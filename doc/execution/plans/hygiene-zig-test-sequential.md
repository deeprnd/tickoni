# Plan: Unify unit tests (TK + CLI) to compile + run via `b.addRunArtifact`

## Problem

Unit tests (TK lane + CLI lane) are wired to compile and run via a bash script (`contrib/test/run_test_series.sh`) that discovers compiled binaries and runs them sequentially. This was created as a workaround, but Zig 0.17's `b.addRunArtifact(test)` natively compiles AND runs each test binary — with sequential execution, correct exit code propagation, and no shared-pipe contention (each binary is a separate process).

The current split causes broken standalone steps: `zig build test-cli-parser` and `zig build test-cli-main` compile test binaries but never run them. The bash script is the only thing that executes them, but no just recipe invokes it for CLI tests.

## Current flow (broken)

```
build_test_lanes.zig → createRunTestsCmd(b) → "run-tests" step (bash script)
                          │
unit.zig.strategy() → registerRunTest(test_step, run_cmd)
                          │         └─ addArtifactArg → bash run_test_series.sh
                          └─ test_step.dependOn(&t.step)

cli.zig.strategy() → registerRunTest(test_step, run_cmd)
                          │
               test-cli-parser step ──> depends on test_step (compile only, broken)
               test-cli-main step   ──> depends on test_step (compile only, broken)
```

`run_test_series.sh` does a `find .zig-cache/o/ -name test` and runs each binary sequentially. This reimplements what Zig already does natively.

## What Zig does natively

`b.addRunArtifact(test)` on a `.test` step:
1. Compiles the test binary (implicit dependency chain)
2. Runs it via `enableTestRunnerMode()` (passes `--listen=-` per-process, no shared pipes)
3. Returns a `Step.Run` that depends on the `Step.Compile` — sequential execution when chained

The integration lane already uses this correctly for static tests via `shims.addPlainTestRun()`.

## Changes

### 1. `build-lib/lane.zig`

- Delete `createRunTestsCmd()` function entirely (bash script no longer needed for unit/CLI tests).
- Remove `TestBuilder.registerRunTest()` method (replaced by `registerRunTestArtifact`).
- Add `TestBuilder.registerRunTestArtifact()`:

```zig
pub fn registerRunTestArtifact(
    self: *const TestBuilder,
    spec: TestSpec,
    run_sequence: []const *std.Build.Step.Run,
) *std.Build.Step.Run {
    const t_mod = self.b.createModule(.{ ... });
    const t = self.b.addTest(.{ .name = spec.name, .root_module = t_mod });

    // Apply linkage (codec, firedancer, topo_run, libc)
    if (spec.linkage.needs_codec) codec.linkTickoniCodec(self.b, t, self.fd_lib_dir);
    if (spec.linkage.needs_firedancer) firedancer.linkTickoniFiredancer(self.b, t, self.fd_lib_dir);
    if (spec.linkage.needs_topo_run) topo_run.linkTickoniTopoRun(self.b, t, self.fd_lib_dir);
    if (spec.linkage.needs_libc) t.root_module.link_libc = true;

    // addRunArtifact: compile + run in one step
    const run = self.b.addRunArtifact(t);

    // Chain: run this after the previous one (sequential execution)
    if (run_sequence.len > 0) {
        run.step.dependOn(run_sequence[run_sequence.len - 1]);
    }

    return run;
}
```

### 2. `build-lib/lanes/unit.zig`

- Remove `run_cmd` parameter from `strategy()`.
- Keep `test_step` parameter for compile-only aggregation (optional — can be removed if no other consumer).
- For each test: replace `tb.registerRunTest(..., test_step, run_cmd)` with `tb.registerRunTestArtifact(spec, &run_sequence)`.
- Accumulate all `*std.Build.Step.Run` results in a `[]*std.Build.Step.Run` array (capacity ~30).
- The last element of the array becomes the top-level `test-all` step's dependency.

```zig
pub fn strategy(
    b: *std.Build,
    shared: shared_mod.Shared,
    tm: test_mod.TestModules,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,
    test_step: *std.Build.Step,  // compile-only aggregation (optional)
) void {
    var run_sequence: [32]*std.Build.Step.Run = undefined;
    var run_count: usize = 0;

    const tb = lane.TestBuilder{ ... };

    // tile-based unit tests
    run_sequence[run_count] = tb.registerRunTestArtifact(.{
        .name = "test-topology",
        .source_file = "src/tickoni/runtime/topology.zig",
    }, run_sequence[0..run_count]);
    run_count += 1;

    // ... more tests follow the same pattern ...

    // Top-level step
    const test_all_step = b.step("test-all", "Compile and run all TK unit tests sequentially");
    if (run_count > 0) {
        test_all_step.dependOn(run_sequence[run_count - 1].step);
    }
}
```

### 3. `build-lib/lanes/cli.zig`

- Remove `run_cmd` parameter from `strategy()`.
- Replace `tb.registerRunTest(..., test_step, run_cmd)` with `tb.registerRunTestArtifact(spec, &run_sequence)`.
- For `test-cli-main` (integration test): keep the `test_step.dependOn()` for compile-only aggregation, but wire the `addRunArtifact` into the run sequence.
- Top-level steps (`test-cli-parser`, `test-cli-main`) now depend on the **run step**, not just the compile step.

```zig
pub fn strategy(
    b: *std.Build,
    test_step: *std.Build.Step,
    run_sequence: []const *std.Build.Step.Run,  // shared with unit lane
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,
) void {
    var run_sequence_local: [2]*std.Build.Step.Run = undefined;
    var run_count: usize = 0;
    var shared_seq: [2]*std.Build.Step.Run = undefined;

    // test-cli-parser — unit tests
    run_sequence_local[run_count] = tb.registerRunTestArtifact(.{
        .name = "test-cli-parser",
        .source_file = "src/app/tickoni_cli/cli.zig",
    }, shared_seq[0..run_count]);
    run_count += 1;

    // test-cli-main — integration tests (spawn tickoni binary)
    // Already has manual addTest + linkage wiring — replace with registerRunTestArtifact
    // Note: depends on exe_install for the tickoni binary
    run_sequence_local[run_count] = tb.registerRunTestArtifact(.{
        .name = "test-cli-main",
        .source_file = "src/app/tickoni_cli/main.zig",
    }, shared_seq[0..run_count]);
    run_sequence_local[run_count].step.dependOn(&exe_install.step);
    run_count += 1;

    // Top-level step for standalone invocation
    const cli_test_all_step = b.step("test-cli-all", "Compile and run all CLI tests sequentially");
    if (run_count > 0) {
        cli_test_all_step.dependOn(run_sequence_local[run_count - 1].step);
    }
}
```

### 4. `build-lib/build_test_lanes.zig`

- Remove `run_tests_cmd = lane.createRunTestsCmd(b)` call.
- Remove the `run-tests` step (`b.step("run-tests", ...)`) — no longer needed.
- Update `build_lane.strategy()` call: remove `run_cmd` parameter.
- Update `cli_lane.strategy()` call: remove `run_cmd` parameter.
- Keep `test_step` as compile-only aggregation (for CI `zig build test`).
- Wire unit lane run sequence into CLI lane so all tests run in one pipeline:

```zig
// Unit tests — no run_cmd parameter
build_lane.strategy(b, shared, tm, target, optimize, fd_lib_dir, test_step);

// CLI lane — shares the unit run sequence
cli_lane.strategy(b, test_step, &unit_run_sequence, target, optimize, fd_lib_dir);
```

### 5. `just/test/unit.just`

- `test-unit-tk-linux-x86`: replace two-command sequence with single `zig build -Dtest=true test-all`.
- `test-unit-cli-linux-x86`: replace single command with `zig build -Dtest=true test-cli-all` (now actually runs).
- Remove `run-tests` from any recipe references.

## Integration and system tests (unchanged)

- **Integration static tests** — already use `b.addRunArtifact()` natively via `shims.addPlainTestRun()`. No change.
- **Integration process-mode tests** — use `shims.addPlainTestRun()` because they depend on the supervisor binary being installed first. Separate problem, not in scope.
- **System tests** — use `shims.addPlainTestRun()`. Not in scope for this change.

## Verification

```bash
# Compile all unit test binaries (existing step, unchanged)
zig build -Dtest=true test

# Run all unit tests (NEW — replaces old two-command pattern)
zig build -Dtest=true test-all

# Run CLI tests (NEW — actually runs now, not just compiles)
zig build -Dtest-all test-cli-all

# Existing just recipes (now unified, single command)
just test-unit-tk-linux-x86
just test-unit-cli-linux-x86
```

## Files changed

- `build-lib/lanes/unit.zig` — replace `registerRunTest` with `registerRunTestArtifact`
- `build-lib/lanes/cli.zig` — replace `registerRunTest` with `registerRunTestArtifact`, fix standalone steps
- `build-lib/build_test_lanes.zig` — remove `run-tests` step, pass run sequence to lanes
- `build-lib/lane.zig` — delete `createRunTestsCmd`, replace `registerRunTest` with `registerRunTestArtifact`
- `just/test/unit.just` — update recipes to use `test-all` / `test-cli-all`

## Files deleted

- `contrib/test/run_test_series.sh` — no longer referenced by unit/CLI test lanes

## Files preserved (no changes)

- `scripts/test-integration-sequential.sh` (dead code, but not touched per request)

## Risks

1. **Exit code propagation**: `addRunArtifact` with `enableTestRunnerMode()` returns non-zero if any test fails. Verified against Zig 0.17 `Build.zig:798` — `enableTestRunnerMode()` sets up the server protocol correctly.
2. **Standalone step behavior**: `zig build test` (compile-only) still works because `test_step.dependOn(&t.step)` is preserved for each test binary. `zig build test-all` is the new compile+run step.
3. **Capacity**: Unit lane has ~30 tests. `run_sequence` array of `[32]*std.Build.Step.Run` provides headroom. Dynamic allocation can replace the fixed array if needed.
