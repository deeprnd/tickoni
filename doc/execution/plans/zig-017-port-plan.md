# Zig 0.17 Port Plan

Target: `zig-0-17` branch, Zig 0.17.0-dev.1770+5d7cf3f34
Source of truth: `/home/vicgenin/.local/zig/zig-x86_64-linux-0.17.0-dev.1770+5d7cf3f34/lib/std/`
Validation: `just build-all`, `just test-unit-tk`, `just test-integration-tk`, `just test-system-tk`

## Background

The 0.17 port so far has addressed:
- `[_]T{0}**N` array init syntax (replaced with `std.mem.zeroes`)
- `@typeInfo(T).enum.fields` → `@typeInfo(T).enum.field_names`/`field_values`
- `@typeInfo(T).fn.args` → `@typeInfo(T).fn.param_types` indexed loop
- OOB slice indexing in `topo_build.zig`
- CLI `parse()` error union return type
- CI default Zig version bump to 0.17
- justfile 0.17 URLs and stale comments

## What Zig 0.17 Actually Changed

**`std.Io` (capital I) IS the correct API.** There is no `std.io` module.
The codebase correctly uses `std.Io` — the breaking changes are within sub-modules.

**`std.process.Init` still has `.io`, `.gpa`, `.arena`, `.minimal`.** All `init.io` usage is valid.

The actual breaking changes are in these sub-modules:

### 1. `std.Io.Writer.fixed()` — return type change
- Old: returns `Writer`
- New: may have changed return type or method signatures
- 26 uses across 11 files
- Affects: `std.Io.Writer.fixed(&buf)` → verify return type is still `Writer`

### 2. `std.Io.Dir.cwd()` — return type change
- 42 uses across 19 files
- The `Dir` type may have changed — needs verification of each call site

### 3. `std.Io.File.writeStreamingAll()` — signature change
- Old: `writeStreamingAll(file, io, bytes)` — 3 args
- Current code: `std.Io.File.writeStreamingAll(std.Io.File.stdout(), init.io, w.buffered())`
- 6 uses across 3 files (main.zig, cli.zig, main.zig)
- Needs verification of new signature

### 4. `std.Io.File.stderr()/stdout().writer()` — signature change
- Old: `File.stderr().writer(io, buffer)` — takes io and buffer
- 3+ uses in main.zig, cli.zig, main.zig
- May need signature update

### 5. `std.Io.Dir.access()` — signature change
- 4 uses across 2 files
- Old: `Dir.access(dir, io, path, options)`
- Files: `preflight.zig`, `doctor/checks.zig`

### 6. `std.Io.Dir.openFile()` — signature change
- 6 uses in `doctor/checks.zig`
- Old: `Dir.openFile(dir, io, path, options)`

### 7. `std.Io.File.readPositionalAll()` — signature change
- 4 uses in `doctor/checks.zig`
- Old: `File.readPositionalAll(file, io, buf, offset)`

### 8. `std.Io.net.IpAddress.parse/connect` — potential changes
- 4 uses across 2 files (mock servers)
- Files: `mock_openai_server.zig`, `mock_broker_market_server.zig`

### 9. `std.Io.Mutex`, `std.Io.Threaded` — potential changes
- 2 uses each across mock server files
- Files: `mock_openai_server.zig`, `mock_broker_market_server.zig`, `mock_http_support.zig`

### 10. `std.Io.Writer.Allocating` — potential changes
- 2 uses in `mock_servers.zig`, `model/backend.zig`

### 11. `init.minimal.args` → `init.minimal` change (confirmed breaking)
- `std.process.Args.iterate(init.minimal.args)` — `.args` field may be renamed
- Current file: `cli.zig:37`
- Zig 0.17 `std.process.Init.Minimal` struct may have different field names

### 12. `rest[0..eq]` optional index (current build blocker)
- `cli.zig:66`: `const eq = std.mem.indexOfScalar(u8, rest, '=')` returns `?usize`
- `rest[0..eq]` where `eq` is `?usize` fails in 0.17
- Fix: use `eq orelse rest.len` or restructure

## Fix Order

### Phase 0: Unblock Build (1 file, 1 fix)
**`src/app/tickoni_cli/cli.zig:66`**
- `rest[0..eq]` where `eq: ?usize` → use `eq orelse rest.len` or `if (eq)` pattern
- This is the ONLY current build error
- Commit after fix

### Phase 1: Core Runtime (3 files, highest impact)
**`src/app/tickoni/main.zig`** (9 `std.Io` uses, 46 `init.io` uses)
- `writeStreamingAll` calls — verify signature
- `File.stderr().writer(io, buffer)` — verify signature
- `File.stdout().writer(io, buffer)` — verify signature
- `demo_preflight.loadManifest(init.gpa, init.io, ...)` — verify
- `demo_runner.runWithBackend(init.gpa, ...)` — verify
- `doctor_checks.runAll(...)` — verify
- `sup.startPaymentPipelineProcess(init.io, ...)` — verify
- `sup.stopProcess(init.io)` — verify
- `cmdStatus(io, ...)` — verify io parameter type

**`src/app/tickoni/supervisor.zig`** (9 `std.Io` uses)
- `Dir.cwd()` calls — verify return type
- `init.io` parameter passing — verify type compatibility
- All `writeStreamingAll` calls — verify signature

**`src/app/tickoni/tile_main.zig`** (2 `std.Io` uses)
- `run(io, gpa, spec_path)` — verify io type

**`src/app/tickoni/tile_registry.zig`** (8 `std.Io` uses)
- `Dir.cwd()` calls — verify return type
- `Writer.fixed()` — verify return type

### Phase 2: Doctor & Demo (5 files, moderate impact)
**`src/tickoni/doctor/checks.zig`** (23 `std.Io` uses — MOST in codebase)
- `Dir.access()` — 4 uses
- `File.readPositionalAll()` — 4 uses
- `Dir.openFile()` — 6 uses
- `fileExists(dir: std.Io.Dir, io: Io, path)` — verify Io parameter type
- This is the file with the most I/O changes needed

**`src/tickoni/doctor/output.zig`** (8 `std.Io` uses)
- `Writer.fixed()` — verify return type
- `writeStreamingAll` — verify signature

**`src/tickoni/demo/preflight.zig`** (15 `std.Io` uses)
- `Dir.access()` — 4 uses
- `Dir` parameter usage — verify type changes
- `Writer.fixed()` — verify

**`src/tickoni/demo/manifest.zig`** (3 `std.Io` uses)
- `Dir` usage — verify type changes

**`src/tickoni/demo/runner.zig`** (4 `std.Io` uses)
- `Dir` usage — verify type changes

### Phase 3: Schema & Codec (3 files, low impact)
**`src/tickoni/codec/audit/jsonl.zig`** (3 `std.Io` uses)
- `Writer.fixed()` — verify return type

**`src/tickoni/schema/classification/classification.zig`** (2 `std.Io` uses)
- `std.Io.Dir` — verify type

**`src/tickoni/schema/consumer_money/thesis.zig`** (1 `std.Io` use)
- Minimal change, likely just `Dir` type

### Phase 4: Tiles & Backends (5 files, moderate impact)
**`src/tickoni/tiles/adapter/backend.zig`** (6 `std.Io` uses)
- Verify `std.Io` parameter types in backend functions

**`src/tickoni/tiles/model/backend.zig`** (6 `std.Io` uses)
- `Writer.Allocating()` — verify constructor/signature

**`src/tickoni/tiles/replay/capsule.zig`** (6 `std.Io` uses)
- `std.Io` parameter types — verify

**`src/tickoni/tiles/replay/mod.zig`** (6 `std.Io` uses)
- `std.Io` parameter types — verify

**`src/tickoni/tiles/payment_pipeline/process.zig`** (2 `std.Io` uses)
- `Dir` usage — verify type

### Phase 5: Test Files (13 files, verify tests pass)
**`src/tickoni/test/demo/investment/mod.zig`** (6 `std.Io` uses)
**`src/tickoni/test/fixtures/investment/fixture_denied_trade.zig`** (2 `std.Io` uses)
**`src/tickoni/test/integration/`** (3 files, 7 `std.Io` uses total)
**`src/tickoni/test/mocks/`** (5 files, 21 `std.Io` uses total)
  - `mock_openai_server.zig`: `net.IpAddress`, `Mutex`, `Server`
  - `mock_broker_market_server.zig`: `net.IpAddress`, `Mutex`, `Server`
  - `mock_http_support.zig`: `Threaded`, `Threaded.init`
  - `mock_servers.zig`: `Writer.Allocating`

**`src/tickoni/version.zig`** (4 `std.Io` uses)
- `Dir` usage — verify type

### Phase 6: Verify All Tests
1. `just build-all` — zero errors
2. `just test-unit-tk` — all pass (was 67/68 before, 1 harness flake)
3. `just test-integration-tk` — all pass
4. `just test-system-tk` — all pass

## Commit Strategy

- One commit per phase (or sub-grouping if a phase spans multiple files)
- 3-6 word messages, domain-aligned
- Example messages:
  - `fix: cli optional slice index`
  - `fix: core runtime io parameter types`
  - `fix: doctor checks io api signatures`
  - `fix: demo io api signatures`
  - `fix: tile backend io parameter types`
  - `fix: test mock server io signatures`
  - `fix: version module io types`
  - `fix: remaining io api updates`

## Risk Notes

1. **`std.Io` API is still in flux** — this is a dev build (0.17.0-dev.1770). The actual Zig 0.17.0 release may change things further.
2. **The `std.Io` type is opaque** — it's a vtable-backed interface. The actual implementation is platform-specific. Function signatures that take `std.Io` parameters need careful verification.
3. **`Dir` type may have internal changes** — `Dir.cwd()` return type may have changed.
4. **`Writer` type changes** — `Writer.fixed()` return type may have changed, affecting chained calls like `writeAll()`.
5. **No `std.io` module** — don't search for lowercase `std.io` as a replacement for `std.Io`.

## Verification Steps After Each Phase

After each phase commit:
1. Run `just build-all` — confirm zero errors
2. Run `zig build check` — confirm clean compilation
3. If build passes, run relevant test suites

## Files Summary

| Phase | Files | `std.Io` Uses | Risk |
|-------|-------|---------------|------|
| 0 | 1 | 0 | Low (1 line fix) |
| 1 | 4 | 75 | Medium (core runtime) |
| 2 | 5 | 34 | Medium (doctor is heavy) |
| 3 | 3 | 6 | Low |
| 4 | 5 | 26 | Low-Medium |
| 5 | 13 | 42 | Low (test-only changes) |
| 6 | - | - | Verify all tests |
| **Total** | **31** | **183** | |

Note: Some files were already modified in prior commits but still contain `std.Io` references that need API-level fixes (not just syntax changes). The 32 "unfixed" files are the ones not yet touched by any 0.17 commit.
