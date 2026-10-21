# Plan: Replace CLI bash conformance tests with Zig unit + integration tests

## Overview

Replace `contrib/test/run_cli_conformance_tests.sh` with Zig unit tests in `src/app/tickoni_cli/cli.zig` and integration tests in `src/app/tickoni_cli/main.zig`, registered via a new `build-lib/lanes/cli.zig` lane.

## Implementation Steps

### Phase 1: Unit tests — `src/app/tickoni_cli/cli.zig`

1. Append a `test` block to `cli.zig` (already has the `parse()` function and `Parser` struct).
2. `test "parse --help flag"`: Create a mock `std.process.Init` with args `["tickoni", "--help"]`. Call `cli.parse()`. Assert `result.help == true`, `result.version == 0`, `result.positionals.len == 0`.
3. `test "parse -h flag"`: Same with args `["tickoni", "-h"]`. Assert `result.help == true`.
4. `test "parse -v flag"`: Args `["tickoni", "-v"]`. Assert `result.version == 1`, `result.help == false`.
5. `test "parse --version flag"`: Args `["tickoni", "--version"]`. Assert `result.version == 1`.
6. `test "parse unknown command"`: Args `["tickoni", "foobar"]`. Assert no panic, `result.positionals.len == 1`, `result.positionals[0] == "foobar"`.
7. `test "parse bare invocation"`: Args `["tickoni"]` only. Assert `result.help == false`, `result.version == 0`, `result.positionals.len == 0`.
8. `test "parse version command"`: Args `["tickoni", "version"]`. Assert `result.positionals.len == 1`, `result.positionals[0] == "version"`.
9. `test "parse doctor --plain"`: Args `["tickoni", "doctor", "--plain"]`. Assert `result.positionals[0] == "doctor"`, `result.flags.plain == true`, `result.flags.json == false`.
10. `test "parse doctor --json"`: Args `["tickoni", "doctor", "--json"]`. Assert `result.flags.json == true`, `result.flags.plain == false`.
11. `test "parse --thesis=macro (equals)"`: Args `["tickoni", "--thesis=macro"]`. Assert `result.values.thesis != null` and deref equals `"macro"`.
12. `test "parse --thesis macro (space)"`: Args `["tickoni", "--thesis", "macro"]`. Same assertion.
13. `test "parse --endpoint=value"`: Args `["tickoni", "--endpoint=http://local"]`. Assert `result.values.endpoint` equals `"http://local"`.
14. `test "parse --model=value"`: Args `["tickoni", "--model=gemma4"]`. Assert `result.values.model` equals `"gemma4"`.
15. `test "parse --manifest=value"`: Args `["tickoni", "--manifest=/path/to/manifest"]`. Assert `result.values.manifest` equals `"/path/to/manifest"`.
16. `test "parse deinit frees thesis"`: Use `std.testing.allocator` (leak-detecting). Create parser with `--thesis=test`, call `deinit()`. Verify no leak on deinit.
17. `test "parse short -h wins"`: Args `["tickoni", "-h", "--version", "doctor"]`. Assert `result.help == true`, `result.version == 0` (short-circuits).
18. `test "parse double dash separator"`: Args `["tickoni", "--", "version", "doctor"]`. Assert `result.positionals.len == 2`, positionals are `["version", "doctor"]`.
19. `test "parse empty string values"`: Args `["tickoni", "--thesis="]`. Assert `result.values.thesis` is null (empty string not stored).
20. Helper: create a `parseArgs` helper that takes a slice of strings and constructs `std.process.Init` for testing.

### Phase 2: Integration tests — `src/app/tickoni_cli/main.zig`

21. Append a `test` block to `main.zig`.
22. `test "version output format"`: Spawn `tickoni --version` via `std.process.Child`. Assert stdout starts with `"Tickoni "`. Assert needles present: `"Build ID:"`, `"Git:"`, `"OS:"`, `"Runtime Tier:"`, `"Isolation Tier:"`, `"Policy Schema:"`, `"Replay Schema:"`, `"Manifest:"`, `"Compiler:"`.
23. `test "doctor --plain output"`: Spawn `tickoni doctor --plain`. Assert stdout contains `"tickoni doctor"` and `"Platform tier:"`.
24. `test "doctor --json output"`: Spawn `tickoni doctor --json`. Parse JSON. Assert `"platform_tier"`, `"result"`, and `"checks"` (array) fields exist.
25. `test "bare invocation fail-closed"`: Spawn `tickoni` with no args. Assert output contains `"command"`, `"usage"`, `"error"`, or `"unknown"` (case-insensitive). Process should not crash.
26. `test "unknown command error"`: Spawn `tickoni foobar`. Assert non-zero exit code. Assert stderr/stdout contains `"unknown command"`.
27. Helper: use `std.process.executableDirPathAlloc` (pattern from existing integration tests) to locate the `tickoni` binary, or use fixed path `build/zig-out/bin/tickoni`.
28. Helper: create `runBinary(args: []const []const u8)` returning `{ stdout: []u8, stderr: []u8, exit_code: i32 }`.

### Phase 3: Create lane — `build-lib/lanes/cli.zig`

29. Create file `build-lib/lanes/cli.zig`.
30. Define `strategy()` with signature:
    ```zig
    pub fn strategy(
        b: *std.Build,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        fd_lib_dir: []const u8,
        test_step: *std.Build.Step,
        run_cmd: *std.Build.Step.Run,
        exe_install: *std.Build.Step.InstallArtifact,
    ) void
    ```
31. Register `test-cli-parser`: create module from `src/app/tickoni_cli/cli.zig`, add test, wire to `test_step` + `run_cmd`. No special linkage.
32. Create top-level step `test-cli-parser` for standalone execution.
33. Build the `tickoni` executable (reuse existing `exe` if available, or create a compile step).
34. Register `test-cli-main`: create module from `src/app/tickoni_cli/main.zig` with imports: `cli`, `doctor_output` (from `src/tickoni/doctor/output.zig`), `version` (from `src/tickoni/version.zig`).
35. Wire `test-cli-main` run step to depend on `exe_install` (binary must exist).
36. Create top-level step `test-cli-main` for standalone execution.

### Phase 4: Wire lane — `build-lib/build_test_lanes.zig`

37. Add import: `const cli_lane = @import("lanes/cli.zig");`
38. In `registerTestLanes()`, call:
    ```zig
    cli_lane.strategy(b, target, optimize, fd_lib_dir, test_step, run_cmd, exe_install);
    ```

### Phase 5: Delete bash script

39. Delete `contrib/test/run_cli_conformance_tests.sh`.

### Phase 6: Delete justfile recipes

40. Delete `just/test/cli.just` (verify it's only used for test-cli-tk recipes).
41. Update `scripts/dispatch-map.json`: remove `"test-cli-tk"` entry.

### Phase 7: Update documentation references

42. Update all roadmap stories referencing `test-cli-tk`:
    - `doc/strategy/roadmap/stories/v2.10-s8.md`
    - `doc/strategy/roadmap/stories/v2.10-s12.md`
    - `doc/strategy/roadmap/stories/v2.10-s14.md`
    - `doc/strategy/roadmap/stories/v3.19-s*.md` (all)
    - `doc/strategy/roadmap/stories/v3.23-s*.md` (all)
    - `doc/strategy/roadmap/epics/v1.11.md`
    - `doc/strategy/templates/story-template.md`
43. Replace `test-cli-tk` with `test-cli-parser` / `test-cli-main` in each.
44. Update `doc/execution/testing-tickoni.md`: replace `test-cli-tk` references.
45. Update `doc/execution/quality.md`: replace `test-cli-tk` references.
46. Delete stale plan doc: `doc/execution/plans/hygiene-migrate-demo-tests-from-bash-to-pytest.md`.

### Phase 8: Verify

47. Run `zig build test-cli-parser` — all unit tests pass.
48. Run `zig build test-cli-main` — all integration tests pass.
49. Run `zig build test` — CLI lanes included.
50. Verify no references to `run_cli_conformance_tests.sh` remain in source/justfiles.
51. Verify no `test-cli-tk` references remain in `just/` or `scripts/`.

## In Scope

- Unit tests for the parser (19 tests)
- Integration tests for the binary (5 tests)
- Lane creation and wiring
- Deletion of bash script and justfile recipes
- Documentation reference updates

## Out of Scope

- `tickoni-supervisor --version` test (infrastructure-level, excluded by plan)
- CI workflow updates (not mentioned in the plan)
- Doctor check logic changes (already covered by existing unit tests)
- Any changes to `src/tickoni/` files outside test lanes (doctor, version, etc.)
