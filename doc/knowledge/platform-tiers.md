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

`fd_sandbox_enter` (Firedancer's Linux sandbox) executes 17 steps:

| # | Mechanism | Linux | macOS | Windows |
|---|-----------|-------|-------|---------|
| 1 | Clear env vars | ✓ | ✓ | ✓ |
| 2 | Validate open FDs | ✓ | ✓ | ✓ |
| 3 | Drop supplementary groups | ✓ | ✓ | ✓ |
| 4 | Session keyring | Linux-only | ✗ | ✗ |
| 5 | New process group | ✓ | ✓ | ✓ |
| 6 | Switch UID/GID | ✓ | ✓ | ✓ |
| 7 | Unshare namespaces (mount, net, cgroup, ipc, uts) | ✓ | ✗ | ✗ |
| 8 | User namespace | ✓ | ✗ | ✗ |
| 9 | Sysctl hardening | Linux-only | ✗ | ✗ |
| 10 | Nested user namespace | Linux-only | ✗ | ✗ |
| 11 | Dumpable bit | ✓ | ✓ | ✓ |
| 12 | Root filesystem pivot | Linux-only | ✗ | ✗ |
| 13 | Resource limits (rlimits) | ✓ | ✓ | ✓ (partial) |
| 14 | Drop all capabilities | Linux-only | ✗ | ✗ |
| 15 | `no_new_privs` | Linux-only | ✗ | ✗ |
| 16 | Landlock | Linux-only (kernel 5.13+) | ✗ | ✗ |
| 17 | Seccomp-BPF | Linux-only (kernel 3.17+) | ✗ | ✗ |

10 of 17 steps are Linux-only syscalls with no macOS or Windows equivalent.
Namespaces, user namespaces, capabilities, seccomp, Landlock, keyring, and
pivot_root do not exist on those platforms.

macOS provides `sandbox_init()` (BSD sandbox profiles, since 10.8), which controls
network and file access but not syscalls. Code signing and entitlements are
mandatory for many operations but cannot be set programmatically per-process.
`setuid`/`setgid` and `setrlimit` work. No namespaces, no seccomp, no capabilities.

Windows provides Job Objects (`JOB_OBJECT_LIMIT_*`) for CPU, memory, and handle
limits; Mandatory Integrity Levels (coarse-grained access control); Restricted
Tokens (limited access tokens). No namespaces, no seccomp, no capabilities, no
pivot_root.

**Conclusion:** `fd_sandbox_enter` cannot be ported to macOS/Windows. The header
is `#if defined(__linux__)` for a reason. On macOS and Windows, the sandbox
boundary is process-level isolation (separate address spaces, which Tickoni
already has with its process-mode tiles), plus whatever coarse mechanisms exist
(UID/GID switching, resource limits, `sandbox_init` on macOS for network/file
access). The Linux full-runtime tier is the only tier with seccomp/Landlock
enforcement. Retail tiers have process isolation only.

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

### CPU Placement (Affinity)

Firedancer pins threads to cores with `sched_setaffinity` / `cpuset` because
Firedancer tiles are **threads within a single process**. Pinning gives:

- L1/L2 cache stays warm on the same core — no cold cache on migration.
- No cross-core TLB flushes (threads share page tables).
- Cheap context switching within one address space.
- Hyperthreading: two threads per core, each pinned, avoiding OS scheduler
  interference.
- NUMA: pin to the local node so shared memory accesses are fast.

This matters at 100K+ TPS because every microsecond of cache locality is ~100K
cache hits you don't miss.

Tickoni tiles are **separate processes**. Each process already has its own page
tables, its own TLB, and a cold L1/L2 at startup. The IPC boundary (shared
memory) already breaks the cache-locality chain that makes pinning valuable:

- **Cache locality?** Marginal. Process B doesn't benefit from Process A's cache.
- **TLB stability?** Negligible. Each process has its own page tables.
- **Reduced context switches?** Slightly, but the real cost is IPC/serialization
  between tiles, not context switches.
- **NUMA locality?** No. Shared memory regions are allocated globally; accessing
  them from any core goes through the same NUMA path.

**Conclusion:** CPU affinity in Tickoni's process-model is a Firedancer relic.
The performance benefit is vanishingly small because the IPC boundary already
breaks the cache-locality chain. At best it prevents the OS from moving a process
between cores, which saves a handful of TLB misses — nowhere near the cost of
inter-process communication. CPU placement (`exclusive`, `shared`, `floating`) is
Tickoni-owned policy, but the supervisor does not call `sched_setaffinity`,
`SetThreadAffinityMask`, or any affinity API. Tile processes run with whatever
the OS scheduler assigns. Shared-core placement (`shared`) is accepted only when
the Tickoni config declares it and is visible in metrics, diagnostics, or
supervisor output.

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
