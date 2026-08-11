# Platform Support Tiers

## Purpose

Defines the official runtime support tiers for Tickoni, maps workflows to tiers,
and specifies degraded-guarantee visibility rules. This document is the source
of truth for which tiers exist and what each tier guarantees.

Tier definitions are product-language decisions. They do not modify policy
outcomes, audit/replay behavior, topology changes, or CaseOps integration —
those are scoped to separate stories (S3, S7, etc.).

## Tier Inventory

| Tier | OS | Arch | What it is |
| --- | --- | --- | --- |
| `linux_full` | Linux | x86_64, ARM64 | Shared-memory topology, seccomp/Landlock sandbox, AF_PACKET networking, full tile set |
| `macos_retail` | macOS | ARM64, x86_64 | No seccomp/sandbox, no shared-memory topology, socket networking, reduced tile set |
| `windows_retail` | Windows | x86_64, ARM64 | No seccomp/sandbox, no shared-memory topology, socket networking, reduced tile set |
| `container_assisted` | Any hosted OS | varies | Runs inside another OS/host; tier is that of the host, with additional notes about hosting context |
| `unsupported` | any | any | Not a supported OS or architecture; nothing runs |

The Linux full-runtime tier is the default. V2.21 (macOS) and V2.22 (Windows)
define their respective retail tiers as degraded relative to Linux. Linux
remains the high-throughput tier unless a separate decision approves native
parity.

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
deterministic capture semantics. Marking `?` until a decision is made.

## Degraded Guarantees

Each non-Linux tier has the following degraded guarantees relative to Linux
full-runtime. The degradation applies to every workflow on that tier.

### Sandboxing

seccomp and Landlock are unavailable on macOS and Windows. Tiles that require
sandbox enforcement are excluded from the retail tile set. No sandbox guarantee.

### Shared Memory

Firedancer workspace and topology shared memory are unavailable on macOS and
Windows. No deterministic queue topology. Tiles that depend on shared memory
are stubbed or excluded.

### Networking

AF_PACKET and XDP are unavailable on macOS and Windows. Standard sockets are
used instead. Throughput is bounded by socket I/O, not kernel-bypass ring I/O.

**Stub behavior note:** some retail stubs use a "stub object" pattern
(`fd_platform_stub_object_new()`) that returns a valid non-NULL pointer so
callers don't null-crash, but all functional methods are no-ops. A few
metadata bookkeeping functions (gRPC stream send/close) return 0 to avoid
polluting errno. The actual data path (socket `rxtx`, HTTP listen, UDP send)
correctly fails closed with errno.

### Performance

No shared-memory queues means no Firedancer throughput model. Expected throughput
is bounded by socket I/O. The tier name "retail" signals this to users.

### Execution

Full tile runtime is not available outside Linux. Only the subset of tiles that
do not require Linux kernel primitives run on retail tiers.

## Visibility Rules

The tier and its degraded dimensions must be visible in all five surfaces.

### CLI (`tickoni doctor`)

The supported product command is `tickoni doctor` on the retail-facing `tickoni`
binary. It prints tier name, OS, architecture, degraded dimensions, and
affected tiles:

```
Tier: macos_retail
OS: macOS 14.5 | arch: arm64
Degradations: sandboxing (disabled), shared memory (disabled), networking (socket path)
Tiles excluded: 5
```

### CLI (`tickoni --version`)

The supported product command is `tickoni --version` on the retail-facing
`tickoni` binary. It prints the version/provenance fields plus the runtime and
isolation tiers as the short trust surface for retail users.

### CaseOps

CaseOps tier/degraded-guarantee display is deferred for V2.21. In this epic,
platform trust is exposed through CLI, audit, replay, metrics, diagnostics, and
linked evidence artifacts. A future tkapi/UI story must add the dashboard host
metadata surface before docs can claim CaseOps display is shipped.

### Audit

Each audit event records the tier of the host that generated it. Replay output
reports the original host's tier and flags any dimension that differs from the
replay environment.

### Documentation

This document is the canonical support matrix. Any change to tier definitions,
new tiers, or updated degradation rules must be documented here before other
docs or stories reference them.

## Decision Rules

| Question | Owner |
| --- | --- |
| What tiers exist and what do they guarantee? | This document (V2.21.S1 / V2.22.S1) |
| How do we detect the tier at runtime? | S3 (doctor/preflight) |
| How is tier shown in CaseOps? | Deferred beyond V2.21; S7 documents the deferral explicitly |
| How do we test per tier? | Separate testing story |

## Quality Gate

- [x] Tier definitions are documented in this file.
- [x] No story in V2.21/V2.22 can proceed with an implicit WSL2, container,
      or VM choice without an explicit tier decision (see `?` cell for
      WSL2 replay — not resolved yet, but the table makes it visible).
- [x] Documentation and roadmap status are updated when tier definitions change.
      (Owners of roadmap stories must reference this doc.)
