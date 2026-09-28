# Tickoni Tile Orchestration

## Decision

Tickoni uses a Tickoni-owned tile orchestration boundary with a
Firedancer-backed Linux full-runtime implementation.

The public orchestration model is Tickoni-owned:

- Tickoni tile ids and roles
- Tickoni topology descriptors and link contracts
- Tickoni support tiers
- Tickoni capability, audit, replay, evidence, model, tool, adapter, and
  execution contracts
- Tickoni runtime diagnostics and operator-facing status

The Linux full-runtime implementation should reuse Firedancer orchestration
semantics through an adapter instead of rebuilding a parallel harness. The
adapter may map Tickoni runtime descriptors to the Firedancer topology/run
surface internally, but product code must not depend on Firedancer validator
topology types, Solana tile kinds, validator config stages, validator metrics,
or validator schemas.

For macOS and Windows retail runtimes, the same Tickoni orchestration boundary
applies. The implementation may use portable substitutes or fail-closed
unsupported operations. Native retail builds must not assume that
`libfd_tango.a`, `libfd_util.a`, or `libfd_ballet.a` compile, link, or export
the same symbols as the Linux build. Target-specific `c_abi` implementations
select the correct behavior at compile/link time, not only at runtime.

## Scope

This document describes how tile orchestration is meant to work at the
architecture boundary.

It owns launch lifecycle, Firedancer harness adapter semantics, runtime-tier
implementation boundaries, registry responsibility, link discovery,
health/staleness behavior, shutdown behavior, and crash visibility.

It does not own the canonical list of Tickoni tile IDs, product event flow, or
reuse/exclude decisions for validator tiles. Those are owned by
[`tile-topology.md`](tile-topology.md).

It does not decide product policy, financial capability semantics, audit
schema, replay capsule format, model-provider behavior, adapter authority, or
execution approval rules. Those remain owned by the relevant Tickoni product
and schema documents.

It also does not evaluate alternatives. The option analysis lives in:

- `doc/knowledge/rant/firedancer-orchestration-reuse.md`
- `doc/knowledge/rant/static-inline-and-ffi.md`

## Core Model

Tickoni has one orchestration contract with multiple implementation tiers:

```text
Tickoni product topology
  tile ids, roles, link descriptors, placement, support tier
        |
        v
Tickoni orchestration boundary
  registry, callbacks, lifecycle, link discovery, diagnostics contract
        |
        +--> Linux full runtime
        |     Firedancer-backed adapter
        |     real process isolation, real Firedancer shared memory,
        |     real sandbox/metrics/lifecycle semantics where supported
        |
        +--> macOS / Windows retail runtime
              portable or reduced-isolation implementation,
              deterministic paper/sandbox demos, visible degraded guarantees,
              fail-closed unsupported live effects
```

The boundary is stable. The implementation behind it is selected by target and
runtime tier.

## Firedancer Orchestration Mechanics

Firedancer's useful orchestration machinery is not a single primitive. It is a
stack of conventions and guardrails:

1. A topology describes tiles, workspaces, links, per-tile input link arrays,
   per-tile output link arrays, metrics storage, CPU placement, memory
   footprint, and sandbox-relevant details. (See
   [workspace-management.md](../knowledge/workspace-management.md) for workspace
   lifecycle, backing strategy, and the Firedancer vs Tickoni divergence.)
2. A tile run descriptor provides callbacks and resource policy:
   footprint/alignment, privileged init, unprivileged init, run callback,
   allowed file descriptors, seccomp policy, file/address-space/process
   limits, and shutdown rules.
3. The runner joins tile workspaces, runs privileged init, enters sandbox,
   fills link pointers from topology, registers metrics, runs unprivileged
   init, calls the tile run loop, and checks shutdown expectations when the
   run callback returns.
4. The stem pattern provides the hot-loop discipline used by many Firedancer
   tiles: loop-top shutdown check, periodic housekeeping, credit/backpressure
   handling, input polling, fragment processing, output publication, and
   heartbeat/metric visibility.
5. The supervisor path owns process/thread launch, child tracking, crash
   visibility, and crash-only shutdown behavior.

The Firedancer shape to preserve is the semantics of that lifecycle:

```text
tile selected from topology
  -> join required workspaces
  -> privileged_init
  -> enter sandbox
  -> fill/join input and output links
  -> register metrics or equivalent health surface
  -> unprivileged_init
  -> run tile loop
  -> enforce shutdown/exit expectations
```

The Linux full-runtime adapter must preserve the ordering, guard intent, and
failure behavior of these steps unless an explicit Tickoni substitute is
documented and tested.

## Non-Blocking I/O Discipline

**All tile receive paths must use bounded polling. No tile may perform
blocking I/O (OS-level sleep, wait, futex, condition variable, or synchronous
read on a file/pipe/socket) in its hot loop.**

This is the fundamental constraint that makes the entire tile lifecycle
correct: heartbeat, halt, shutdown, and health checks interleave with data
processing because the hot loop is always returning to the stem's top-level
iteration and can observe external signals at every iteration boundary.

### The Pattern (Firedancer `FD_MCACHE_WAIT`)

Firedancer's `FD_MCACHE_WAIT` macro is the canonical example:

```c
for(;;) {
    seq_found = mline->seq;     // atomic read from shared memory
    *meta     = *mline;         // copy metadata if stable
    if (stable && not_behind) break;
    FD_SPIN_PAUSE();            // CPU hint, NOT a syscall
    --poll_max;
    if (!poll_max) return;      // bounded: timed out, not blocked
}
```

Key properties:

- **No syscalls in the spin loop.** `FD_SPIN_PAUSE()` is a compiler hint
  (typically `pause` x86 instruction or equivalent), not a wait or sleep.
- **Bounded.** `poll_max` caps iterations. When it reaches zero, the macro
  returns and the caller decides what to do next. The tile is never stuck
  inside `FD_MCACHE_WAIT` for more than a fraction of a second.
- **Spin, don't sleep.** On a hit (data available), the macro exits immediately.
  On a miss (no data yet), it retries in a tight loop that yields CPU to
  sibling threads via `pause` but never yields the core to the OS.
- **Overrun-safe.** If the consumer falls more than `depth` behind the producer,
  `seq_diff > 0` and the caller knows the expected metadata has been evicted.
  The macro does not retry forever.

### Stem Loop Structure

The stem loop (`fd_stem.c` `stem_run1`) interleaves the following every iteration:

1. **Shutdown check** — `STEM_CALLBACK_SHOULD_SHUTDOWN(ctx)` at the top of
   every loop iteration. Returns immediately when shutdown is set.
2. **Housekeeping** — periodic health/metric publishing, credit replenishment,
   input flow-control updates, event-map randomization. Driven by a lazy
   timer (`STEM_LAZY`) that fires every ~50-100ms.
3. **Credit/backpressure check** — if downstream has no credits, `continue`
   to next iteration to recheck credits. Never blocks waiting.
4. **Input polling** — for each input link, check if a new fragment is
   available via `FD_MCACHE_WAIT` with a short poll budget. If no data,
   advance to the next input or recheck credits.
5. **Fragment processing** — `BEFORE_FRAG` → `DURING_FRAG` → `AFTER_FRAG`
   callbacks. These are the only place tile-specific logic executes.
6. **Output publication** — publish to downstream via `fd_stem_publish`.

Every iteration boundary is an interleaving point for shutdown, health, and
backpressure. A tile cannot get stuck because there is no blocking point
between iterations.

### Tickoni Application

Tickoni Phase 0 tiles (`tkings`, `tknorm`, `tkdedu`, `tkpoly`, `tkaudt`,
`tkmetr`, `tkdiag`) already follow this pattern: they process bounded event
counts, have no network/file I/O in the hot path, and use `fd_topo_run_tile`
or equivalent harness loops that interleave heartbeat with work.

Future tiles (`tkcase`, `tkrepl`, `tkmodl`, `tktool`, `tkadpt`, `tkapi`) must
adhere to the same discipline:

- **Model access (`tkmodl`):** Use bounded polling on shared memory or a
  non-blocking queue from the LLM server proxy. Never have the model thread
  block waiting for a response. Responses arrive via shared memory or a
  pre-allocated ring buffer.
- **Adapter access (`tktool`, `tkadpt`):** Read and write through bounded
  shared-memory queues or a proxy tile that does the I/O and publishes
  results asynchronously. The consumer tile polls, never blocks.
- **API/transport (`tkapi`):** Use Firedancer's `fd_http_server` infrastructure
  or a non-blocking event loop. Never have a handler block the tile's
  heartbeat/halt loop.
- **Replay (`tkrepl`):** Substitutes external effects with captured data.
  The replay loop is inherently bounded because it processes a fixed capsule.
- **CaseOps (`tkcase`, `tkdisp`):** All processing is in-memory against
  Tickoni-owned shared memory. No file or network I/O in the hot path.

### Deviation: Bounded Sleep Instead of Pure Spin

Firedancer tiles are pinned to dedicated, isolated cores. `FD_MCACHE_WAIT`
spins for the entire `poll_max` budget on that core and then returns. The
cost is one core per idle tile — acceptable because a validator node has
many cores and each tile is latency-critical on its own pinned core.

Tickoni runs on targeted consumer hardware with limited cores. We cannot
guarantee tile-to-core exclusivity: multiple tiles share cores as threads.
If each tile spins for the full poll budget when genuinely idle, `N` idle
links burn `N` entire cores even though no work is being done.

The link primitives (`consumer.zig`, `producer.zig`) use a **hybrid pattern**:

```
1. Spin `spin_poll_max` (4096) iterations via spinPause()
2. Check stop/halt and update heartbeat via cnc
3. sleepNanos(idle_sleep_ns) — 100μs on Linux
4. Loop back to step 1
```

This trades ~100μs of added idle latency for a single core shared across
many tiles. The sleep is **bounded and interruptible** — the stop and halt
checks run on every iteration (after each sleep returns), so a shutdown
signal cannot be missed. The 100μs sleep is the housekeeping and stop-check
point, replacing Firedancer's per-tile-housekeeping on a dedicated core.

Firedancer's `FD_MCACHE_WAIT` achieves its "no sleep" guarantee by running
on a pinned core where spinning is a resource cost the system has already
paid. Tickoni's shared-core model cannot make that trade — it must sleep
during idle to keep the total tile-to-core ratio manageable. This is a
conscious architectural relaxation, not an oversight: it is documented in
`wait.zig` and enforced in the link primitives.

### Anti-Patterns (What to Avoid)

- `sleep()`, `nanosleep()`, `usleep()` — OS-level sleep, blocks the entire
  tile thread and prevents shutdown/heartbeat from interleaving.
- `pthread_cond_wait()` or `futex()` — blocks the tile thread. The stem loop
  cannot observe shutdown or health changes while the thread is waiting.
- `read()` on a blocking socket or pipe — blocks on EOF or no-data. Use
  `FD_MCACHE_WAIT` on a shared-memory ring buffer instead.
- Synchronous file I/O in the hot path — disk latency varies wildly and can
  block the tile for seconds. Buffer to memory and flush asynchronously.
- Any `select()`/`poll()`/`epoll_wait()` with `timeout == -1` — the entire
  purpose of the polling discipline is to eliminate indefinite waits.

### Enforcement

This discipline is non-negotiable for any tile that participates in the
Firedancer-backed or Tickoni-own harness. If a tile must interact with a
blocking external system (LLM server, trading API, file system), the pattern
is:

1. The tile writes a request to a bounded shared-memory queue.
2. A proxy tile (or Firedancer `fd_http_server` worker) reads the request,
   performs the blocking I/O, and writes the response back to shared memory.
3. The original tile polls the response queue with `FD_MCACHE_WAIT`.
4. If the queue is empty, the tile continues to the next input or rechecks
   health/shutdown. It never blocks.

## What Tickoni Reuses

Tickoni reuses Firedancer infrastructure in two forms.

### Linux Full Runtime

The Linux full-runtime tier reuses Firedancer orchestration as deeply as the
Tickoni boundary allows:

- topology construction via `fd_topob.c` (the real Firedancer topology builder)
- workspace creation and join via `fd_wksp_*` (normal-page backing; see
  [workspace-management.md](../knowledge/workspace-management.md) for the
  hugetlbfs vs normal-page divergence)
- link filling for `mcache`, `dcache`, `fseq`, and related state
- sandbox entry and allowed-fd/seccomp discipline where supported
- metrics registration or equivalent per-tile health visibility
- process/thread launch semantics where the selected Linux mode uses them
- crash and shutdown semantics
- stem-loop guard patterns for shutdown, housekeeping, credit, and heartbeat
- per-tile CPU placement via `fd_topo_cpus_init()` +
  `fd_topob_auto_layout_cpus()` with Tickoni name arrays in priority slots

The adapter should follow Firedancer harness hooks, guards, ordering, and
failure semantics. If Tickoni replaces one of those pieces, the replacement
must preserve the same orchestration guarantee at the Tickoni boundary.

### Topology Builder Adapter

`fd_topob.c` is the real Firedancer topology builder — it is NOT Solana-shaped.
Tickoni calls it directly rather than maintaining a parallel builder. The adapter
pattern is:

1. **Build the topology:** `fd_topob_new(topo, "tickoni")` — allocates and
   `memset`-zeros the entire `fd_topo_t`, zeroing every field including Solana
   union fields (xdp, sock, gossip, quic, etc.).

2. **Create workspaces:** `fd_topob_wksp(topo, name)` declares workspace names.
   The supervisor then creates and joins them with normal-page backing (see
   [workspace-management.md](../knowledge/workspace-management.md)).

3. **Create links:** `fd_topob_link(topo, name, ...)` for each inter-tile link.

4. **Create tiles:** `fd_topob_tile(topo, name, wksp, metrics_wksp, cpu_idx)`
   for each Tile — the Zig wrapper exposes a 5-param signature. The C shim
   (`tk_topob_tile` in `shim/topob.c`) forwards to the upstream 8-param
   `fd_topob_tile` with the 3 Solana flags hardcoded as `0`
   (`is_agave`, `uses_id_keyswitch`, `uses_av_keyswitch`). This is
   transparent to Zig callers — they only pass 5 args. The shim is the
   single point where Tickoni's contract diverges from upstream.

5. **Wire links:** `fd_topob_tile_in(topo, tile_idx, link_idx, ...)` and
   `fd_topob_tile_out()` to attach each link to its tile.

6. **Validate:** `fd_topob_finish(topo)` runs structural validation (free check,
   link connectivity, workspace coverage) — pure generic, no Solana dependency.

7. **CPU placement:** `fd_topo_cpus_init()` → `fd_topob_auto_layout_cpus()`
   assigns each tile to a CPU core using priority phase arrays. The 4 arrays
   (`CRITICAL_TILES[]`, `ALWAYS[]`, `STARTUP[]`, `FLOATING[]`) are the only
   Solana-specific part — they contain hardcoded tile name strings matched
   against `fd_topo_tile_t.name` via `strcmp`. Tickoni replaces these arrays
   with Tickoni tile names:

   ```c
   // Patched in fd_topob.c — CRITICAL (no HT sharing)
   static char const * CRITICAL_TILES[] = {
     "pack", "poh", "pohh", "gui", "guih",
     "tkings", "tknorm",
     NULL
   };

   // Patched — ALWAYS (continuous pipeline)
   static char const * ALWAYS[] = {
     "backt", "benchg", "net", "sock", "quic", "bundle",
     "verify", "dedup", "pack", "sign", "shred", "pktgen",
     "tkdedu", "tkpoly", "tkaudt",
     NULL
   };

   // Patched — FLOATING (monitoring, kernel-scheduled)
   static char const * FLOATING[] = {
     "netlnk", "metric", "diag", "bencho",
     "tkmetr", "tkdiag", "tkdisp",
     NULL
   };
   ```

   The algorithm (`fd_topo_cpus_init` → `auto_tile_cpu` → `auto_layout_cpus`)
   is fully generic: NUMA-aware core scanning, hyperthread-pair exclusion for
   latency-sensitive tiles, 4-phase priority ordering, and "floating" fallback
   for unmatched tiles (logged as warning, left to kernel scheduler). Only the
   name strings change.

8. **Launch:** Pass `topo` and `topo->tiles[]` to `fd_topo_run_tile()` — the
   harness joins workspaces, fills link pointers, enters sandbox, runs the tile,
   and checks shutdown state.

**Why `0` for Solana flags is safe:** `fd_topob_new()` does `memset(topo, 0)`,
so all Solana union fields in `fd_topo_t` are already zero. The launch path
(`fd_topo_run_tile` in `fd_topo_run.c` lines 49–140) reads only `name`,
`kind_id`, `cpu_idx`, `allow_shutdown`, and `metrics` — none are Solana union
fields. `fd_topo_run_single_process()` reads `is_agave` (lines 326, 335) but
Tickoni uses per-process `execve` mode, not single-process mode.

**Keyswitch objects (the 3 params):** Each keyswitch is a 128-byte shared memory
object with a state machine: `SWITCH_PENDING` → tile reads new bytes →
`COMPLETED` or `FAILED`. While Solana uses these for validator identity/authority
key rotation, the mechanism is generic and can be repurposed for Tickoni:
GCP/GCS OAuth tokens, AWS credential rotation, LLM provider API keys, or
adapter secrets stored in `bytes[64]`. For Phase 0 tiles that need no runtime
auth rotation, pass `0` and no keyswitch object is allocated.

### Interface Symmetry Between Harnesses

The Tickoni topology harness (`src/tickoni/runtime/topo_build.zig`) intentionally
mirrors the Firedancer harness call sequence **1:1** — same methods, same order,
same placeholder convention — so that side-by-side code review and comparison
are trivial. When Firedancer upstream introduces an improvement to its topology
harness, the Tickoni harness maps directly to it without needing to understand
the divergence.

This deliberate redundancy is a maintainability investment, not a flaw. The
goal is that a developer reading both harness files can follow the same
narrative line: create topology → create workspaces → create links → create
tiles → wire links → set CPU placement → finish → validate. The only
difference is **how** each harness determines cpu_idx for each tile:

| Step | Firedancer harness (`topology.c`) | Tickoni harness (`topo_build.zig`) |
|------|----------------------------------|------------------------------------|
| Build | `fd_topob_new(topo, name)` | `topobNew(buf.ptr, app_name)` |
| Workspace | `fd_topob_wksp(topo, name)` | `topobWksp(topo, name)` | Real creation handled by supervisor (see [workspace-management.md](../knowledge/workspace-management.md)). |
| Links | `fd_topob_link(topo, name, ...)` | `topobLink(topo, name, ...)` |
| Tiles | `fd_topob_tile(topo, name, wksp, metrics, 0, 0, 0, 0)` | `topobTile(topo, name, wksp, wksp, 0)` |
| CPU layout | `fd_topob_auto_layout(topo, 0)` | `topobAutoLayout(topo, cpu_idx_arr)` |
| Finish | `fd_topob_finish(topo, callbacks)` | `topobFinish(topo)` |

The `0` passed to `fd_topob_tile()` and `topobTile()` is a placeholder — not
the final cpu assignment. The Firedancer harness overwrites `tile->cpu_idx`
later in `fd_topob_auto_layout()` from its hardcoded priority arrays. The
Tickoni harness overwrites it in `tk_topob_auto_layout()` from the
`cpu_idx_arr` that the harness computed from `CpuPlacement` enum values
(`exclusive = N`, `shared = N`, `floating`). The placement source differs,
but the **harness contract is identical**: create with placeholder → lay out
CPUs → finish.

The shim's `tk_topob_auto_layout(topo, cpu_idx_arr)` iterates `topo->tiles[]`
and writes `tile->cpu_idx = cpu_idx_arr[i]` for each tile. This mirrors
Firedancer's `fd_topob_auto_layout(topo, 0)` which iterates tiles and assigns
from priority arrays. The internal data source is different (harness-provided
array vs. hardcoded C arrays), but the **interface shape is identical**:
a single `auto_layout` call after tile creation, before `finish`.

This matters for porting: when Firedancer changes `fd_topob_auto_layout()` to
support NUMA-aware groupings or dynamic CPU allocation, the Tickoni harness
already calls an identically-named wrapper at the identically-positioned
harness step. The shim absorbs the implementation difference; the harness does
not need to change.

**What changes in upstream `fd_topob.c`:** Only the 4 name arrays get Tickoni
tile names appended. No logic changes, no new functions, no struct modifications.
The file set is tracked by `engine-check-changes` to catch any upstream drift.

### C ABI Substrate

Tickoni-owned Zig code crosses into Firedancer or vendored C only through
Tickoni-owned `tk_*` shims and Zig wrappers under `src/tickoni/c_abi/**`.

Current and expected substrate categories include:

- Tango queues and control state:
  `mcache`, `dcache`, `fseq`, `cnc`, and, where justified, `fctl` and `tempo`
- workspace and shared-memory mechanics
- sandbox primitives on Linux
- low-level metrics/diagnostics mechanics or patterns
- Ballet protobuf/hash primitives and vendored JSON where Tickoni deliberately
  reuses them

The C ABI is not a place for financial policy, product topology, capability
rules, adapter authority, or audit/replay semantics.

#### Harness Architecture (from audit 8.md)

The Firedancer harness `src/disco/topo/fd_topo_run.c` exposes a single entry
(`fd_topo_run_tile`) that implements a 3-layer tile lifecycle. Tickoni mirrors
this with `tile_process.zig` through the c_abi bridge:

```text
┌─────────────────────────────────────────────────┐
│  Tickoni tile_process.zig (our harness)         │
│  - self-exec supervisor                         │
│  - join wksp → privileged_init → sandbox        │
│  - join mcache/dcache/cnc/fseq/fctl/tempo       │
│  - unprivileged_init → work loop                │
│  - heartbeat/halt loop                          │
└─────────────────────────────────────────────────┘
                          │ calls through c_abi bridge
┌─────────────────────────────────────────────────┐
│  c_abi bridge (src/tickoni/c_abi/)              │
│  - wksp.zig    + shim/wksp.c      → fd_wksp_*  │
│  - dcache.zig  + shim/tango.c     → fd_dcache_*│
│  - fseq.zig    + shim/tango.c     → fd_fseq_*  │
│  - fctl.zig    + shim/tango.c     → fd_fctl_*  │
│  - tempo.zig   + shim/util.c      → fd_tempo_* │
│  - cnc.zig     + shim/tango.c     → fd_cnc_*   │
│  - queue.zig                                         │
│  - boot.zig      + shim/ballet.c  → fd_boot/     │
│  - sandbox.zig   + shim/sandbox.c → fd_sandbox   │
│  - topo_run.zig  (fd_topo_run_tile)                │
│  - topob.zig     (fd_topob_* topology builder)    │
│                                                 │
│  NEW additions needed:                          │
│  - metrics.zig + shim/tango.c → fd_metrics_*    │
└─────────────────────────────────────────────────┘
                          │ links against
┌─────────────────────────────────────────────────┐
│  Firedancer infrastructure (unchanged)          │
│  src/tango/{mcache,dcache,fseq,cnc,fctl,tempo}  │
│  src/util/{sandbox,util}                        │
│  src/disco/metrics                              │
└─────────────────────────────────────────────────┘
```

The diagram shows that Tickoni only needs to add 1 Zig wrapper + shim
(`metrics`) to cover the full Firedancer substrate used by the harness.
No structural changes to Firedancer are required.

The c_abi bridge also includes `topo_build.zig` and `topology_spec.zig`,
which are not adapter modules themselves but core orchestration components:

- **`topo_build.zig`** (`src/tickoni/runtime/topo_build.zig`): builds a real
  Firedancer `fd_topo_t` from Tickoni's own `Topology` by calling through
  `c_abi.topob`'s `fd_topob_*` wrappers. Called identically by the supervisor
  (parent) and each self-exec'd tile process (child) to rebuild an identical
  topology — the "topology handoff" pattern (V2.14.S8.T12). Returns
  `BuiltTopo` with allocated `buf`, opaque `topo`, workspace index, per-tile
  `cnc_obj_id[]`, and per-channel `link_obj_id[]` (mcache/dcache/fseq).
  Does not create the workspace or instantiate object content — that is the
  caller's job via `topobCreateWorkspace`/`topoWkspNew` (parent-only, once).

- **`topology_spec.zig`** (`src/tickoni/runtime/topology_spec.zig`): small
  serialized wire format (magic `0x544b5453` / "TKST", version 1) for
  passing topology between parent and child processes. `TopologySpec`
  carries tile ids, CPU placements, channel src/dst/depth/mtu, and workspace
  name. `fromTopology()` converts a runtime `Topology` into the wire format;
  `toTopology()` reconstructs it. File I/O includes magic/version validation
  and fail-closed on truncation. Parent writes once; each child reads,
  rebuilds an identical `fd_topo_t`, and finds its own tile index in it.

- **`cpu_placement.zig`** (`src/tickoni/runtime/cpu_placement.zig`): implements
  the Tickoni CPU placement model with `CpuPlacement` enum variants
  `exclusive`, `shared`, and `floating`, plus `validateStatic()` that enforces
  exclusive collision detection and shared/exclusive co-existence rules.

#### 11-Item Reuse Categorization (from audit 8.md)

Firedancer infrastructure decomposes into 11 reuse categories. The first 4
require only `tk_*` shims (already covered or trivial). The remaining 7
require deliberate Tickoni implementation or are explicitly not reused:

1. **`fd_topo_run_tile` harness** — reuse the Firedancer lifecycle (harness)
   by wiring a minimal `fd_topo_run_tile_t` through the adapter. The `tile_process.zig`
   path is equivalent and may be used instead when harness reuse proves too
   expensive.

2. **Topology arrays** — `fd_topo_tile_t[32]`, `fd_topo_link_t[256]`,
   `fd_topo_wksp_t[4]` — the array-based topology is a direct match for Tickoni's
   link-array model. The harness reads `name`, `kind_id`, `cpu_idx`,
   `allow_shutdown`, `metrics` — no Solana union fields touched.

3. **`fd_topo_run_single_process`** — single-process mode for testing, not for
   Linux full-runtime. Use when testing topology without process launch.

4. **`generate_filters.py`** — Firedancer's CPU placement script. **Resolved: the
   script is topology-independent.** It reads `topology_name`, `topology_path`,
   `tile_name`, `cpu_layout_file`, and `output_file`. It does not import
   Firedancer types. It can be used as-is and is not part of the Firedancer API
   surface.

5. **Tile registry** — `fd_topo_run_tile_t` serves as a per-tile registry. Tickoni
   implements this in `src/app/tickoni/tile_registry.zig` (not `topology.zig`).
   The registry is keyed by tile ID and owns: thread-mode run callback
   (`RunFn`), process-mode run callback (`ProcessFn`), counter schema
   (`CounterSchemaEntry`), expected link cardinality (`in_cnt`/`out_cnt`),
   and diagnostics naming. Beyond lookup and cardinality, the registry also
   owns **process-mode dispatch wiring** (link-joining shape per tile — each
   process-mode entry function joins the correct consumer/producer links and
   calls into the pipeline stage) and **topology-bijection validation**
   (`validate()` checks that every topology tile is registered, every
   registered tile appears in the topology, and per-tile channel counts match
   the registry). No supervisor, process dispatcher, metrics reader, or test
   harness should recreate these mappings.

6. **Heartbeat semantics** — `cnc_update` / `FD_CNC_HEARTBEAT` — the pattern is
   proven; Tickoni's `tile_process.zig` already implements heartbeat during work.

7. **Shutdown semantics** — `cnc` shutdown flag checked inside tile work loop,
   not only outside — preserved in Tickoni.

8. **Crash-only lifecycle** — crash teardown follows Firedancer semantics via
   `fd_stem` teardown, but Tickoni implements this in `tile_process.zig`, not
   through `fd_stem`. The crash teardown pattern is preserved.

9. **Stem loop (multi-input multiplexer)** — **NOT REUSED.** `fd_stem.c` is a
   multi-input callback multiplexer with credit/burst accounting tied to Solana
   validator tile semantics. Tickoni implements its own single-input bounded
   polling per tile.

10. **Supervisor (fork+exec + wait4)** — **NOT REUSED.** `run.c`/`run1.c` manage
    PID namespaces, seccomp, and process lifecycle. Tickoni's `supervisor.zig`
    owns this independently.

11. **Metrics (fd_metrics_*)** — reuse Firedancer metrics primitives through a
    new `metrics.zig` wrapper + shim, similar to the queue wrappers. The
    infrastructure is clean (Firedancer-owned, no Solana semantics).

#### fd_topo_run.c Audits (from v2.14.s8-wip.md)

The following concrete findings were verified during audit S8:

- **fd_topo_run_tile has zero fd_topob references:** confirmed via `nm`
  inspection of `libfd_disco.a` — no `fd_topob_*` symbols are called from the
  harness. The harness is standalone with respect to the topology builder.
- **fd_topo_run_single_process is the only fdctl coupling:** it is the single
  file in `src/disco/topo/` that includes `src/app/shared/commands/run/run1.c`.
  This is the only cross-boundary dependency between the harness and fdctl.
  Mitigated by Tickoni's per-process execve model (not single-process mode).
- **generate_filters.py is topology-independent:** it takes
  `topology_name`, `topology_path`, `tile_name`, `cpu_layout_file`,
  `output_file` as CLI arguments. No Firedancer types are imported. It can be
  used as-is.
- **fd_topo_run_tile can be called without fd_topob.c:** the harness does not
  depend on the topology builder. Topology can be constructed independently and
  passed to `fd_topo_run_tile`.
- **Key switch uses 128B union fields:** confirmed from header inspection.
  Solana union fields are zeroed by memset, which is safe for Tickoni.
- **fd_topo_run.c has zero fd_topob calls:** confirmed via grep. The harness
  uses `fd_topo_cnc_fseq_init` from `fd_topo.c`, but this is the shared
  infrastructure file — not the builder.

#### fd_topob.c Usability (from v2.14.s8-wip.md)

`fd_topob.c` is a generic topology builder that is usable for Tickoni:

- **fd_topob_new()** — memset to zero, sets app_name. **No Solana.**
- **fd_topob_wksp()** — generic workspace declaration. **No Solana.**
- **fd_topob_link()** — creates link entry, mcache/dcache objects. **No Solana.**
- **fd_topob_tile()** — creates tile entry. Takes `is_agave`, `uses_id_keyswitch`,
  `uses_av_keyswitch` as int params. Pass `0` for all three. **Only Solana touch:
  3 trivial int params.**
- **fd_topob_tile_in()/fd_topob_tile_out()** — generic link wiring. **No Solana.**
- **fd_topob_finish()** — structural validation (workspace uniqueness, link
  reachability, no duplicates, no self-loops). **No Solana.**
- **fd_topob_auto_layout()** — hardcodes Solana tile name arrays (`FLOATING[]`,
  `STARTUP[]`, `ALWAYS[]`, `CRITICAL_TILES[]`). **Solana names only.** The
  algorithm (NUMA scanning, HT-pair exclusion, 4-phase priority ordering) is
  generic and should be reused with Tickoni tile groups.

**Verdict:** Use fd_topob.c with 3 params set to 0, 2 functions reimplemented
with Tickoni names. Extract and reuse the CPU placement algorithm as-is. No
Solana semantics leak into Tickoni product code.

#### Structural Resolutions (from v2.14.s8-wip.md)

The following structural tensions were identified during S8 planning and have
been resolved:

1. **Scope too large for one story:** S8's 10 tasks span registry, links, c_abi
   bridge, lifecycle migration, sandbox/seccomp, stuck-tile detection, parent-path
   investigation, and engine drift guard. Resolved by splitting: S8 handles the
   core tasks, T11 handles tempo/fctl shims.

2. **tile_process.zig stays as product code:** The tension was whether to replace
   tile_process.zig's hand-rolled loop with fd_topo_run_tile. Resolution: keep
   tile_process.zig as the product-level self-exec boot/heartbeat/halt loop.
   The adapter layer (in the Linux full-runtime adapter) may optionally call
   fd_topo_run_tile, but tile_process.zig itself remains a product tile
   lifecycle implementation, not the adapter.

3. **tempo/fctl shims explicitly scoped:** Audit 8's plan requires them for
   proper stuck-tile defense. Resolved as V2.14.S8.T11.

4. **Seccomp policy generation risk resolved:** generate_filters.py is
   completely topology-independent. Input is a flat .seccomppolicy text file;
   output is a standalone C header. No topology context needed.

### Patterns

Tickoni also reuses Firedancer orchestration patterns even where the exact C
implementation is not used:

- topology owns graph cardinality
- tile registry is the single answer for what a tile id does
- input and output links are arrays, not one-off fields
- shutdown is checked inside tile work, not only outside it
- heartbeat and health are updated during work/housekeeping
- reliable links backpressure or fail closed instead of silently dropping
- crash-only behavior keeps failure handling explicit
- operator diagnostics must identify which tile, workspace, link, and process
  is unhealthy

## What Tickoni Owns

Tickoni owns all product and framework semantics above the generic engine
layer.

### Tile Identity

Tickoni tile identities are product topology concepts, not aliases for
validator tiles. The canonical tile ID list and tile responsibility table live
in [`tile-topology.md`](tile-topology.md). This document uses those IDs only to
describe orchestration behavior.

### Topology And Links

Tickoni topology owns:

- which Tickoni tiles exist in a product topology
- tile instance ids and logical names
- channel direction
- channel backing
- depth, MTU, reliability, and overrun behavior
- workspace ownership
- input and output link cardinality
- CPU placement policy at the Tickoni support tier

Topology is the graph. Bootstrap records are not the graph.

Process boot may carry identity and minimal startup data, but the topology is
the source of truth for link cardinality and link ownership. Fan-in and fan-out
are represented as per-tile link arrays:

```text
tile
  in_cnt
  in_link_id[]
  out_cnt
  out_link_id[]
```

A single-link launch field is not a valid long-term representation of Tickoni
topology. It can exist only as a compatibility lane for a topology that is
explicitly validated as linear.

### Registry

The tile registry is the single product-facing answer to:

- this tile id's logical name
- supported runtime tiers
- thread/dev run callback, if any
- Linux full-runtime run callback or adapter entry, if any
- process/retail run callback, if any
- expected link cardinality
- counter/metric schema
- diagnostics naming

No supervisor, process dispatcher, metrics reader, or test harness should
recreate tile identity mappings independently.

### Financial Correctness

Tickoni owns the financial correctness layer:

- capability envelopes
- policy outcomes
- destination, account, rail, venue, market, sector, instrument, amount,
  exposure, frequency, holding-period, environment, and approval dimensions
- audit records and hash chaining
- evidence references
- replay substitution
- model/tool/adapter routing
- approved execution authority

These contracts must not be represented as Firedancer topology fields.

## Linux Full-Runtime Adapter Contract

The Linux full-runtime adapter is allowed to know about Firedancer topology and
run types. It is the only layer that may translate from Tickoni descriptors to
Firedancer-compatible structures.

The adapter owns:

- mapping Tickoni topology into the minimal Firedancer topology/run surface
  required by the reused harness code
- mapping Tickoni tile registry entries into Firedancer-style tile run
  descriptors
- mapping Tickoni link descriptors into Firedancer link arrays and link
  backing objects
- mapping Tickoni placement policy into supported Linux placement behavior
- preserving Firedancer lifecycle ordering and failure semantics
- reporting adapter-private failures through Tickoni diagnostics

The adapter does not own:

- financial event schemas
- policy semantics
- audit schemas
- replay capsule semantics
- model/tool/adapter authority
- operator approval behavior
- public product topology vocabulary

If the adapter needs fake or unrelated validator values to satisfy Firedancer
structures, those values are adapter-private compatibility fields. They must
not become Tickoni product concepts.

## Retail Runtime Contract

macOS and Windows retail runtimes implement the same Tickoni orchestration
boundary but are not expected to provide Linux-equivalent engine guarantees.

Retail runtimes may support:

- deterministic paper/sandbox demos
- policy decisions over fixtures
- audit JSONL output
- replay proof
- CaseOps review of supported demo artifacts
- mocked, fixture-backed, or replay-substituted model/tool/adapter effects

Retail runtimes must fail closed for unsupported behavior:

- live trading
- live payment or transfer execution
- Ledger writes
- direct model-provider bypass
- direct adapter bypass
- privileged execution
- unsupported sandbox or isolation claims

Target-specific bridges decide at compile/link time whether a `tk_*` symbol is:

- Linux-Firedancer
- portable-Firedancer
- Tickoni substitute
- unsupported/fail-closed
- decision-needed

Runtime checks remain necessary for operator diagnostics, but they are not
sufficient when a Firedancer symbol cannot compile or link on the target.

## Health, Shutdown, And Crash Semantics

Every runtime tier must expose enough health information to answer:

- which tile is running, halted, failed, or stale
- which process/thread owns that tile
- which workspace or allocation backs its state
- which links it consumes and produces
- which heartbeat or health timestamp is advancing
- whether shutdown was requested and observed
- whether a failure was crash-only, clean halt, unsupported tier, or startup
  validation failure

Linux full-runtime tiles should preserve Firedancer-style lifecycle behavior:

- heartbeat or equivalent health state advances during work
- shutdown is checked inside tile loops and waits
- reliable consumers/producers do not block forever without a visible stale
  health state
- one tile crash is visible to the supervisor
- crash-only policy tears down or marks the topology according to the selected
  support-tier semantics

Retail runtimes must expose degraded guarantees explicitly. If they cannot
provide process isolation, namespace sandboxing, CPU pinning, or shared-memory
equivalence, the missing guarantee is part of the runtime tier and must be
visible in diagnostics and evidence.

## Orchestration Drift Guard

The Linux adapter depends on Firedancer harness behavior staying understood.
Tickoni should maintain a watched Firedancer harness file set and a repo gate
that detects changes relative to the previous commit. The intended command is:

```text
just engine-check-changes
```

That gate belongs in `just tests-all` once implemented. It should force human
review or explicit acknowledgement when watched harness files change.

The initial watched set is:

- `src/disco/topo/fd_topo_run.c`
- `src/disco/topo/fd_topo.h`
- `src/disco/topo/fd_topo.c`
- `src/disco/stem/fd_stem.c`
- `src/app/shared/commands/run/run.c`
- `src/app/shared/commands/run/run1.c`
- `src/app/shared/boot/fd_boot.c`
- `src/util/sandbox/fd_sandbox.c`
- `src/util/sandbox/fd_sandbox.h`
- `src/util/sandbox/fd_sandbox_private.h`
- `src/disco/metrics/fd_metrics.c`
- `src/disco/metrics/fd_metrics.h`
- `src/disco/metrics/fd_metrics_base.h`

The list is conservative and may be refined when the Linux adapter's exact
dependency surface is known. The guard does not freeze Firedancer. It prevents
silent drift in orchestration semantics Tickoni relies on.

## Non-Negotiable Boundaries

- Do not rename or repurpose Solana validator tiles as Tickoni tiles.
- Do not add Tickoni product fields to upstream Firedancer topology structs.
- Do not encode financial policy or approval behavior in orchestration
  bootstrap state.
- Do not treat Markdown, the analytics store, the approved execution ledger, model providers, or financial
  adapters as direct dependencies of the orchestration layer.
- Do not let agents, UI, model tiles, tool brokers, adapters, or future
  execution paths bypass `tkpoly`, `tkaudt`, and replay boundaries.
- Do not claim macOS or Windows Linux-equivalent isolation, performance, or
  shared-memory behavior without explicit support-tier evidence.

## Summary

Tickoni's orchestration architecture is a boundary decision:

```text
Tickoni owns the product topology and financial semantics.
Firedancer powers the Linux full-runtime implementation where reusable.
Retail runtimes implement the same Tickoni boundary with explicit guarantees.
```

The architecture should make it hard to accidentally rebuild Firedancer in
parallel, and equally hard to let Firedancer validator semantics leak into
Tickoni's financial product model.

## Related Docs

- [Tile Topology](tile-topology.md) — tile IDs, link shapes, workspace mapping modes, reuse/exclude table
- [Workspace Management](workspace-management.md) — workspace lifecycle, backing strategy, the Firedancer vs Tickoni divergence, object callbacks
- [Architecture](architecture.md) — system layers, Firedancer infrastructure reuse boundary
- [Auth Tiles](auth-tiles.md) — keyswitch objects (same topology infrastructure, no workspace coupling)
