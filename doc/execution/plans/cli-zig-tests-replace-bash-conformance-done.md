# Plan: Replace CLI bash conformance tests with Zig unit + integration tests in a lane

## Problem

`contrib/test/run_cli_conformance_tests.sh` is the sole test for the `tickoni` CLI binary. It:
1. Runs `zig build` to compile the binary
2. Executes `tickoni --version`, `tickoni doctor --plain`, `tickoni doctor --json`, bare invocation, and `tickoni-supervisor --version`
3. Validates output via embedded Python heredocs

The tests live in bash — they're not in a Zig test lane, so they don't participate in `zig build test` and can't be run individually with `zig build test-cli-parser`.

The plan doc `hygiene-migrate-demo-tests-from-bash-to-pytest.md` is stale (wrong filename, never executed).

## Design decisions

1. **Where tests live**: In the same files under `src/app/tickoni_cli/` — `cli.zig` gets unit tests, `main.zig` gets integration tests. This matches the repo convention (`doctor/checks.zig`, `doctor/output.zig` both have inline `test` blocks).

2. **Where the lane is**: `build-lib/lanes/cli.zig` — a new lane that registers `test-cli-parser` (unit) and `test-cli-main` (integration). The lane is thin: it just registers two test binaries. No cross-module linkage needed — the CLI module is self-contained.

3. **What gets removed**: `contrib/test/run_cli_conformance_tests.sh` is deleted. The `test-cli-tk` recipe in `just/test/cli.just` is removed (the lane handles everything).

4. **What stays out of scope**: Supervisor tests (`tickoni-supervisor --version`). Those are infrastructure-level tests for the supervisor tile, not the CLI. If needed later, they belong in a separate `test-supervisor` lane or the existing integration lane.

## Tests to write

### Unit tests — `cli.zig`

The CLI parser (`Parser` struct + `parse()`) is pure logic with no I/O, no system calls, no networking. All tests are deterministic.

| # | Test name | What it tests |
|---|---|---|
| 1 | `--help flag` | `-h` and `--help` set `help = true`, rest is zeroed |
| 2 | `-v flag` | `-v` sets `version = 1` |
| 3 | `--version flag` | `--version` sets `version = 1` |
| 4 | `unknown command` | Unrecognized positional command does NOT crash parser (main.zig handles it) |
| 5 | `bare invocation` | No args → `help = false`, `version = 0`, `positionals.len == 0` |
| 6 | `version command` | `tickoni version` → `version = 1`, `positionals = ["version"]` |
| 7 | `doctor command --plain` | `tickoni doctor --plain` → `help = false`, `version = 0`, `positionals = ["doctor"]`, `flags.plain = true` |
| 8 | `doctor command --json` | `tickoni doctor --json` → same as above, `flags.json = true` |
| 9 | `--thesis value` | `tickoni doctor --thesis=macro` → `values.thesis = "macro"` |
| 10 | `--thesis value` (space-separated) | `tickoni doctor --thesis macro` → same as above |
| 11 | `--endpoint value` | `tickoni --endpoint=http://local` → `values.endpoint = "http://local"` |
| 12 | `--model value` | `tickoni --model=gemma4` → `values.model = "gemma4"` |
| 13 | `--manifest value` | `tickoni --manifest=/path/to/manifest` → `values.manifest = "/path/to/manifest"` |
| 14 | `deinit frees thesis` | Create parser with thesis, call `deinit()` — no leak (checked via allocator leak detection in test harness) |
| 15 | `short -h with other args` | `tickoni -h --version doctor` → `help = true` wins, short circuit |
| 16 | `double dash separator` | `tickoni -- version doctor` → `positionals = ["version", "doctor"]` |
| 17 | `empty string values` | `--thesis=` → `values.thesis` is empty (the parser accepts it) |

### Integration tests — `main.zig`

These test the actual binary. They need `zig build` first, then subprocess invocations. The existing bash script pattern is fine here — just replace `python3 -` assertions with Zig `std.testing` checks.

| # | Test name | What it tests |
|---|---|---|
| 1 | `version output format` | Run `tickoni --version`, assert `Tickoni ` prefix and all needle strings (Build ID, Git, OS, Runtime Tier, etc.) |
| 2 | `doctor --plain output` | Run `tickoni doctor --plain`, assert `tickoni doctor` header and `Platform tier:` |
| 3 | `doctor --json output` | Run `tickoni doctor --json`, parse JSON, assert `platform_tier`, `result`, `checks` fields |
| 4 | `bare invocation fail-closed` | Run `tickoni` with no args, assert it shows usage/help (not a crash or panic) |
| 5 | `unknown command error` | Run `tickoni foobar`, assert error message contains "unknown command" and non-zero exit code |

**Note**: Tests 2-3 and 5 are the same assertions the bash script makes, just moved into Zig. Test 1 overlaps with `version.zig` tests but tests the CLI transport layer (what the binary prints, not the format function).

### What we DON'T test

- **Doctor check logic**: Already covered by `doctor/checks.zig` and `doctor/output.zig` unit tests (they run in the unit lane).
- **Supervisor binary**: Out of scope for CLI tests.
- **Version info init/format**: Covered by `version.zig` unit tests.

## Files touched

| File | Action |
|---|---|
| `src/app/tickoni_cli/cli.zig` | Add ~100 lines of unit tests at bottom |
| `src/app/tickoni_cli/main.zig` | Add ~80 lines of integration tests at bottom (subprocess-based) |
| `build-lib/lanes/cli.zig` | **Create** — new lane registering 2 test binaries |
| `build-lib/build_test_lanes.zig` | Edit — import and register cli lane |
| `just/test/cli.just` | Delete (or remove `test-cli-tk` recipe and all aliases) |
| `contrib/test/run_cli_conformance_tests.sh` | **Delete** |
| `doc/execution/plans/hygiene-migrate-demo-tests-from-bash-to-pytest.md` | Delete (stale, superseded) |

## Implementation order

1. **Add unit tests to `cli.zig`** — pure logic, no dependencies, can run standalone.
2. **Add integration tests to `main.zig`** — need the binary, but easy to write.
3. **Create `build-lib/lanes/cli.zig`** — thin lane, just registers the two test binaries.
4. **Wire lane in `build_test_lanes.zig`** — add import + registration call.
5. **Delete `contrib/test/run_cli_conformance_tests.sh`** — verify nothing else references it.
6. **Delete/update `just/test/cli.just`** — remove `test-cli-tk` recipe.
7. **Delete stale plan doc**.
8. **Verify** — run `zig build test-cli-parser` and `zig build test-cli-main`, confirm they pass.

## Verification

After implementation:
- `zig build test-cli-parser` — runs all unit tests on `cli.zig`
- `zig build test-cli-main` — runs integration tests (requires built binary)
- `zig build test` — runs all lanes including CLI
- No references to `run_cli_conformance_tests.sh` remain in the repo
- No references to `test-cli-tk` remain in justfile or CI
