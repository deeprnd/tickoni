# Retail Runtime Support

## Purpose

Canonical retail runtime trust surface. Documents supported binaries, install and
update paths, storage locations, manual verification, privacy defaults,
unsupported features, and execution defaults for retail Tickoni.

Platform support definitions themselves, low-level topology ownership, or
release-signing claims that do not exist are out of scope for this document.
Platform support is defined in
[`doc/knowledge/platform-tiers.md`](../knowledge/platform-tiers.md).

## Supported Platforms

Retail Tickoni is on par on every supported platform. The same binaries, tile
runtime, shared-memory topology, workflows and guarantees apply everywhere:

| OS | Arch | Support |
| --- | --- | --- |
| Windows (10 2004+ on x86_64, 11 on ARM64) | x86_64, ARM64 | Full |
| macOS | x86_64, ARM64 | Full |
| Linux | x86_64, ARM64 | Full |
| any other OS or architecture | any | `unsupported`: nothing runs |

Native ARM64 Zig on Windows requires Windows 11. WSL2, VMs and containers are
not a separate support class: Tickoni runs as the platform its process sees.
Native portable Tickoni needs no WSL2, Docker Desktop or VM.

Linux-only features (seccomp/Landlock sandboxing, namespaces, AF_PACKET/XDP
networking, huge pages, CPU pinning) are not part of retail Tickoni on any
platform. They are postponed to a future server-only version.

## Workflows

| Workflow | Windows, macOS, Linux (x86_64, ARM64) |
| --- | --- |
| Build | ✓ |
| Doctor | ✓ |
| Deterministic paper demo | ✓ |
| CaseOps review | ✓ |
| Replay proof | ✓ |
| Sandbox adapter substitute | ✓ |
| Full tile runtime | ✓ |

## Install Paths

### Windows

- Binary directory: `%LOCALAPPDATA%\tickoni\bin\` (per-user, no `sudo`)
- Config/evidence directory: `%LOCALAPPDATA%\tickoni\` (user-scoped)
- Log directory: `%LOCALAPPDATA%\tickoni\logs\` (user-scoped)

### macOS

- Binary directory: `$HOME/.tickoni/bin/` (per-user, no `sudo`)
- Config/evidence directory: `$HOME/.tickoni/` (user-scoped)
- Log directory: `$HOME/.tickoni/logs/` (user-scoped)

### Linux

- Binary directory: `$HOME/.tickoni/bin/` (per-user, no `sudo`)
- Config/evidence directory: `$HOME/.tickoni/` (user-scoped)
- Log directory: `$HOME/.tickoni/logs/` (user-scoped)

All install, update, and uninstall paths are per-user only. No elevated
privileges are required or requested.

## Storage Locations

Evidence, config, and logs all live under user-scoped directories:

| Category | Path pattern | Access |
| --- | --- | --- |
| Evidence artifacts | `~/.tickoni/evidence/` | User |
| Config files | `~/.tickoni/config/` | User |
| Log files | `~/.tickoni/logs/` | User |
| Binary cache | `~/.tickoni/bin/` | User |

No files are written to system directories (`/etc/`, `/var/`, `Program Files/`)
during install, demo, or evidence generation.

## Demo Commands

### Retail Demo

```bash
# Check host and preflight
tickoni doctor

# Run a deterministic paper investment demo
tickoni demo investment --manifest <path-to-manifest>
```

The demo commands run locally with no outbound network calls. Output includes:

- Host platform (OS and architecture)
- Demo manifest compatibility check
- Policy-checked proposal hash
- Append-only audit JSONL output
- Replay match confirmation
- Blocked-flow diagnostics (if the manifest triggers one)

### Version and Provenance

```bash
# Print version, host platform, and build metadata
tickoni --version
```

The output is the same on every platform apart from the host OS, architecture
and compiler values.

## Manual Verification

Users can verify release artifacts by comparing SHA256 checksums:

1. Obtain the published checksum for the release artifact (e.g. `tickoni-x.x.x-win.zip.sha256`).
2. Compute the checksum locally:

   ```bash
   # Windows (PowerShell)
   Get-FileHash -Algorithm SHA256 tickoni-x.x.x-win.zip

   # macOS / Linux
   sha256sum tickoni-x.x.x.tar.gz
   ```

3. Compare the output against the published checksum.

Build reproducibility: rebuilding Tickoni from the same commit on the same
platform produces the same binary hashes. Cross-platform behavior is verified
through the conformance suite, which checks that deterministic fixture inputs
produce identical normalized event hashes, policy outcomes, proposal hashes,
audit records, and replay results on Windows, macOS and Linux, x86_64 and ARM64.

## Update / Uninstall Behavior

### Update

- Updates are per-user and do not require admin rights.
- Evidence and config are preserved across updates by default.
- A manual verification route (SHA256 checksum) is available for each update.

### Uninstall

- Uninstall removes binaries, logs, and config from the user-scoped directory.
- Evidence artifacts are **preserved** by default to support audit continuity.
- Full reset (including evidence removal) is opt-in.

```bash
# Windows: remove user-scoped directory
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\tickoni"

# macOS / Linux: remove user-scoped directory
rm -rf ~/.tickoni
```

## Unsupported Features

The following features are **not** available in retail Tickoni on any platform:

| Feature | Status | Reason |
| --- | --- | --- |
| seccomp / Landlock / namespace sandbox | Postponed to server-only version | Linux-only; would make the Linux product diverge |
| AF_PACKET / XDP networking | Postponed to server-only version | Linux-only; retail uses standard sockets everywhere |
| Huge-page workspaces, CPU pinning | Postponed to server-only version | Linux-only; retail uses normal-page workspaces and the OS scheduler |
| Live execution / trading | Disabled | Consumer retail mode never enables live money paths |

Retail Tickoni also does not claim:

- CaseOps UI display of host platform metadata (deferred)
- Signed release assets beyond checksum-based verification

## Execution Defaults

On every platform, retail Tickoni defaults to paper/sandbox/mock/sandbox-substitute
behavior:

- **Live execution is disabled.** Attempting to trigger live trading, payments,
  crypto transfers, or any privileged money-moving operation will fail closed
  with an explicit diagnostic.
- The user sees a clear error indicating that live execution is not supported
  in retail Tickoni.
- All demo flows produce deterministic paper results only.

## Privacy and Telemetry Defaults

- **Telemetry is disabled by default** on every platform.
- `tickoni --version`, `tickoni doctor`, and the deterministic demo flows do not
  require outbound telemetry.
- Evidence generation is local/offline by default.
- Opt-in diagnostics or managed export require an explicit future privacy
  decision and are not claimed as part of the retail support path.
- Installers do not request broker, payment, crypto, approved execution ledger,
  or live model-provider credentials.

## Package Inclusion Rules

Consumer retail packages include only:

1. Tickoni-owned code from the `deeprnd/tickoni` repository
2. Reused Firedancer substrate that Tickoni actually depends on

Excluded from retail packages:

- Solana validator tiles
- RPC schemas
- Unrelated Firedancer source
- Any source code not actually reused by Tickoni's retail tile set

## Quality Gate

- [x] Platform support documented in `doc/knowledge/platform-tiers.md`.
- [x] No implicit WSL2, container, or VM assumption.
- [x] Unsupported features explicitly listed with reasons.
- [x] Per-user install paths documented (no sudo).
- [x] Manual verification via SHA256 checksums documented.
- [x] Update/uninstall behavior documented (evidence preserved by default).
- [x] Privacy and telemetry defaults documented (opt-out, not opt-in).

## Platform Visibility

The host platform is visible as provenance. It never gates behavior or implies
degradation.

### `tickoni --version`

`tickoni --version` prints the version and provenance fields plus the host OS,
architecture and compiler. The `Runtime Tier` and `Isolation Tier` lines from
the V2.21/V2.22 output are host-platform provenance only (see the note in
[`version-identity.md`](../knowledge/version-identity.md)); renaming or removing
them is a separate, approved CLI contract change.

### `tickoni doctor`

`tickoni doctor` prints the host OS, architecture and preflight results. It
prints no degradations and no excluded tiles, because no platform has any.

### Audit Events

Audit events carry the host platform in the event header's `platform_tier`
field, serialized identically on every platform:

- JSONL: `"platform_tier":"<host platform>"`
- Binary: platform_tier field in `schema.Header`
- Wire: 64-byte `platform_tier` field
- Protobuf: field 91 `platform_tier`

The field is provenance only. Changing its name or values is an audit schema
change that needs approval.

### Replay Capsules

Replay capsules carry the original host platform. A different replay host is
reported as information, never as a divergence by itself.

### CaseOps (Deferred)

CaseOps display of host platform metadata is deferred. Platform provenance is
exposed through CLI, audit, replay, metrics, diagnostics, and linked evidence
artifacts. A future tkgate/UI story must add the dashboard host metadata surface
before docs can claim CaseOps display is shipped.
