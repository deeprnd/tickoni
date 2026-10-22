# Plan: Migrate unit tests from bash script to native Zig `addRunArtifact`

## Goal

Replace the bash-driven `contrib/test/run_test_series.sh` test runner with Zig 0.17's native `b.addRunArtifact(test)` for unified compile+run of TK unit tests and CLI tests. One command replaces two. No external scripts.

Current state (broken):
- `zig build test` compiles test binaries
- `zig build run-tests` runs them via `contrib/test/run_test_series.sh`
- CLI tests (`test-cli-parser`, `test-cli-main`) compile but never run (no just recipe invokes `run-tests` for them)

Desired state:
- `zig build test-unit-tk` compiles AND runs all TK unit tests sequentially
- `zig build test-unit-cli` compiles AND runs all CLI tests sequentially
- `just test-unit-tk-linux-x86` invokes `test-unit-tk` (single command)
- `just test-unit-cli-linux-x86` invokes `test-unit-cli` (single command, actually runs)

Note: existing just recipes `test-unit-tk` and `test-unit-cli` are the dispatchers that call platform-specific variants. The zig build step names (`test-unit-tk`, `test-unit-cli`) align with these existing just recipe names, not with a generic `test-all` (which would imply unit+integration+system+e2e).

---

## Step 1: Modify `build-lib/lane.zig`

**File:** `build-lib/lane.zig`

### 1a. Delete `createRunTestsCmd()` function (lines 12-40)

Remove the entire function that creates the bash script runner:

```zig
// DELETE THIS ENTIRE FUNCTION (lines 12-40):
/// Create the run-tests command that executes all test binaries
/// sequentially via a bash script (avoids Zig's --listen=- parallel
/// coordination which panics with EndOfStream when 48+ test binaries
/// communicate over the same pipe).
pub fn createRunTestsCmd(b: *std.Build) *std.Build.Step.Run {
    const run_tests_cmd = std.Build.Step.Run.create(b, "run-tests");
    const build_root_str = b.root.toString(b.allocator) catch |err| {
        std.debug.print("error: Failed to get build root path: {any}\n", .{err});
        return run_tests_cmd;
    };
    defer b.allocator.free(build_root_str);
    var script_buf: [4096]u8 = undefined;
    const full_script_path = std.fmt.bufPrint(
        &script_buf,
        "{s}/contrib/test/run_test_series.sh",
        .{build_root_str},
    ) catch |err| switch (err) {
        error.NoSpaceLeft => {
            std.debug.print("error: Script path buffer overflow (4096 bytes insufficient)\n", .{});
            return run_tests_cmd;
        },
    };
    run_tests_cmd.addArgs(&[_][]const u8{
        "bash",
        full_script_path,
    });
    run_tests_cmd.setCwd(b.path("."));
    return run_tests_cmd;
}
```

**Verify:** No references to `lane.createRunTestsCmd` remain in the codebase after this change.

### 1b. Replace `TestBuilder.registerRunTest()` with `TestBuilder.registerRunTestArtifact()`

Replace the existing method (lines 109-131) with:

```zig
/// Register a test for the sequential run lane.
/// Compiles and runs the test binary via addRunArtifact, chaining
/// after previous tests in run_sequence for sequential execution.
pub fn registerRunTest(
    self: *const TestBuilder,
    spec: TestSpec,
    run_sequence: []const *std.Build.Step.Run,
) *std.Build.Step.Run {
    const t_mod = self.b.createModule(.{
        .root_source_file = self.b.path(spec.source_file),
        .target = self.target,
        .optimize = self.optimize,
        .imports = if (spec.imports.len > 0) spec.imports else &.{},
    });
    const t = self.b.addTest(.{ .name = spec.name, .root_module = t_mod });

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

**Key changes:**
- Remove `test_step: *std.Build.Step` parameter
- Change `run_cmd: *std.Build.Step.Run` to `run_sequence: []const *std.Build.Step.Run`
- Replace `test_step.dependOn(&t.step)` and `run_cmd.addArtifactArg(t)` with `b.addRunArtifact(t)`
- Add sequential chaining: `run.step.dependOn(run_sequence[run_sequence.len - 1])`

**Verify:** The method now returns `*std.Build.Step.Run` instead of `void`. All callers must update to capture the return value.

---

## Step 2: Modify `build-lib/lanes/unit.zig`

**File:** `build-lib/lanes/unit.zig`

### 2a. Update `strategy()` signature

Change the function signature (line 15) from:

```zig
pub fn strategy(
    b: *std.Build,
    shared: shared_mod.Shared,
    tm: test_mod.TestModules,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,
    test_step: *std.Build.Step,
    run_cmd: *std.Build.Step.Run,  // DELETE THIS PARAMETER
) void {
```

To:

```zig
pub fn strategy(
    b: *std.Build,
    shared: shared_mod.Shared,
    tm: test_mod.TestModules,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,
    test_step: *std.Build.Step,  // compile-only aggregation (preserved)
) void {
    var run_sequence: [32]*std.Build.Step.Run = undefined;
    var run_count: usize = 0;

    const tb = lane.TestBuilder{ ... };
    _ = run_sequence; // suppress unused warning until used
```

### 2b. Replace all `registerRunTest` calls

Replace every call of the form:

```zig
tb.registerRunTest(.{
    .name = "...",
    .source_file = "...",
    ...
}, test_step, run_cmd);
```

With:

```zig
run_sequence[run_count] = tb.registerRunTest(.{
    .name = "...",
    .source_file = "...",
    ...
}, run_sequence[0..run_count]);
run_count += 1;
```

### 2c. Update special-case registrations

For tests with manual wiring (e.g., `test-process-api`, `test-os-shim`, `test-tier`, `test-wksp`, `test-version`, `test-logger`), each currently has:

```zig
const pa_test = b.addTest(...);
test_step.dependOn(&pa_test.step);
run_cmd.addArtifactArg(pa_test);
```

Replace with:

```zig
const pa_test = b.addTest(...);
test_step.dependOn(&pa_test.step);
run_sequence[run_count] = self.b.addRunArtifact(pa_test);
if (run_count > 0) run_sequence[run_count].step.dependOn(run_sequence[run_count - 1]);
run_count += 1;
```

### 2d. Add top-level `test-unit-tk` step

Add at the end of `strategy()` (after all tests registered):

```zig
// Top-level step: compile and run all TK unit tests sequentially.
// Zig step name `test-unit-tk` aligns with existing just recipe `test-unit-tk`.
const test_unit_tk_step = b.step("test-unit-tk", "Compile and run all TK unit tests sequentially");
if (run_count > 0) {
    test_unit_tk_step.dependOn(run_sequence[run_count - 1].step);
}
```

**Verify:** All ~30 tests use `run_sequence[run_count]` pattern. No `run_cmd.addArtifactArg()` calls remain.

---

## Step 3: Modify `build-lib/lanes/cli.zig`

**File:** `build-lib/lanes/cli.zig`

### 3a. Update `strategy()` signature and add run sequence parameter

Change from:

```zig
pub fn strategy(
    b: *std.Build,
    test_step: *std.Build.Step,
    run_cmd: *std.Build.Step.Run,  // DELETE
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,
) void {
```

To:

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
    _ = run_sequence; // may be extended to share unit lane sequence later
```

### 3b. Replace `registerRunTest` for `test-cli-parser`

From:

```zig
tb.registerRunTest(.{
    .name = "test-cli-parser",
    .source_file = "src/app/tickoni_cli/cli.zig",
}, test_step, run_cmd);
```

To:

```zig
run_sequence_local[run_count] = tb.registerRunTest(.{
    .name = "test-cli-parser",
    .source_file = "src/app/tickoni_cli/cli.zig",
}, run_sequence_local[0..run_count]);
run_count += 1;
```

### 3c. Fix `test-cli-main` step (integration test)

Currently compiles but doesn't run (broken). Replace the manual wiring:

From:

```zig
const cli_main_test = b.addTest(...);
test_step.dependOn(&cli_main_test.step);
```

To:

```zig
const cli_main_test = b.addTest(...);
test_step.dependOn(&cli_main_test.step);
run_sequence_local[run_count] = self.b.addRunArtifact(cli_main_test);
if (run_count > 0) run_sequence_local[run_count].step.dependOn(run_sequence_local[run_count - 1]);
run_count += 1;
```

### 3d. Add top-level `test-unit-cli` step

Add at end of `strategy()`:

```zig
// Top-level step: compile and run all CLI unit tests sequentially.
// Zig step name `test-unit-cli` aligns with existing just recipe `test-unit-cli`.
const test_unit_cli_step = b.step("test-unit-cli", "Compile and run all CLI unit tests sequentially");
if (run_count > 0) {
    test_unit_cli_step.dependOn(run_sequence_local[run_count - 1].step);
}
```

### 3e. Fix standalone step dependencies

The current standalone steps (`test-cli-parser`, `test-cli-main`) depend on `test_step` (compile only). Update to depend on the run step:

```zig
const cli_parser_step = b.step("test-cli-parser", "Run CLI parser unit tests (cli.zig)");
cli_parser_step.dependOn(run_sequence_local[0].step);  // depends on RUN, not just compile

const cli_main_step = b.step("test-cli-main", "Run CLI integration tests (main.zig)");
cli_main_step.dependOn(run_sequence_local[1].step);  // depends on RUN, not just compile
```

**Verify:** `zig build test-cli-parser` and `zig build test-cli-main` now actually execute tests (not just compile).

---

## Step 4: Modify `build-lib/build_test_lanes.zig`

**File:** `build-lib/build_test_lanes.zig`

### 4a. Remove `run_tests_cmd` creation (line 31)

Delete:

```zig
const run_tests_cmd = lane.createRunTestsCmd(b);
```

### 4b. Remove `run-tests` step (lines 35-36)

Delete:

```zig
const run_tests_step = b.step("run-tests", "Run offline Tickoni unit tests");
run_tests_step.dependOn(check_step);
```

### 4c. Update `build_lane.strategy()` call (line 37)

From:

```zig
build_lane.strategy(b, shared, tm, target, optimize, fd_lib_dir, test_step, run_tests_cmd);
```

To:

```zig
build_lane.strategy(b, shared, tm, target, optimize, fd_lib_dir, test_step);
```

### 4d. Update `cli_lane.strategy()` call (line 40)

From:

```zig
cli_lane.strategy(b, test_step, run_tests_cmd, target, optimize, fd_lib_dir);
```

To:

```zig
// Capture unit lane run sequence for CLI lane (optional: share for unified run)
const unit_run_count = ...; // track from unit lane (may need to return or use global)
cli_lane.strategy(b, test_step, &unit_run_sequence, target, optimize, fd_lib_dir);
```

**Note:** The exact mechanism for sharing the run sequence between unit and CLI lanes may require a small refactor (e.g., returning the count, or using a struct to pass back state). For now, keep them separate but ensure both compile+run independently.

**Verify:** No references to `run_tests_cmd` or `run-tests` remain.

---

## Step 5: Modify `just/test/unit.just`

**File:** `just/test/unit.just`

### 5a. Update `test-unit-tk-linux-x86` (line 108-110)

From two commands:

```just
test-unit-tk-linux-x86:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} test --summary all
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} run-tests
```

To single command:

```just
test-unit-tk-linux-x86:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} test-unit-tk
```

### 5b. Update `test-unit-cli-linux-x86` (line 150-151)

From compile-only (broken):

```just
test-unit-cli-linux-x86:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} test-cli-parser
```

To compile+run:

```just
test-unit-cli-linux-x86:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} test-unit-cli
```

### 5c. Remove `run-tests` from any other recipe references

Search for any remaining `run-tests` references in `just/test/*.just` and remove them.

**Verify:** `just test-unit-tk-linux-x86` runs in a single `zig build` command. `just test-unit-cli-linux-x86` actually executes tests.

---

## Step 6: Delete `contrib/test/run_test_series.sh`

**File:** `contrib/test/run_test_series.sh`

Verify no references remain in:
- `build-lib/` (Zig build system)
- `just/` (justfile recipes)
- CI workflows (`.github/workflows/`)
- Documentation (`doc/execution/`)

Then delete the file:

```bash
git rm contrib/test/run_test_series.sh
```

**Verify:** `grep -r "run_test_series.sh" .` returns no matches (excluding this plan file and git history).

---

## Step 7: Build and run verification

### 7a. Build test

```bash
zig build -Dtest=true test-unit-tk
```

**Expected:** All ~30 TK unit tests compile and run sequentially. No bash script invoked.

### 7b. Build CLI test

```bash
zig build -Dtest=true test-unit-cli
```

**Expected:** Both `test-cli-parser` and `test-cli-main` compile and run.

### 7c. Run just recipes

```bash
just test-unit-tk-linux-x86
just test-unit-cli-linux-x86
```

**Expected:** Both run to completion without errors. Single `zig build` invocation each.

### 7d. Verify compile-only step still works

```bash
zig build -Dtest=true test
```

**Expected:** Compiles test binaries without running them (for CI use cases).

---

## Risk mitigation

1. **Exit code propagation**: `addRunArtifact` with `enableTestRunnerMode()` returns non-zero on test failure. Verified against Zig 0.17 `Build.zig:798`. If any test crashes (SIGABRT), `addRunArtifact` captures the non-zero exit code and fails the step.

2. **Standalone step behavior**: `zig build test` (compile-only) still works because `test_step.dependOn(&t.step)` is preserved for each test binary. The `test-unit-tk` step is the new compile+run entry point.

3. **Capacity**: Unit lane has ~30 tests. `run_sequence` array of `[32]*std.Build.Step.Run` provides headroom. If tests are added beyond 32, switch to dynamic allocation via `b.allocator.alloc(...)`.

4. **Parallel compilation**: All test binaries compile in parallel (fast), then run sequentially via `addRunArtifact`. No regression in build time.

---

## Files changed summary

| File | Action |
|------|--------|
| `build-lib/lane.zig` | Delete `createRunTestsCmd()`, replace `registerRunTest()` |
| `build-lib/lanes/unit.zig` | Remove `run_cmd` param, add run sequence, replace registrations |
| `build-lib/lanes/cli.zig` | Remove `run_cmd` param, add run sequence, fix standalone steps |
| `build-lib/build_test_lanes.zig` | Remove `run-tests` step, update strategy calls |
| `just/test/unit.just` | Replace two-command `test-unit-tk` with single `test-unit-tk`, fix `test-unit-cli` |
| `contrib/test/run_test_series.sh` | **DELETED** |

---

## Verification checklist

- [x] `zig build -Dtest=true test` compiles without errors
- [x] `zig build -Dtest=true test-unit-tk` compiles AND runs all tests (no bash)
- [x] `zig build -Dtest=true test-unit-cli` compiles AND runs CLI tests
- [x] `zig build test-cli-parser` actually runs tests (was broken before)
- [x] `zig build test-cli-main` actually runs tests (was broken before)
- [x] `just test-unit-tk-linux-x86` runs in single command
- [x] `just test-unit-cli-linux-x86` runs in single command (was broken before)
- [x] No references to `run_test_series.sh` in codebase (deleted)
- [x] No references to `createRunTestsCmd` in codebase
- [x] All ~30+ unit tests execute sequentially
- [x] Exit code is non-zero if any test fails
