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
| `tkings -> tkagnt` (agent topology) | The test-build request source in `tkings` owns the run ids and the fragment stream; `tkagnt` owns framing rejection, admission ordinals and routing. | Tango shared-memory workspace (per-run name); producer writes fragments and metadata. | One logical message (`TkAgentRequestHdr` + prompt) is a contiguous multipart stream (`tk_multipart_wire.h`): SOM/EOM, canonical offsets, whole-message hash. | 32 fragments / 8192 MTU (8128 payload, 256 KiB message ceiling, 33 fragments). | Reliable; a new message is held back (`BEFORE_FRAG` returns -1) while there is no free request slot or run entry, so nothing is dropped. | A malformed stream admits nothing and is counted; shutdown drains accepted work first. | `tkagnt` counters and `transport_dropped` (scratch accessor). |
| `tkmodl -> tkaudt` | `tkmodl` owns the model-call or denial record content; `tkaudt` owns ordering, chaining and hashing. | Same workspace. | `tkmodl` writes `ModelAuditMsg` with `sig` = record type (model_call or denial); `tkaudt` copies it into its next uncommitted slot. | 32 entries / 256 MTU (record is under 256 bytes, asserted in `c_abi/tkmodl.zig`). | Reliable. | As above; `tkmodl` publishes the audit record and the result from one `AFTER_FRAG` commit (`STEM_BURST` 2). | `tkaudt` committed record count and hash chain. |
| `tkagnt -> tkmodl[k]` | `tkagnt` owns dispatch; `tkmodl[k]` owns reassembly, governance and the prompt hash (computed from the bytes it receives). | Same workspace. | Multipart `ModelRequestMsg` + prompt, one stream per request, one request in flight per instance. | 32 fragments / 8192 MTU. | Reliable. | A stream that fails reassembly is dropped whole and counted; no governance, audit or result is produced for it, and the agent's model deadline ends the run in an audited terminal failure. | `tkmodl` `dropped`, `tkagnt` `dispatched`. |
| `tkmodl[k] -> tkagnt` | `tkmodl[k]` owns the result; `tkagnt` owns correlation and interpretation. | Same workspace. | Multipart `ModelResultMsg` + captured response bytes. The audit record is published first, then the result fragments over successive stem iterations; input polling pauses while a result is being sent. | 32 fragments / 8192 MTU. | Reliable. | An unknown, duplicate, stale, wrong-instance or wrong-model result completes nothing and is counted (`mismatched`); a corrupt or incomplete stream ends the run it answered in a transport failure. | `tkagnt` `results`, `mismatched`. |
| `tkagnt -> tkaudt` | `tkagnt` owns the terminal agent record (proposal or denial) and publishes in admission order; `tkaudt` owns ordering and the chain. | Same workspace. | One-fragment `TkAgentAuditMsg`, hashes and attribution only. `tkaudt` holds model records until the agent record for the same ordinal arrives and commits model-then-agent per ordinal. | 32 entries / 512 MTU. | Reliable. | A late, duplicate or out-of-order record is refused and counted, never reordered; held records are bounded at 64. | `tkaudt` `rejected`, `held_*`. |
| `tkaudt` committed-order watermark | `tkaudt` writes (single writer); `tkagnt` reads. | One `fseq` object in the app workspace, created by `topo_build` when both tiles exist. | The last agent ordinal committed, published only after the record is appended and chained (`TK_AUDIT_WATERMARK_NONE`, the 64-bit all-ones value, before the first; not C `ULONG_MAX`, which is only 32-bit on Windows). `tkaudt` stays a sink. | n/a | n/a | `tkagnt` publishes a run's terminal result only once the watermark has reached its ordinal. | Watermark value (shared memory). |
| `tkagnt -> tkdisp` | `tkagnt` owns the terminal result; `tkdisp` (bounded sink) owns receipt. | Same workspace. | One-fragment `TkAgentResultMsg`: outcome, hashes, attribution; no content. | 32 entries / 256 MTU. | Reliable. | Published in admission order after the audit commit; on HALT every accepted request still gets one (completed or failed as shutdown). | `tkdisp` committed result count (scratch accessor). |
| `tkcase -> tkpoly`, `tkcase -> tkdisp` (full workflow) | `tkcase` (placeholder) owns forwarding; `tkpoly` and `tkdisp` own receipt. | Same workspace as every link of the run. | Each event is forwarded unchanged to both consumers; the producer back-pressures on the slower one. | 64 entries / 128 MTU. | Reliable. | A new event stays upstream while a consumer cannot take it; shutdown follows the event count, then HALT. | `tkdisp` events seen and requests scheduled (scratch accessors). |
| `tkdisp -> tkagnt` (full workflow) | `tkdisp` (scheduler) owns the request stream and run ids (event offset + 1); `tkagnt` owns framing rejection and admission. | Same workspace. | The same multipart `TkAgentRequestHdr` + prompt stream as `tkings -> tkagnt`, built from the dispatch template. | 32 fragments / 8192 MTU. | Reliable. | One request at a time; a full event queue backs events up to `tkcase`. | `tkdisp` requests scheduled; `tkagnt` admitted. |
| `tkagnt -> tktool -> tkadpt`, `tktool -> tkaudt`, `tkadpt -> tkaudt` (full workflow) | `tktool` and `tkadpt` (placeholders) own receipt; no tile publishes on them. | Same workspace. | Declared and bound only: no tool or adapter call and no tool or adapter audit record exists, and `tkaudt` does not audit a fragment that arrives on such an input. | 32 entries / 512 MTU (to `tkaudt`: 256). | Reliable. | Idle. | `tktool` and `tkadpt` consumed counts (scratch accessors; zero in a correct run). |
| `tkaudt` event-ordered chain (full workflow) | `tkaudt` owns the single hash chain; `tkpoly`, `tkmodl` and `tkagnt` own their records' content. | Same workspace. | One chain in event order: for event n, its payment (policy decision) record, then its model record (if any), then its agent record (owner decision, 2026-11-19). Payment records arrive in event order and agent runs are admitted in event order, so the n-th of each belong together. A payment record is left queued upstream (`BEFORE_FRAG` -1, nothing dropped) until the agent record of event n-1 is committed; an agent record is committed only after its event's payment record. Where there is no payment chain or no agent runs, records commit on arrival or by ordinal as before. | Payment link 64 / 128; agent audit link 32 / 512. | Reliable. | An event whose payment record never reaches `tkaudt` leaves its agent record held (fail closed; crash-only). Shutdown follows the event count: both the agent ordinals and the payment records. | `tkaudt` committed counts, held counts, refusals (scratch accessors). |
| `tkaudt` audit log | `tkaudt` owns append-only sequence and hash chain. | Heap-backed fixed audit record array; future append-only file or shared audit workspace. | Only `tkaudt` writes; replay reads after audit completion. | Capacity equals configured event count. | Reliable; full audit allocation is a crash condition. | Full allocation marks `tkaudt` crashed and stops the runtime; restart replays from source facts; shutdown preserves completed records in memory for replay. | Audited count, audit hash, replay divergence, latency hops, crash tile. |
| `tkrepl` replay path | `tkrepl` owns replay comparison and external-effects-disabled mode. | Reads completed audit records and regenerates deterministic synthetic events. | Replay reads audit after `tkaudt` signals completion; no producer mutates audit during compare. | Same event envelope as the main path. | Reliable comparison; reports divergence instead of mutating state. | Replay never invokes external effects; mismatch increments divergence count; shutdown exits after comparison or crash signal. | Replay checked, replay match, divergence count. |
| `tkmetr` telemetry | `tkmetr` owns metric snapshots. | Atomic counters and queue-watermark reads in `PaymentPipelineState`. | All tiles publish counters; `tkmetr` reads snapshots. | No correctness queue in the spike. | Observational; future telemetry may be lossy with counted drops. | Shutdown takes a final snapshot. | Produced, normalized, invalid, duplicates, allowed, denied, audited, depth, waits, max latency hops. |
| `tkdiag` diagnostics | `tkdiag` owns diagnostic aggregation: the latest fragment per pipeline tile, the observation of every tile's process, and the replay result it reads. | The 5 diagnostic links below (payment process topology only); every tile's metrics region (status, pid, and where it writes OS-level metrics); tkrepl's CNC app slots 0 and 1. The in-process spike's `PaymentPipelineState` fields remain the thread-mode runtime's. | Tiles publish diagnostics; `tkdiag` receives and aggregates them and watches the processes. | One fragment per processed event per producer; `tkdiag` keeps one per input. | Observational; best effort. A tile found dead is counted (and logged) by `tkdiag`; the supervisor still owns crash handling. | `tkdiag` stops on CNC HALT, or once tkrepl publishes `replay_checked`. A crashed producer publishes nothing, so its death is seen from its process and its `TILE_STATUS`, not from a fragment. | CNC slots 0 to 4 (tiles that died or reported a fault, tiles that died before they ran, tiles reporting, fragments accepted and rejected) and the `tkdiag` metrics kind at `/metrics`. |
| `tkings`, `tknorm`, `tkdedu`, `tkpoly`, `tkaudt` `-> tkdiag` (payment process topology) | Each producer owns its own diagnostic fragment (`shim/tk_diag_fragment.h`: cumulative counters of that tile only); `tkdiag` owns aggregation. | Tango shared-memory workspace `tkpay0`, links appended after the pipeline links so each is its producer's last output. | One fragment per processed event, single producer, single consumer (`tkdiag`). All five stem tiles use `fd_stem_publish`: `tkings` in `AFTER_CREDIT`, the four consumers in `AFTER_FRAG`. | 64 entries / 128-byte fragment. | **Unreliable** (`LinkReliability.lossy`): the consumer is wired unreliable, so a producer never waits on `tkdiag`. | The producer overwrites the oldest fragment; `tkdiag`'s fd_stem counts the overrun and resyncs. Latest-wins is the intended semantics. Crash-only: no restart inside a run. Shutdown is independent of `tkdiag`, which stops on CNC HALT only. | `tkdiag` CNC slots 2 to 4 (tiles reporting, fragments accepted, fragments rejected) and fd_stem link metrics. See [`plans/v2.10-s14-tkdiag-fan-in.md`](plans/v2.10-s14-tkdiag-fan-in.md). |

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

## Stem Callback Contract Conformance

The fd_stem callback contract is stated in
[`contribution/tickoni.md`](contribution/tickoni.md) ("fd_stem Callback
Contract") and restated at the top of `src/tickoni/c_abi/shim/stem_helpers.h`:
`DURING_FRAG` stages, `AFTER_FRAG` commits and publishes, `AFTER_CREDIT` is
only for fragment-independent work, and `STEM_BURST` equals the maximum
publishes per stem iteration.

| Tile | Shape | State | Note |
|---|---|---|---|
| `tknorm` | 1-in, 1-out (+ optional diagnostic link) | Conforms | Publishes in `AFTER_FRAG` only, the diagnostic fragment after the pipeline publish (`STEM_BURST` stays 1: the unreliable diagnostic link draws no credit). |
| `tkdedu` | 1-in, 1-out (+ optional diagnostic link) | Conforms | Publishes in `AFTER_FRAG` only, the diagnostic fragment after the pipeline publish (`STEM_BURST` stays 1). |
| `tkaudt` | 1-in, 0-out (+ optional diagnostic link) | Conforms | `DURING_FRAG` builds the record into the next, still-uncommitted ring slot; `AFTER_FRAG` stamps `seq`/`prev_hash`, hashes, and advances the chain and `audit_count`. Sink: no pipeline publish; its only publish is the optional diagnostic fragment, last in `AFTER_FRAG`. See [`plans/v2.NN-sXX-tkaudt-stem-contract.md`](plans/v2.NN-sXX-tkaudt-stem-contract.md). With an agent input it also orders the chain (see the event-ordered chain row); in a topology with a payment chain and agent runs its `BEFORE_FRAG` holds the next payment record back until the previous agent record is committed. |
| `tkmodl` | 1-in, 2-out | Conforms (fixture/replay only) | `DURING_FRAG` stages a multipart fragment; `AFTER_FRAG` feeds the reassembler and, on a complete verified request, governs it (chat and embedding allowlists, vector width), resolves the fixture and its captured content, publishes the audit record and the first result fragments (`STEM_BURST` 5); `AFTER_CREDIT` sends the rest and stops polling input while a result is in flight. Per-instance config binds `(kind_id, tier)`. No provider I/O is reachable. Up to 11 instances; runs in `agentProcess(n)` and in the 14-tile investment workflow. |
| `tkagnt` (active agent worker) | 1+N in, N+2 out | Conforms | Admits requests (`BEFORE_FRAG` backpressure), asks the Zig-owned hooks (`decision.zig`) for routing and result interpretation, dispatches to the tkmodl instance serving the named tier, correlates results by ordinal, instance and model, and publishes only in `AFTER_CREDIT`: terminal results (after the audit watermark), audit records (admission order) and request fragments (`STEM_BURST` 4). One request, one dispatch, one result; no cascade. Drains on HALT. |
| `tkdisp` (terminal-result sink or scheduler) | sink: 1-in, 0-out; scheduler: 2-in, 1-out | Conforms | Sink (agent topology): bounded consumer of `tkagnt`'s terminal-result link; stages and validates in `DURING_FRAG`, appends to a fixed ring in `AFTER_FRAG`; no decisions, no publish. Scheduler (full workflow, when a `tkcase` feeds it): `BEFORE_FRAG` leaves an event upstream while its 64-entry queue is full; `AFTER_FRAG` queues the event's source offset or appends a result; `AFTER_CREDIT` sends the next request's fragments (`STEM_BURST` 4) from the run's dispatch template, with only the run id taken from the event. No dispatch policy. |
| `tkcase`, `tktool`, `tkadpt` (placeholders) | 1-in 2-out, 1-in 2-out, 1-in 1-out | Conforms | One stem implementation (`shim/tk_pass_stem.c`): `DURING_FRAG` validates and stages, `AFTER_FRAG` publishes (`STEM_BURST` 4). `tkcase` forwards each event unchanged to both consumers; `tktool` and `tkadpt` are idle bounded consumers that stop on HALT. No case, tool or adapter logic. |
| `tkdiag` (diagnostics and fan-in collector) | N-in (one unreliable diagnostic link per pipeline tile), 0-out | Conforms | One stem implementation (`shim/tk_diag_stem.c`), modelled on Firedancer's diag tile. `BEFORE_CREDIT` (every 100 ms, never sleeping) reads each tile's `/proc` statistics through `shim/tk_os_stats.h` into that tile's metrics region, applies the liveness rule (process gone while `TILE_STATUS` is not "shutdown": a crash, logged once) and reads tkrepl's CNC for the replay result. `DURING_FRAG` bounds-checks the chunk and size and stages a copy of the fragment; `AFTER_FRAG` offers it to the aggregation (`tkdiag_agg_accept` in `shim/tk_diag_fragment.h`: shape, sender identity bound from the topology, strictly increasing `seq`). `METRICS_WRITE` publishes the `tkdiag` metrics kind; CNC slots 0 to 4 for the supervisor. No publish (`STEM_BURST` 1, `out_cnt` 0), no `AFTER_CREDIT`, no socket: the metric tile serves its metrics. Plus the shared `DURING_HOUSEKEEPING` heartbeat. Fails closed on an output link, a reliable input, an input whose producer is not a diagnostic producer, or two inputs of one producer type; with no input links it still observes the tiles. `SHOULD_SHUTDOWN` is CNC HALT or tkrepl's `replay_checked`. `/proc` descriptors are opened in `privileged_init` and listed in `populate_allowed_fds`; no seccomp policy yet. See [`plans/v2.10-s14-tkdiag-fan-in.md`](plans/v2.10-s14-tkdiag-fan-in.md). |
| `tkmetr` | 0-in, 0-out | Conforms (liveness only) | Delegates to `fd_metric_tile.c`; Tickoni authors no fragment callbacks for it. The file is also linked into the native Firedancer binaries, so liveness is a NULL-by-default hook, `fd_metric_ctx_t.liveness`, that `shim/tk_metric_tile.c` sets to `stk_cnc_liveness`; native Firedancer leaves it NULL and is unchanged. It runs its stem loop under `__tile-run` (launch mode `tile` in the registry) and never took the generic path's `RUN` and heartbeat, so the supervisor never stale-checked it. |

Every stem tile above (all nine `tk_*_stem.c` files) and the metric tile advance the CNC heartbeat,
and moves the CNC `BOOT -> RUN` on its first loop iteration, from
`STEM_CALLBACK_DURING_HOUSEKEEPING` (`stk_cnc_liveness` in
`shim/stem_helpers.h`), so the supervisor classifies a wedged or stopped stem
tile `.stale` exactly as it does a generic-path tile. See [`knowledge/tile-orchestration.md`](../knowledge/tile-orchestration.md),
"Health And Lifecycle", for the clock, units and the staleness budget.

The Tickoni-authored stem tiles follow the same test/FFI pattern (see
[`contribution/tickoni.md`](contribution/tickoni.md), "Stem Tile Test And FFI
Pattern"): the identical `tk_get_<tile>_run_*` accessor set in the tile's
`.c`/`.h`, a `c_abi/<tile>.zig` FFI module (`c_abi/audit.zig` for tkaudt),
and a unit-test registration in `build-lib/lanes/unit.zig`. No Zig struct
mirrors a C struct.

Forward-looking plans written before the contract still prescribe publishing
in `AFTER_CREDIT` and must not be followed verbatim for the publish point:
`plans/v2.10-s14-fd-stem-migration.md`, `plans/v2.22-s5-fd-stem-migration.md`,
`plans/v2.10-s14-tkrepl-capsule-io.md`, and the story
`doc/strategy/roadmap/stories/v2.10-s14.md`. The contract wins; those
documents need a product-owned pass before `tkpoly` or `tkrepl`
are migrated. `plans/v2.10-s14-tkdiag-fan-in.md` had the same defect and was
given that pass before it was implemented: its "Resolved Design" section
supersedes its code sketches (publish in `AFTER_FRAG`, an unreliable link, a
128-byte fragment). `tkings` now uses `fd_stem` for the synthetic payment
source under the S15 producer-only exception: it publishes the reliable
pipeline fragment and then the diagnostic fragment in `AFTER_CREDIT`. The
test-only model-request source stays on the process callback path.

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
