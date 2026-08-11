# Retail Runtime Support

## Purpose

Canonical retail runtime trust surface. Documents supported binaries, install and
update paths, storage locations, manual verification, privacy defaults,
unsupported features, and execution defaults for every supported retail tier.

Tier definitions themselves, low-level topology ownership, or release-signing
claims that do not exist are out of scope for this document.

## Supported Binaries and Runtime Tiers

| Tier | OS | Arch | Description |
| --- | --- | --- | --- |
| `linux_full` | Linux | x86_64, ARM64 | Shared-memory topology, seccomp/Landlock sandbox, AF_PACKET networking, full tile set |
| `macos_retail` | macOS | ARM64, x86_64 | No seccomp/sandbox, no shared-memory topology, socket networking, reduced tile set |
| `windows_retail` | Windows | x86_64, ARM64 | No seccomp/sandbox, no shared-memory topology, socket networking, reduced tile set |
| `container_assisted` | Any hosted OS | varies | Runs inside another OS/host; tier is that of the host, with additional notes about hosting context |
| `unsupported` | Any | Any | Not a supported OS or architecture; nothing runs |

The Linux full-runtime tier is the default. macOS and Windows retail tiers are
degraded relative to Linux. Linux remains the high-throughput tier unless a
separate decision approves native parity.

### V2.22: Windows Retail (`windows_retail`)

The Windows retail tier was added in V2.22 to bring Tickoni's deterministic
paper-demo, policy-gated, audit-chain, and replay-proof path to Windows consumer
hardware. It uses the same capability envelopes, hash-chained audit records, and
fail-closed guarantees as the Linux full-runtime tier, but with the degraded
guarantees listed below.

Windows retail is available on:

- Windows 10 2004+ for x86_64
- Windows 11 for ARM64 (native ARM64 Zig requires Windows 11)

No WSL2, no Docker Desktop, no VMs. Native portable Tickoni only.

## Workflow-to-Tier Mapping

| Workflow | Linux full | macOS retail | Windows retail | WSL2/VM | Unsupported |
| --- | --- | --- | --- | --- | --- |
| Build | ✓ | ✓ | ✓ | ✓ | ✗ |
| Doctor | ✓ | ✓ | ✓ | ✓ | ✗ |
| Deterministic paper demo | ✓ | ✓ | ✓ | ✓ | ✗ |
| CaseOps review | ✓ | ✓ | ✓ | ✓ | ✗ |
| Replay proof | ✓ | ✗ | ✗ | ? | ✗ |
| Sandbox adapter substitute | ✓ | ✗ | ✗ | ✗ | ✗ |
| Full Linux tile runtime | ✓ | ✗ | ✗ | ✗ | ✗ |

WSL2/VM replay is TBD — depends on whether the container or host provides
deterministic capture semantics.

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

### V2.21 / V2.22 Retail Demo

```bash
# Check host capabilities and tier
tickoni doctor

# Run a deterministic paper investment demo
tickoni demo investment --manifest <path-to-manifest>
```

The demo commands run locally with no outbound network calls. Output includes:

- Runtime tier and isolation tier
- Demo manifest compatibility check
- Policy-checked proposal hash
- Append-only audit JSONL output
- Replay match confirmation
- Blocked-flow diagnostics (if the manifest triggers one)

### Version and Provenance

```bash
# Print version, tier, and build metadata
tickoni --version
```

On Windows retail, this prints `windows_retail` as the runtime tier and `retail`
as the isolation tier.

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
platform produces the same binary hashes. This is verified through the
conformance suite, which checks that deterministic fixture inputs produce
identical normalized event hashes, policy outcomes, proposal hashes, audit
records, and replay results across Linux full-runtime and Windows retail modes.

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

The following features are **not** available on retail tiers (macOS, Windows):

| Feature | Status | Reason |
| --- | --- | --- |
| seccomp / Landlock sandbox | Not supported | OS does not provide kernel-level syscall filtering |
| Shared-memory topology | Not supported | No Firedancer workspace shared memory on retail tiers |
| AF_PACKET / XDP networking | Not supported | Retail tiers use standard sockets only |
| Full Linux tile runtime | Not supported | Only subset of tiles that do not require Linux kernel primitives |
| Replay proof on retail tier | Disabled | Replay substitution required; not deterministic across tiers |
| Sandbox adapter substitute | Disabled | No sandbox layer on retail tiers |
| Live execution / trading | Disabled | Consumer retail mode never enables live money paths |

The `windows_retail` tier additionally does not claim:

- Throughput parity with Linux full runtime
- Shared-memory queue topology
- CaseOps UI tier/degraded-guarantee display (deferred)
- Signed release assets beyond checksum-based verification

## Execution Defaults

### Windows Retail (`windows_retail`)

The Windows retail tier defaults to paper/sandbox/mock/sandbox-substitute
behavior:

- **Live execution is disabled.** Attempting to trigger live trading, payments,
  crypto transfers, or any privileged money-moving operation will fail closed
  with an explicit diagnostic.
- The user sees a clear error indicating that live execution is not supported
  on the `windows_retail` tier.
- All demo flows produce deterministic paper results only.

### macOS Retail (`macos_retail`)

Same defaults as Windows retail: paper/sandbox/mock/sandbox-substitute, live
execution disabled.

## Privacy and Telemetry Defaults

- **Telemetry is disabled by default** on all retail tiers.
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

- [x] Tier definitions documented in `doc/knowledge/platform-tiers.md`.
- [x] No implicit WSL2, container, or VM assumption for supported retail tiers.
- [x] Unsupported features explicitly listed with reasons.
- [x] Per-user install paths documented (no sudo).
- [x] Manual verification via SHA256 checksums documented.
- [x] Update/uninstall behavior documented (evidence preserved by default).
- [x] Privacy and telemetry defaults documented (opt-out, not opt-in).

## Tier Visibility on Windows

### `tickoni --version`

On Windows retail, `tickoni --version` prints:

```
Tickoni 0.1.1
Build ID: ...
Git: abc123def456
OS: Windows x86_64
Runtime Tier: windows_retail
Isolation Tier: retail
Policy Schema: 2
Replay Schema: 2
Demo Manifest: none
Compiler: ...
```

The runtime tier field shows `windows_retail` and the isolation tier shows
`retail` (same as macOS retail).

### `tickoni doctor`

On Windows retail, `tickoni doctor` prints:

```
tickoni doctor — host report
Platform tier: windows_retail
OS: Windows | arch: x86_64
Degradations: sandboxing (disabled), shared memory (disabled), networking (socket path)
Tiles excluded: 5
---
...
```

The degraded dimensions are:

| Dimension | Windows retail | Linux full |
| --- | --- | --- |
| Sandboxing | disabled (no seccomp/Landlock) | enabled |
| Shared memory | disabled (no workspace shm) | enabled |
| Networking | socket path | AF_PACKET / XDP |

Five tiles are excluded from the Windows retail tile set: replay_proof,
sandbox_adapter, full_linux_tile_runtime, and shared-memory-dependent tiles.

### Audit Events

Audit events on Windows carry `platform_tier` in the event header, serialized
identically to Linux and macOS:

- JSONL: `"platform_tier":"windows_retail"`
- Binary: platform_tier field in `schema.Header`
- Wire: 64-byte `platform_tier` field
- Protobuf: field 91 `platform_tier`

### Replay Capsules

Replay capsules on Windows carry the original host's `platform_tier` and flag
any dimension that differs from the replay environment.

### CaseOps (Deferred)

CaseOps tier/degraded-guarantee display is deferred for V2.22. Platform trust
is exposed through CLI, audit, replay, metrics, diagnostics, and linked evidence
artifacts. A future tkapi/UI story must add the dashboard host metadata surface
before docs can claim CaseOps display is shipped.
