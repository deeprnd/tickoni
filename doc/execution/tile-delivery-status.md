# Tile Delivery Status

Architecture, tile inventory, reuse boundaries, topology design, runtime IDs,
and event flow are in
[`doc/knowledge/tile-topology.md`](../knowledge/tile-topology.md).

## Product Boundary

Status: complete for the current boundary.

Tile-relevant facts:

1. `src/app/tickoni/` and `src/tickoni/` exist.
2. The Zig supervisor starts a Tickoni-only topology in dev/test mode.
3. Narrow C ABI declarations exist for selected queue and sandbox primitives.
4. The current in-process spike maps tiles to threads and heap-backed queues.
5. The temporary `firedancer -> tickoni` compatibility behavior remains outside
   the product tile topology until the deprecation window in
   [`roadmap/epics/v1.11.md`](../strategy/roadmap/epics/v1.11.md) is complete.

## Current Topology

Status: complete as an in-process tile spike.

Implemented topology:

```text
tkings -> tknorm -> tkdedu -> tkpoly -> tkaudt
tkrepl
tkmetr
tkdiag
```

Implemented in
[`src/tickoni/tiles/payment_pipeline/`](../../src/tickoni/tiles/payment_pipeline/),
with supervisor wiring in
[`src/app/tickoni/supervisor.zig`](../../src/app/tickoni/supervisor.zig) and the
static topology in
[`src/tickoni/runtime/topology.zig`](../../src/tickoni/runtime/topology.zig).

Tile behaviors proven by the current topology:

1. `tkings` owns synthetic source offsets and ingress backpressure.
2. `tknorm` owns canonical payment normalization and malformed-event rejection.
3. `tkdedu` owns idempotency and content-hash duplicate memory.
4. `tkpoly` owns allow, deny, malformed-drop, and duplicate-drop decisions.
5. `tkaudt` owns append-only audit ordering and hash chaining.
6. `tkrepl` owns deterministic replay comparison with external effects disabled.
7. `tkmetr` owns runtime metric snapshots.
8. `tkdiag` owns crash, sandbox, audit, and replay diagnostics.

The Firedancer-style topology answers for current links are:

| Link | Owner tile | Backing allocation | Mapping mode | Depth / MTU | Reliability | Overrun, restart, shutdown | Metrics and diagnostics |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `tkings -> tknorm` | `tkings` owns source offsets and writes the link; `tknorm` owns framing rejection. | Heap-backed bounded SPSC ring in `PaymentPipelineState`; future shared-memory workspace. | Single producer writes; single consumer reads; in-process thread mapping for spike. | 64 entries / 128-byte payment envelope. | Reliable until shutdown; producer backpressures when full. | Overrun increments wait pressure instead of dropping; restart regenerates from source offset; shutdown closes the link. | Produced, invalid, max depth, backpressure waits, latency hops, crash tile. |
| `tknorm -> tkdedu` | `tknorm` owns canonical hash generation and malformed-drop decisions. | Heap-backed bounded SPSC ring in `PaymentPipelineState`; future shared-memory workspace. | Single producer writes normalized events or malformed-drop envelopes; single consumer reads. | 64 entries / 128-byte normalized event. | Reliable until shutdown. | Overrun backpressures normalization; restart recomputes stable hashes; shutdown drains then closes. | Normalized count, malformed-drop count, queue depth, waits, latency hops. |
| `tkdedu -> tkpoly` | `tkdedu` owns idempotency key and content-hash memory. | Heap-backed bounded SPSC ring plus `tkdedu`-owned seen-key arrays. | Single producer writes dedupe decisions; single consumer reads. | 64 entries / 128-byte decision input. | Reliable until shutdown. | Overrun backpressures dedupe; restart rebuilds seen-key state from source order; shutdown drains then closes. | Duplicate count, queue depth, waits, latency hops. |
| `tkpoly -> tkaudt` | `tkpoly` owns policy decision; `tkaudt` owns final ordering. | Heap-backed bounded SPSC ring in `PaymentPipelineState`; future audit workspace. | Single producer writes policy envelopes; single consumer appends. | 64 entries / 128-byte audit envelope. | Reliable until shutdown. | Overrun backpressures policy; restart re-evaluates policy version; shutdown drains then closes. | Allow, deny, duplicate-drop, audited count, queue depth, waits, latency hops. |
| `tkaudt` audit log | `tkaudt` owns append-only sequence and hash chain. | Heap-backed fixed audit record array; future append-only file or shared audit workspace. | Only `tkaudt` writes; replay reads after audit completion. | Capacity equals configured event count. | Reliable; full audit allocation is a crash condition. | Full allocation marks `tkaudt` crashed and stops the runtime; restart replays from source facts; shutdown preserves completed records in memory for replay. | Audited count, audit hash, replay divergence, latency hops, crash tile. |
| `tkrepl` replay path | `tkrepl` owns replay comparison and external-effects-disabled mode. | Reads completed audit records and regenerates deterministic synthetic events. | Replay reads audit after `tkaudt` signals completion; no producer mutates audit during compare. | Same event envelope as the main path. | Reliable comparison; reports divergence instead of mutating state. | Replay never invokes external effects; mismatch increments divergence count; shutdown exits after comparison or crash signal. | Replay checked, replay match, divergence count. |
| `tkmetr` telemetry | `tkmetr` owns metric snapshots. | Atomic counters and queue-watermark reads in `PaymentPipelineState`. | All tiles publish counters; `tkmetr` reads snapshots. | No correctness queue in the spike. | Observational; future telemetry may be lossy with counted drops. | Shutdown takes a final snapshot. | Produced, normalized, invalid, duplicates, allowed, denied, audited, depth, waits, max latency hops. |
| `tkdiag` diagnostics | `tkdiag` owns diagnostic snapshots. | Atomic crash, sandbox, audit, and replay fields in `PaymentPipelineState`. | Tiles publish diagnostics; `tkdiag` reads snapshots. | No correctness queue in the spike. | Observational; crash state is reliable. | Sandbox failure marks the owning tile crashed and requests runtime stop; shutdown takes a final snapshot. | Sandbox failures, crashed tile, audit count, replay status. |

### Cross-Platform Shmem and Workspace Shim (V2.10.S15)

Story V2.10.S15 extended the workspace shim layer to macOS and Windows:

| Platform | Shim file | Shmem backend | Tile launcher | Notes |
| --- | --- | --- | --- | --- |
| Linux | `wksp.c` (POSIX block) | POSIX `shm_open`/`mmap` | `topo_run_platform_linux.c` | Native shmem; `fd_wksp_*` passthrough |
| macOS | `wksp.c` (POSIX block) | POSIX `shm_open`/`mmap` | `topo_run_platform_macos.c` | Darwin `_NSGetExecutablePath`, `pthread_setname_np` |
| Windows | `wksp.c` (Windows block) | Firedancer `CreateFileMapping` | `topo_run_platform_windows.c` | Replaces previous ENOTSUP stubs; `WaitForSingleObject` process poll |
| Fallback | `wksp.c` (no block) | N/A | N/A | Stub returns for test contexts |

The shared header `topo_run_platform_common.h` provides `tk_initialize_logging()` used by all three platform launcher files, eliminating ~33 lines of duplicated logging setup.

Fail-closed: on stub failure the workspace shim returns -1/-2/0/null; the supervisor logs errors and tile boot fails gracefully. This is the expected blocked flow — the shim layer is in place but Firedancer's native shmem backend may still return -ENOTSUP.

Before the topology leaves the in-process spike, replace the heap-backed rings
with the selected shared-memory queue backing and keep these link answers
current:

1. owner tile
2. workspace or backing allocation
3. producer and consumer mapping mode
4. queue depth and MTU
5. reliable or unreliable behavior
6. overrun, restart, and shutdown behavior
7. queue, drop, latency, and crash metrics

## Execution Readiness Prerequisites

These prerequisites state which runtime guarantees must exist before later tile
classes are meaningful. They are not a product delivery schedule.

Step 1: deterministic financial event spine.

```text
configured event source
  -> tkings
  -> tknorm
  -> tkdedu
  -> tkpoly
  -> tkaudt

replay capsule -> tkrepl -> deterministic pipeline with tkexec disabled
all tile metrics -> tkmetr
```

Step 2: deterministic case and evidence scope.

```text
tkcase
tkevid
all boundary events -> tkaudt
```

Step 3: bounded agent, model, tool, and adapter integration.

```text
tkdisp -> tkagnt -> tkmodl
tkagnt -> tktool -> tkadpt
```

Step 4: operator API and approved execution boundary.

```text
tkapi
tkexec
```

## Tile Synchronization Debt

Once the new product topology is canonical:

1. Remove validator tile registrations from the Tickoni product binary.
2. Remove Tickoni-only changes from upstream-owned Firedancer files where the
   new app makes them unnecessary.
3. Delete Agave and Frankendancer code: `src/app/fdctl/`, `src/app/fddev/`, and
   `src/discoh/`.
4. Delete full Firedancer validator applications after the compatibility window:
   `src/app/firedancer/` and `src/app/firedancer-dev/`.
5. Delete Solana-only tile implementations from `src/disco/` and `src/discof/`,
   including consensus, TPU, shred, repair, replay, PoH, snapshot, validator
   RPC, validator GUI, bundle, and validator telemetry code.
6. Delete Solana runtime roots such as `src/choreo/`, `src/flamenco/`,
   `src/funk/`, `src/groove/`, `src/vinyl/`, and `src/wiredancer/` once no
   retained Tickoni substrate depends on them.
7. Keep only the dependency-proven substrate used by Tickoni, primarily
   `src/tango/`, selected `src/util/` code, and narrow wrappers around any
   retained topology, sandbox, metrics, or networking primitives.

Do not keep merging the complete Firedancer tree into the pruned product
branch. A whole-tree merge would turn upstream edits to intentionally deleted
files into modify/delete conflicts. Keep an unmodified Firedancer mirror branch
or external reference and selectively import reviewed substrate changes into
the retained Tickoni boundary.

## Completion Gate

The topology has the right shape when:

1. The canonical `tickoni` binary starts no Solana validator tiles.
2. Every Tickoni tile has a `tk*` runtime ID and a Tickoni-owned source path.
3. Agent workers have no direct shell or unrestricted network access.
4. Model access is isolated behind `tkmodl`.
5. Tool use is isolated behind `tktool` and converted into finance-native
   adapter or proposal requests before reaching signed `tkadpt` instances.
6. Financial capabilities enforce destination allowlists, amount/exposure
   limits, frequency limits, and approval state according to
   [`capabilities.md`](../strategy/capabilities.md).
7. Privileged accounting ledger posting, money movement, crypto transfer, and
   trading order placement are isolated behind disabled-by-default `tkexec`.
8. Every material event, denial, model call, adapter call, proposal, approval,
   destination/limit/frequency check, and external result is appended through
   `tkaudt`.
9. Replay can execute with external mutation disabled and report divergence.
10. Queue depth and backpressure are visible through `tkmetr`.
11. The validator mirror can be synchronized without editing Tickoni product
    tiles.
