# CLI Test Separation

## Problem

- `test-unit-cli` runs integration tests (test-cli-main) alongside unit tests — mixed concerns
- `integration.zig` has a duplicate of main.zig tests with heavier imports (investment_fixture, firedancer linking)
- Step name `test-cli-main` doesn't match its purpose (it's integration, not "unit cli")
- Justfile calls `test-cli-main` but semantics are wrong
- No clean separation between unit and integration test steps

## Solution

Split the CLI lane into clearly separated unit and integration tests with explicit naming:

- `test-unit-cli-*` — unit tests (parse, doctor checks/output, parser)
- `test-integration-cli-*` — integration tests (spawn tickoni binary, assert output)

## Changes

### 1. build-lib/lanes/cli.zig — Rename and separate

Current state in cli.zig:
```
test-doctor-checks     → unit (checks.zig)
test-doctor-output     → unit (output.zig)
test-cli-parser        → unit (cli.zig)
test-cli-main          → integration (main.zig)  ← WRONG NAME
test-unit-cli step     → runs ALL 4 sequentially
test-cli-main step     → standalone (justfile uses this)
```

New state:
```
test-unit-cli-doctor-checks  → unit (checks.zig)
test-unit-cli-doctor-output  → unit (output.zig)
test-unit-cli-parser         → unit (cli.zig)
test-integration-cli-main    → integration (main.zig)  ← NEW NAME
test-unit-cli step           → runs only unit tests (3 tests)
test-integration-cli step    → runs only integration (1 test), depends on cli_exe_install
```

### 2. build-lib/lanes/integration.zig — Remove duplicate CLI tests

Remove lines 355-375 (the `cli_int_test` block that duplicates main.zig tests).
The integration lane shouldn't have a separate copy of these tests.

### 3. build-lib/build_test_lanes.zig — Update cli_lane.strategy call

Update the call to match the new parameter order (cli_exe_install is still needed for dependency).

### 4. build.zig — No changes needed

cli_exe_install is already passed through.

### 5. just/test/integration.just — Update step name

Line 40: change `test-cli-main` to `test-integration-cli`.

### 6. Verify

- `zig build -l -Dtest=true` shows clean separation
- `zig build test-unit-cli` runs only unit tests (3 tests)
- `zig build test-integration-cli` runs only integration tests (5 tests), depends on tickoni binary
- `just test-unit-cli` works
- `just test-integration-cli` works
- `just test-all` works
