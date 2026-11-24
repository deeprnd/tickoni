# Version Identity, Doctor, and Demo Manifest Preflight

**Story:** V2.21.S3
**Epic:** V2.21
**Status:** Decision record

> **Superseded in part by platform parity.** Windows, macOS and Linux, on
> x86_64 and ARM64, now have the same functionality (see
> [`platform-tiers.md`](platform-tiers.md)). The `linux_full`, `macos_retail`
> and `windows_retail` tiers and the `full` / `retail` / `degraded` isolation
> tiers no longer describe capability differences; Linux-only features are
> postponed to a future server-only version. Where this record uses tier values
> (`--version` and `doctor` output, manifest `supported_runtime_tiers` /
> `required_isolation_tier`, audit header `platform_tier` / `isolation_tier`),
> read them as host-platform provenance only: they must not gate behavior or
> imply degradation. Renaming or removing those fields changes public CLI,
> manifest and audit schemas, and needs its own approved change.

## 1. Version Source of Truth

**Decision:** Build-time environment variables, injected by `build.zig`.

- `BUILD_VERSION` — semver string (e.g. `0.1.1`), set from `git describe --tags` or
  default `0.0.0-dev` when no tags exist.
- `BUILD_GIT_SHA` — full SHA from `git rev-parse HEAD` at build time.
- `BUILD_ID` — deterministic hash of source tree state (timestamp + git SHA + tag).

These are compiled as `builtin.options` overrides via `build.zig` `addExecutable(options: .{ ... })`.
No runtime dependency on git. Release builds carry the tag; local dev builds carry `-dev`.

### Version output format (T5)

Command:

```bash
tickoni --version
```

Expected output shape:

```
Tickoni 0.1.1
Build ID: tk-20260721-a3f2c9d
Git: a3f2c9d1e8...
OS: macOS ARM64
Runtime Tier: macos_retail
Isolation Tier: retail
Policy Schema: 2
Replay Schema: 2
Demo Manifest: 1
Compiler: clang 15.0.0
```

Each line: `Key: Value`. Header line: `Tickoni <semver>`.

## 2. Demo Manifest Format

**Decision:** JSON file, loaded from a well-known path (`~/.tickoni/demos/<name>/manifest.json` or
a CLI-specified path).

### Required fields

| Field | Type | Required | Notes |
|---|---|---|---|
| `min_tickoni_version` | string (semver) | Yes | Minimum Tickoni semver the manifest requires |
| `supported_runtime_tiers` | array[string] | Yes | Subset of Tier enum labels |
| `required_isolation_tier` | string | Yes | One of: `full`, `retail`, `degraded` |
| `required_fixtures` | array[string] | Yes | Fixture identifiers/names to validate |
| `replay_schema_version` | string (semver) | Yes | Must match installed replay schema |
| `policy_schema_version` | string (semver) | Yes | Must match installed policy schema |
| `expected_no_live_effect` | bool | Yes | Runtime must be in paper/sandbox mode |
| `demo_manifest_version` | string (semver) | Yes | Manifest own version |

### Parse error taxonomy

- `missing_field` — JSON object lacks a required key
- `invalid_semver` — semver field fails semver validation
- `invalid_tier` — tier string not in `Tier` enum
- `parse_error` — JSON syntax error

All parse errors are fatal — no partial loading.

## 3. Preflight Fail-Closed Rules

Every check is independent. If **any** check fails:

1. Print all failures to stderr.
2. Exit with code 1.
3. Produce **zero** audit events, **zero** proposal records, **zero** any side-effect.

### Checks (ordered)

1. **Version** — installed semver >= `min_tickoni_version`
2. **Runtime tier** — `detectTier()` result is in `supported_runtime_tiers`
3. **Isolation tier** — `detectIsolationTier()` matches `required_isolation_tier`
4. **Replay schema** — installed replay schema version >= manifest's
5. **Policy schema** — installed policy schema version >= manifest's
6. **No live effect** — runtime confirms paper/sandbox mode (always true on macOS retail)
7. **Fixtures** — every identifier in `required_fixtures` corresponds to an existing, readable file

### Mismatch error format

```
Preflight failure: runtime tier mismatch
  Required: [linux_full, macos_retail]
  Found: macos_retail (expected 'linux_full' for full runtime parity)
```

## 4. `tickoni doctor` Design

Command:

```bash
tickoni doctor --plain
tickoni doctor --json
```

### Check categories

Each category produces a `DoctorResult`: `{ name, status, message }` where status is `pass | warn | fail`.

**OS/Environment checks:**
- Host OS + version
- Architecture + CPU features
- Environment: container (cgroups), WSL2 (Linux on Windows), VM (hypervisor), or native

**Tool checks:**
- Zig compiler (which + version)
- git (which + version)
- make (which + version)

**Fixture checks:**
- Demo manifest files readable
- Test fixture directory exists

**Mode checks:**
- Model/mock mode status
- Local storage paths writable
- Live execution disabled
- Unsupported direct source builds (warn if built from non-tagged commit)

### Output format

Text (default):
```
tickoni doctor — host report
  [PASS] OS: macOS 14.0 (Darwin 23.0.0)
  [PASS] Architecture: ARM64 (Apple Silicon)
  [PASS] Environment: native
  [PASS] Zig: 0.12.0 (/usr/local/bin/zig)
  [WARN] Git: not found — build metadata will be incomplete
  [PASS] Storage: writable (/Users/user/.tickoni)
  [PASS] Live execution: disabled
  Platform tier: macos_retail
```

JSON (`tickoni doctor --json`):
```json
{
  "os": {"name": "macOS", "version": "14.0", "kernel": "Darwin 23.0.0"},
  "arch": "ARM64",
  "environment": "native",
  "checks": [
    {"name": "zig", "status": "pass", "message": "0.12.0"},
    {"name": "git", "status": "warn", "message": "not found"}
  ],
  "platform_tier": "macos_retail",
  "live_execution_disabled": true
}
```

## 5. Audit/Replay Metadata

**Decision:** Add optional fields to the existing `Header` struct. These are additive — they do not
shift byte layout.

New fields in `Header`:
- `release_digest: [64]u8` — SHA256 hex digest of release (empty for dev builds)
- `platform_tier: [20]u8` — one of: `linux_full`, `macos_retail`, `windows_retail`, `unsupported`
- `isolation_tier: [12]u8` — one of: `full`, `retail`, `degraded`
- `demo_manifest_id: [64]u8` — which manifest was loaded (empty if not running demo)

These fields are always present but may be zero-filled for non-demo/non-release runs.

## 6. File Layout

```
src/tickoni/
  version.zig          — Version info: build_version, git_sha, build_id, output formatting
  doctor/
    checks.zig         — Individual check functions
    output.zig         — Text/JSON output formatting
  demo/
    manifest.zig       — Manifest schema struct + JSON parser + loader
    preflight.zig      — Preflight comparison logic + fail-closed enforcement
  codec/
    audit/
      jsonl.zig        — Extended to serialize new Header fields
schema/
  audit/audit.zig      — Header struct extended with new fields
```

## 7. Dependency Graph

```
version.zig ──► tier.zig (already exists)
doctor/checks.zig ──► tier.zig, version.zig
demo/manifest.zig ──► (independent, std.json)
demo/preflight.zig ──► version.zig, demo/manifest.zig, tier.zig
schema/audit/audit.zig ──► (independent schema)
CLI (tickoni/main.zig) ──► all modules
```

## 8. Security Considerations

- `tickoni doctor` output MUST NOT leak secrets (paths may be shown but no credentials).
- Preflight failures MUST be fail-closed — no partial artifact production.
- Manifest parsing is from user-specified file — size limits and recursion limits apply.
- Version info is read-only metadata — no runtime state mutation.
- `BUILD_VERSION` comes from the build system, not from user input — safe.

## 9. Testing Strategy

- Unit tests: every function in every new module (hardcoded returns for scaffold).
- CLI tests: `tickoni --version` output format, `tickoni doctor --plain`, and `tickoni doctor --json` output format.
- Integration tests: valid manifest parse + preflight pass, invalid manifest parse fail,
  preflight mismatch fail-closed (no artifacts).
- Audit/replay tests: metadata fields present in JSONL output, replay includes metadata.

## 10. Open Questions — RESOLVED

| Question | Decision |
|---|---|
| Version source of truth | Build-time env vars (BUILD_VERSION, BUILD_GIT_SHA, BUILD_ID) injected by `build.zig` |
| Manifest format | JSON (Zig `std.json` built-in, no external deps) |
| Isolation tier derivation | Mapped from runtime tier: linux_full→full, macos_retail→retail, windows_retail→retail, unsupported→degraded |
| Doctor check scope | Platform-relevant only — no Firedancer tile internals, no internal telemetry; command lives on `tickoni` |
| Version semver format | Strict semver 2.0.0 validation (MAJOR.MINOR.PATCH-prerelease+metadata) |
| Manifest file path | `~/.tickoni/demos/<name>/manifest.json` or CLI-specified `--manifest <path>` |
