# Platform Support

## Purpose

Defines which platforms Tickoni supports and what they guarantee. This document
is the source of truth for platform support.

**Tickoni has one runtime contract on every supported platform.** Windows, macOS
and Linux, on x86_64 and ARM64, run the same tile runtime and offer the same
functionality. There are no per-OS capability tiers, no degraded modes and no
OS-specific tests. (This file keeps its historical name `platform-tiers.md`
because other documents link to it. The former `linux_full`, `macos_retail` and
`windows_retail` tiers are retired.)

Platform support does not modify policy outcomes, audit/replay behavior, tile
topology or CaseOps integration. Those are defined once, for all platforms, in
their own documents.

## Supported Platforms

| OS | Architectures | Support |
| --- | --- | --- |
| Windows | x86_64, ARM64 | Full |
| macOS | x86_64, ARM64 | Full |
| Linux | x86_64, ARM64 | Full |
| any other OS or architecture | any | `unsupported`: nothing runs |

"Full" means the same thing on all six supported combinations. A platform is not
a reference platform for the others, and a behavior that works on one supported
platform and not on another is a bug in Tickoni, not a documented difference.

Hosted environments (WSL2, VMs, containers) are not a separate support class.
Tickoni runs as the platform its process sees: a Linux kernel in WSL2 is Linux.
Docker may help with development and packaging, but it is not the runtime
security model.

## Functionality On Every Platform

| Capability | Contract (all six platforms) |
| --- | --- |
| Build, `tickoni doctor`, `tickoni --version` | Same commands, same output fields |
| Deterministic paper demo | Same behavior |
| CaseOps review | Same behavior |
| Replay proof | Same behavior, with external effects disabled |
| Full tile runtime | Same tile set, same tile identities, same links |
| Shared-memory topology | Firedancer Tango `mcache`/`dcache` links with `fseq`/`fctl` flow control and Firedancer workspaces, through Tickoni-owned wrappers |
| Tile isolation | One supervisor-managed OS process per tile, each with its own address space, crash-only behavior |
| Networking | Standard sockets |
| Tile liveness, freeze/resume, process metrics | Portable shim APIs with one implementation per OS behind one interface |

Rules that follow from this contract:

- **Same inputs, same facts.** Equivalent inputs produce the same normalized
  financial facts, hashes, audit chain and replay results on every platform.
  A platform difference between capture and replay is never a divergence by
  itself. The cross-platform conformance exports and comparisons
  (`compare-cli-conformance`, `compare-build-artifact-conformance`) are how this
  is verified.
- **No OS-specific product behavior.** OS differences live in the portable shim
  layer (`src/tickoni/c_abi/shim/`, `src/tickoni/util/`) behind a single
  interface. Tile, policy, audit, replay, API and test code must not branch on
  the host OS.
- **No OS-specific tests.** Integration and unit tests run on every platform and
  must not carry OS guards or platform skips. A test that fails on one platform
  is a bug to root-cause and fix. The one OS-flavored area is freezing and
  resuming a tile process (SIGSTOP/SIGCONT on POSIX, `NtSuspendProcess` and
  `NtResumeProcess` on Windows). It goes through the portable
  `tk_process_suspend` / `tk_process_resume` API, so the tests stay identical.
- **Authorization is finance-native, not OS-native.** Who may do what is decided
  by capability envelopes in `tkpoly` and enforced at the `tkmodl`, `tktool`,
  `tkadpt` and `tkexec` boundaries, identically on all platforms. It never
  depends on an OS sandbox.

## Postponed To The Server-Only Version

These Linux-specific mechanisms are **not** part of retail Tickoni on any
platform, including Linux, because adopting them would make one platform's
product diverge from the others. They are postponed to a future server-only
Linux version (see Server-Only Features) and are not used or required anywhere
in the retail product today:

- seccomp-BPF, Landlock, Linux namespaces (mount, net, cgroup, ipc, uts, user),
  capability dropping, `no_new_privs`, `pivot_root`, session keyrings,
  sysctl hardening (the `fd_sandbox_enter` steps that exist only on Linux),
- AF_PACKET and XDP kernel-bypass networking,
- huge-page or gigantic-page workspace requirements,
- hard CPU pinning with `sched_setaffinity` / cpusets (see CPU Placement),
- any dependency on `/proc`, `/sys` or another Linux-only interface in code that
  is not behind the portable shim layer.

Firedancer infrastructure is reused only where it is portable to all six
platforms. Firedancer's Linux-only substrate stays in upstream Firedancer and
does not become a Tickoni framework concept.

## Server-Only Features

Linux-specific features are postponed to a future server-only version of
Tickoni, such as kernel-bypass ingest or seccomp/Landlock sandbox hardening for
a hosted Linux deployment. A server-only feature must:

1. be an explicit, opt-in server profile that is off by default,
2. be documented here before any other document or story references it,
3. never be required by any workflow, demo, CaseOps flow or test that the retail
   product supports,
4. never change the deterministic event path, normalization, deduplication,
   audit records, policy outcomes or replay results,
5. be an explicit product decision, not an implementation detail.

No such feature exists today. Retail Tickoni must stay on par on Windows, macOS
and Linux, x86_64 and ARM64.

## CPU Placement (Affinity)

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

The host platform must be visible, and nothing may be hidden behind it.

### CLI (`tickoni doctor`)

`tickoni doctor` on the retail-facing `tickoni` binary prints the host OS and
architecture and the result of each preflight check. It prints no
"degradations" and no "excluded tiles", because no platform has any.

### CLI (`tickoni --version`)

`tickoni --version` prints the version and provenance fields plus the host OS,
architecture and compiler.

### CaseOps

CaseOps does not display a platform capability level, because there is none to
show. Host platform metadata may be shown as plain provenance once a tkgate/UI
story adds the dashboard host metadata surface.

### Audit

Each audit event records the host platform that generated it, in the audit
header's existing platform field. The field is provenance only. It never gates
behavior. Replay output reports the original host platform and treats a
difference from the replay host as informational, not as a divergence. Changing
the audit header schema is a separate, approved change.

### Documentation

This document is the canonical support statement. Any new platform, any
platform-specific behavior, or any server-only feature must be documented here
before other docs or stories reference it.

## Decision Rules

| Question | Owner |
| --- | --- |
| Which platforms are supported and what do they guarantee? | This document |
| Is a feature allowed to differ by platform? | Only as a server-only feature under the rules above; otherwise no |
| Where do per-OS differences live? | The portable shim layer, one interface per capability |
| How do we test per platform? | The same tests on all six platforms; conformance exports compare results |

## Quality Gate

- [x] One support contract for all supported platforms is documented here.
- [x] Linux-only mechanisms are listed as postponed to the server-only version.
- [x] Server-only features have explicit admission rules.
- [ ] Code, tests and other docs are aligned with this contract (open: the old
      tier names and degradation output still exist in code and in other docs).
