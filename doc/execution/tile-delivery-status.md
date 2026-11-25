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

Status: financial event spine and agent workflow stem-migrated; case, tool,
adapter, API, execution, and evidence tiles remain unimplemented.

Financial event spine (fully stem-migrated, tested in process spike):

```text
tkings -> tknorm -> tkdedu -> tkpoly -> tkaudt
replay capsule -> tkrepl -> deterministic pipeline with tkexec disabled
all tile metrics -> metric (tkmetr)
all tile diagnostics -> tkdiag
```

Agent workflow (stem-migrated, fixture/replay mode):

```text
tkdisp -> tkagnt -> tkmodl[k]
tkagnt -> tktool -> tkadpt
tkagnt -> tkaudt
tkmodl -> tkaudt
tkcase -> tkdisp -> tkagnt (full workflow; tkcase placeholder)
tkagnt -> tktool -> tkaudt, tkadpt -> tkaudt (full workflow; placeholders)
```

Payment pipeline implementation lives in
[`src/tickoni/tiles/payment_pipeline/`](../../src/tickoni/tiles/payment_pipeline/).
Agent workflow implementation lives in
[`src/tickoni/tiles/agent/`](../../src/tickoni/tiles/agent/),
[`src/tickoni/tiles/model/`](../../src/tickoni/tiles/model/),
[`src/tickoni/tiles/disp/`](../../src/tickoni/tiles/disp/),
[`src/tickoni/tiles/case/`](../../src/tickoni/tiles/case/),
[`src/tickoni/tiles/tool/`](../../src/tickoni/tiles/tool/), and
[`src/tickoni/tiles/adapter/`](../../src/tickoni/tiles/adapter/).
Replay lives in [`src/tickoni/tiles/replay/`](../../src/tickoni/tiles/replay/).
Supervisor wiring is in
[`src/app/tickoni/supervisor.zig`](../../src/app/tickoni/supervisor.zig) and the
static topology in
[`src/tickoni/runtime/topology.zig`](../../src/tickoni/runtime/topology.zig).

Tile behaviors proven by the current topology:

1. `tkings` owns canonical `TkEvent` framing (dropping and counting what fails), per-source source offsets and ingress backpressure. Its only source is its input link.
2. `tknorm` owns canonical payment normalization and malformed-event rejection.
3. `tkdedu` owns idempotency and content-hash duplicate memory.
4. `tkpoly` owns allow, deny, malformed-drop, and duplicate-drop decisions.
5. `tkaudt` owns append-only audit ordering and hash chaining.
6. `tkrepl` owns deterministic replay comparison with external effects disabled.
7. `tkmetr` owns runtime metric snapshots.
8. `tkdiag` owns crash, sandbox, audit, and replay diagnostics.
9. `tkdisp` owns event-to-request scheduling (an agent-request event's own request, a payment event's template) and terminal-result receipt.
10. `tkagnt` owns bounded agent request dispatch, model-tier routing, result correlation, and audit watermark enforcement.
11. `tkmodl` owns model fixture resolution, governance, and captured-result replay (fixture/replay only; no provider I/O).

The Firedancer-style topology answers for current links are:

| Link | Owner tile | Backing allocation | Mapping mode | Depth / MTU | Reliability | Overrun, restart, shutdown | Metrics and diagnostics |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `tkings -> tknorm` | `tkings` owns source offsets and writes the link; `tknorm` owns framing rejection. | Heap-backed bounded SPSC ring in `PaymentPipelineState`; future shared-memory workspace. | Single producer writes; single consumer reads; in-process thread mapping for spike. | 64 entries / 512-byte `TkEvent` (360 bytes). | Reliable until shutdown; producer backpressures when full. | Overrun increments wait pressure instead of dropping; restart regenerates from source offset; shutdown closes the link. | Produced, invalid, max depth, backpressure waits, latency hops, crash tile. |
| `tknorm -> tkdedu` | `tknorm` owns canonical hash generation and malformed-drop decisions. | Heap-backed bounded SPSC ring in `PaymentPipelineState`; future shared-memory workspace. | Single producer writes normalized events or malformed-drop envelopes; single consumer reads. | 64 entries / 512-byte `TkEvent`. | Reliable until shutdown. | Overrun backpressures normalization; restart recomputes stable hashes; shutdown drains then closes. | Normalized count, malformed-drop count, queue depth, waits, latency hops. |
| `tkdedu -> tkpoly` | `tkdedu` owns idempotency key and content-hash memory. | Heap-backed bounded SPSC ring plus `tkdedu`-owned seen-key arrays. | Single producer writes dedupe decisions; single consumer reads. | 64 entries / 512-byte `TkEvent`. | Reliable until shutdown. | Overrun backpressures dedupe; restart rebuilds seen-key state from source order; shutdown drains then closes. | Duplicate count, queue depth, waits, latency hops. |
| `tkpoly -> tkaudt` | `tkpoly` owns policy decision; `tkaudt` owns final ordering. | Heap-backed bounded SPSC ring in `PaymentPipelineState`; future audit workspace. | Single producer writes policy envelopes; single consumer appends. | 64 entries / 512-byte `TkEvent`. | Reliable until shutdown. | Overrun backpressures policy; restart re-evaluates policy version; shutdown drains then closes. | Allow, deny, duplicate-drop, audited count, queue depth, waits, latency hops. |
| terminal tile `-> tkgate` (product topologies: payment, investment, agent) | No producer tile yet: the link is `rt.link.external_src` (Firedancer's `permit_no_producers`), and it is `tkgate`'s only input. The terminal tile (the Qt CaseOps desktop app, a separate story) will produce it; the integration test harness `test/integration/ingest_harness.zig` stands in for it today. The producer owns version, kind, source, flags, `trace_id` and `idempotency_key`. | Tango shared-memory workspace (per-run name); the producer joins it through the supervisor (`Supervisor.linkHandles`) and publishes with `rt.link.Producer`. | One whole `TkEvent` per fragment (`shim/tk_event_wire.h`). `tkgate` drops and counts a fragment of the wrong size, not SOM+EOM, with an unknown version, kind or flag, a source other than `TK_EVENT_SOURCE_TKGATE` (replay never enters here), or a zero `idempotency_key` (shared envelope checks in `shim/tk_event_framing.h`). An all-zero `trace_id` is not dropped: `tkgate` fills in 16 random bytes (two `fd_rng_ulong` draws, seeded per run). | 64 entries / 512 MTU. | Reliable: the producer waits on `tkgate`'s fseq credits, never drops. | Crash-only: no restart inside a run. The producer stops before the supervisor's shutdown unmaps the workspace; `tkgate` stops on its event gate or CNC HALT. With no producer (`start-process` until the terminal tile lands) the pipeline idles. | `tkgate` CNC slots 0 (`api_published`) and 1 (`api_wire_invalid`). |
| `tkgate -> tkings` (product topologies) | `tkgate` writes; `tkings` owns framing validation and `source_offset`, and resets every field a later tile owns. | Same workspace. | Single producer (`tkgate`) writes whole `TkEvent`s unchanged except a filled-in `trace_id`; single consumer reads. | 64 entries / 512 MTU. | Reliable: `tkgate` waits on `tkings`'s credits (fd_stem stops it polling its input), never drops. | Crash-only; `tkings` stops on its event gate or CNC HALT. | `tkings` CNC slots 0 (`produced`) and 1 (`ingest_invalid`). |
| external `-> tkings` (isolation fixtures without `tkgate`) | No producer tile: the link is `rt.link.external_src`, and it is `tkings`'s only source; the integration test harness publishes on it directly (later also `tkrepl` replay). `tkings` owns framing validation and `source_offset`, and resets every field a later tile owns. | Tango shared-memory workspace (per-run name), joined as above. | One whole `TkEvent` per fragment. A fragment of the wrong size, not SOM+EOM, or with an unknown version, kind, source or flag, a replay bit from a non-tkrepl source, or a zero `trace_id` is dropped and counted. | 64 entries / 512 MTU. | Reliable: the producer waits on `tkings`'s fseq credits, never drops. | Crash-only; `tkings` stops on its event gate or CNC HALT. | `tkings` CNC slots 0 (`produced`) and 1 (`ingest_invalid`). |
| `tkmodl -> tkaudt` | `tkmodl` owns the model-call or denial record content; `tkaudt` owns ordering, chaining and hashing. | Same workspace. | `tkmodl` writes `ModelAuditMsg` with `sig` = record type (model_call or denial); `tkaudt` copies it into its next uncommitted slot. | 32 entries / 256 MTU (record is under 256 bytes, asserted in `c_abi/tkmodl.zig`). | Reliable. | As above; `tkmodl` publishes the audit record and the result from one `AFTER_FRAG` commit (`STEM_BURST` 2). | `tkaudt` committed record count and hash chain. |
| `tkagnt -> tkmodl[k]` | `tkagnt` owns dispatch; `tkmodl[k]` owns reassembly, governance and the prompt hash (computed from the bytes it receives). | Same workspace. | Multipart `ModelRequestMsg` + prompt, one stream per request, one request in flight per instance. | 32 fragments / 8192 MTU. | Reliable. | A stream that fails reassembly is dropped whole and counted; no governance, audit or result is produced for it, and the agent's model deadline ends the run in an audited terminal failure. | `tkmodl` `dropped`, `tkagnt` `dispatched`. |
| `tkmodl[k] -> tkagnt` | `tkmodl[k]` owns the result; `tkagnt` owns correlation and interpretation. | Same workspace. | Multipart `ModelResultMsg` + captured response bytes. The audit record is published first, then the result fragments over successive stem iterations; input polling pauses while a result is being sent. | 32 fragments / 8192 MTU. | Reliable. | An unknown, duplicate, stale, wrong-instance or wrong-model result completes nothing and is counted (`mismatched`); a corrupt or incomplete stream ends the run it answered in a transport failure. | `tkagnt` `results`, `mismatched`. |
| `tkagnt -> tkaudt` | `tkagnt` owns the terminal agent record (proposal or denial) and publishes in admission order; `tkaudt` owns ordering and the chain. | Same workspace. | One-fragment `TkAgentAuditMsg`, hashes and attribution only. `tkaudt` holds model records until the agent record for the same ordinal arrives and commits model-then-agent per ordinal. | 32 entries / 512 MTU. | Reliable. | A late, duplicate or out-of-order record is refused and counted, never reordered; held records are bounded at 64. | `tkaudt` `rejected`, `held_*`. |
| `tkaudt` committed-order watermark | `tkaudt` writes (single writer); `tkagnt` reads. | One `fseq` object in the app workspace, created by `topo_build` when both tiles exist. | The last agent ordinal committed, published only after the record is appended and chained (`TK_AUDIT_WATERMARK_NONE`, the 64-bit all-ones value, before the first; not C `ULONG_MAX`, which is only 32-bit on Windows). `tkaudt` stays a sink. | n/a | n/a | `tkagnt` publishes a run's terminal result only once the watermark has reached its ordinal. | Watermark value (shared memory). |
| `tkagnt -> tkdisp` | `tkagnt` owns the terminal result; `tkdisp` (bounded sink) owns receipt. | Same workspace. | One-fragment `TkAgentResultMsg`: outcome, hashes, attribution; no content. | 32 entries / 256 MTU. | Reliable. | Published in admission order after the audit commit; on HALT every accepted request still gets one (completed or failed as shutdown). | `tkdisp` committed result count (scratch accessor). |
| `tkcase -> tkpoly`, `tkcase -> tkdisp` (full workflow) | `tkcase` (placeholder) owns forwarding; `tkpoly` and `tkdisp` own receipt. | Same workspace as every link of the run. | Each event is forwarded unchanged to both consumers; the producer back-pressures on the slower one. | 64 entries / 512 MTU. | Reliable. | A new event stays upstream while a consumer cannot take it; shutdown follows the event count, then HALT. | `tkdisp` events seen and requests scheduled (scratch accessors). |
| `tkdisp -> tkagnt` | `tkdisp` owns the request and stamps its run id (event offset + 1) and trace id (the event's); `tkagnt` owns framing rejection, prompt resolution, admission ordinals and routing. | Same workspace. | One fixed `TkAgentRequestMsg` fragment: scope plus `prompt_ref` (hash, length), no prompt bytes. An agent-request event's own request, a payment event's dispatch template. `tkagnt` resolves the prompt from its content-addressed table (`tkagnt.prompts`); an unknown reference is an audited `DENY_INVALID_REQUEST` (failed scope `prompt_ref`). A fragment of the wrong size or not SOM+EOM admits nothing and is counted. | 32 entries / 512 MTU. | Reliable; a new request is held back (`BEFORE_FRAG` returns -1) while there is no free request slot or run entry, so nothing is dropped. | One request per stem iteration; a full event queue backs events up to `tkcase`; shutdown drains accepted work first. | `tkdisp` requests scheduled; `tkagnt` admitted and `transport_dropped`. |
| `tkagnt -> tktool -> tkadpt`, `tktool -> tkaudt`, `tkadpt -> tkaudt` (full workflow) | `tktool` and `tkadpt` (placeholders) own receipt; no tile publishes on them. | Same workspace. | Declared and bound only: no tool or adapter call and no tool or adapter audit record exists, and `tkaudt` does not audit a fragment that arrives on such an input. | 32 entries / 512 MTU (to `tkaudt`: 256). | Reliable. | Idle. | `tktool` and `tkadpt` consumed counts (scratch accessors; zero in a correct run). |
| `tkaudt` event-ordered chain (full workflow) | `tkaudt` owns the single hash chain; `tkpoly`, `tkmodl` and `tkagnt` own their records' content. | Same workspace. | One chain in event order: for event n, its policy decision record, then its model record (if any), then its agent record (owner decision, 2026-11-19). Every record carries the event's `trace_id` in its header. Policy records arrive in event order and agent runs are admitted in event order, so the n-th of each belong together. A policy record is left queued upstream (`BEFORE_FRAG` -1, nothing dropped) until the agent record of event n-1 is committed; an agent record is committed only after its event's policy record. Where there is no spine chain or no agent runs, records commit on arrival or by ordinal as before. | Event link 64 / 512; agent audit link 32 / 512. | Reliable. | An event whose policy record never reaches `tkaudt` leaves its agent record held (fail closed; crash-only). Shutdown follows the event count: both the agent ordinals and the policy records. | `tkaudt` committed counts, held counts, refusals (scratch accessors). |
| `tkaudt` audit log | `tkaudt` owns append-only sequence and hash chain. | Heap-backed fixed audit record array; future append-only file or shared audit workspace. | Only `tkaudt` writes; replay reads after audit completion. | Capacity equals configured event count. | Reliable; full audit allocation is a crash condition. | Full allocation marks `tkaudt` crashed and stops the runtime; restart replays from source facts; shutdown preserves completed records in memory for replay. | Audited count, audit hash, replay divergence, latency hops, crash tile. |
| `tkrepl` replay path | `tkrepl` owns replay comparison and external-effects-disabled mode. | Reads completed audit records and regenerates deterministic synthetic events. | Replay reads audit after `tkaudt` signals completion; no producer mutates audit during compare. | Same event envelope as the main path. | Reliable comparison; reports divergence instead of mutating state. | Replay never invokes external effects; mismatch increments divergence count; shutdown exits after comparison or crash signal. | Replay checked, replay match, divergence count. |
| `tkmetr` telemetry | `tkmetr` owns metric snapshots. | Atomic counters and queue-watermark reads in `PaymentPipelineState`. | All tiles publish counters; `tkmetr` reads snapshots. | No correctness queue in the spike. | Observational; future telemetry may be lossy with counted drops. | Shutdown takes a final snapshot. | Produced, normalized, invalid, duplicates, allowed, denied, audited, depth, waits, max latency hops. |
| `tkdiag` diagnostics | `tkdiag` owns diagnostic aggregation: the latest fragment per pipeline tile, the observation of every tile's process, and the replay result it reads. | The 5 diagnostic links below (payment process topology only); every tile's metrics region (status, pid, and where it writes OS-level metrics); tkrepl's CNC app slots 0 and 1. The in-process spike's `PaymentPipelineState` fields remain the thread-mode runtime's. | Tiles publish diagnostics; `tkdiag` receives and aggregates them and watches the processes. | One fragment per processed event per producer; `tkdiag` keeps one per input. | Observational; best effort. A tile found dead is counted (and logged) by `tkdiag`; the supervisor still owns crash handling. | `tkdiag` stops on CNC HALT, or once tkrepl publishes `replay_checked`. A crashed producer publishes nothing, so its death is seen from its process and its `TILE_STATUS`, not from a fragment. | CNC slots 0 to 4 (tiles that died or reported a fault, tiles that died before they ran, tiles reporting, fragments accepted and rejected) and the `tkdiag` metrics kind at `/metrics`. |
| `tkings`, `tknorm`, `tkdedu`, `tkpoly`, `tkaudt` `-> tkdiag` (payment process topology) | Each producer owns its own diagnostic fragment (`shim/tk_diag_fragment.h`: cumulative counters of that tile only); `tkdiag` owns aggregation. | Tango shared-memory workspace `tkpay0`, links appended after the pipeline links so each is its producer's last output. | One fragment per processed event, single producer, single consumer (`tkdiag`). All five stem tiles use `fd_stem_publish` in `AFTER_FRAG`. | 64 entries / 128-byte fragment. | **Unreliable** (`LinkReliability.lossy`): the consumer is wired unreliable, so a producer never waits on `tkdiag`. | The producer overwrites the oldest fragment; `tkdiag`'s fd_stem counts the overrun and resyncs. Latest-wins is the intended semantics. Crash-only: no restart inside a run. Shutdown is independent of `tkdiag`, which stops on CNC HALT only. | `tkdiag` CNC slots 2 to 4 (tiles reporting, fragments accepted, fragments rejected) and fd_stem link metrics. See [`plans/v2.10-s14-tkdiag-fan-in.md`](plans/v2.10-s14-tkdiag-fan-in.md). |

### Stem Migration Status

All 17 canonical Tickoni tile runtime IDs (see [`tile-topology.md`](../knowledge/tile-topology.md), "Runtime IDs") map to the status below. The C shim `.c`/`.h` files live in [`src/tickoni/c_abi/shim/`](../../src/tickoni/c_abi/shim/); the Zig FFI wrappers in [`src/tickoni/c_abi/`](../../src/tickoni/c_abi/); the tile implementations in [`src/tickoni/tiles/`](../../src/tickoni/tiles/).

| Tile | Runtime ID | Stem file | Status | Implementation status |
|---|---|---|---|---|
| `tkings` | ingest_tile | `tk_ingest_stem.c` | Migrated | Payment source (synthetic offsets) with no input link; forwards an externally produced input link (agent topology). Processed. |
| `tknorm` | normalize_tile | `tk_normalize_stem.c` | Migrated | Canonical payment normalization. Processed. |
| `tkdedu` | dedupe_tile | `tk_dedu_stem.c` | Migrated | Idempotency key + content-hash dedupe. Processed. |
| `tkpoly` | policy_tile | `tk_policy_stem.c` | Migrated | Allow/deny/malformed-drop/duplicate-drop decisions. Processed. |
| `tkaudt` | audit_tile | `tk_audit_stem.c` | Migrated | Append-only hash-chain audit. Sink tile. Processed. |
| `tkrepl` | replay_tile | *(uses stem contract via shim)* | Not started | Pure test infrastructure. Exposes test verification functions (`verifyAllowedTrade`, etc.) that load capsules from disk and compare against fixture backends. No runtime tile process. No `tkcase → tkrepl` trigger. No `tkaudt → tkrepl` link wired. No product usecase requires it — forensic replay is not a user-facing feature. |
| `metric` | metric_tile | *(delegates to `fd_metric_tile.c`)* | Migrated | Prometheus metrics export. Processed. |
| `tkdisp` | agent_dispatch_tile | `tk_disp_stem.c` | Migrated | Terminal-result sink and event-to-request scheduler. Processed. |
| `tkagnt` | agent_worker_tile | `tk_agent_stem.c` | Migrated | Bounded agent dispatch, tier routing, result correlation. Processed. |
| `tkmodl` | model_gateway_tile | `tk_model_stem.c` | Migrated | Fixture/replay only; no provider I/O. Processed. |
| `tkdiag` | diag_tile | `tk_diag_stem.c` | Migrated | Fan-in diagnostics with lossy links. Processed. |
| `tkcase` | case_router_tile | placeholder in `tk_pass_stem.c` | **Needs real stem** | Placeholder: forwards events unchanged. No case lifecycle logic. |
| `tktool` | tool_broker_tile | placeholder in `tk_pass_stem.c` | **Needs real stem** | Placeholder: idle bounded consumer. No tool-broker logic. |
| `tkadpt` | adapter_tile | placeholder in `tk_pass_stem.c` | **Needs real stem** | Placeholder: idle bounded consumer. No adapter logic. |
| `tkevid` | evidence_tile | *(none — no stem needed)* | **Not implemented** | Content-addressed evidence blob store. |
| `tkgate` | caseops_api_tile | `tk_gate_stem.c` | Migrated (pipeline tile) | Wire-shape validation and trace-id fill-in between the terminal tile and `tkings`; no sockets. CaseOps board queries, evidence reads, approvals and the audit timeline are later stories. |
| `tkexec` | action_executor_tile | *(none — no stem needed)* | **Not implemented** | Approved execution: accounting ledger, payment, trading. Disabled-by-default. |

Three tiles share a placeholder stem (`tk_pass_stem.c`): `tkcase`, `tktool`, `tkadpt`. Each needs its own `.c`/`.h` stem with the `tk_get_<tile>_run_*` accessor pattern, a `c_abi/<tile>.zig` FFI module, and a unit-test registration in `build-lib/lanes/unit.zig`.

Two tiles have no stem at all (`tkevid`, `tkexec`) and need full implementation from scratch.

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

Step 1: deterministic financial event spine. **Status: done.**

```text
configured event source
  -> tkings     [migrated]
  -> tknorm     [migrated]
  -> tkdedu     [migrated]
  -> tkpoly     [migrated]
  -> tkaudt     [migrated]

replay capsule -> tkrepl     [stem only, no runtime trigger] -> deterministic pipeline with tkexec disabled
all tile metrics -> metric   [migrated]
all tile diagnostics -> tkdiag [migrated]
```

Note: `tkrepl` has a stem callback but no runtime tile process. It exposes test verification functions (`verifyAllowedTrade`, etc.) that load capsules from disk and compare against fixture backends. The two runtime triggers described in the architecture — `tkcase` closing a case, or `tkaudt` signaling completion — are not wired.

Step 2: deterministic case and evidence scope. **Status: not started.**

```text
tkcase     [needs real stem]    → deterministic case lifecycle
tkevid     [not implemented]   → content-addressed evidence store
all boundary events -> tkaudt  [migrated — audit chain already exists]
```

Step 3: bounded agent, model, tool, and adapter integration. **Status: agent+model done; tool+adapter placeholder.**

```text
tkdisp -> tkagnt -> tkmodl     [all migrated]
tkagnt -> tktool -> tkadpt     [placeholders: need real stems]
```

Step 4: operator API and approved execution boundary. **Status: not started.**

```text
tkgate      [pipeline stem]     → terminal tile -> tkgate -> tkings; CaseOps board, evidence, approvals, audit timeline not started
tkexec     [not implemented]   → approved privileged execution (disabled-by-default)
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
| `tkings` | 0-in or 1-in, 1-out (+ optional diagnostic link) | Conforms (producer-only exception without an input) | The topology shape decides what it ingests. With no input (synthetic source) it is the only producer-only stem tile: `BEFORE_CREDIT` only stages the next payment (`syntheticPayment`, installed by the Zig child), because `fd_stem` runs it before the reliable output's credit check; `AFTER_CREDIT` publishes one fragment (`STEM_BURST` 1), then the counter and the lossy diagnostic fragment, and sets exhaustion only after the final publish. With one input (only an externally produced one, `rt.link.external_src`; the registry's `.ingest` cardinality) it is a forwarder: `DURING_FRAG` stages, `AFTER_FRAG` publishes the fragment unchanged and counts a message at EOM; no diagnostic fragment. A zero event count leaves the tile idle until CNC HALT. It carries no test code: the test-build crash and stuck faults are the shared stem liveness path (`stk_cnc_liveness`, installed from the LaunchSpec for any stem tile). See [`plans/v2.10-s15-tkings-fd-stem-migration.md`](plans/v2.10-s15-tkings-fd-stem-migration.md) and [`plans/v2.NN-tkings-test-build-cleanup.md`](plans/v2.NN-tkings-test-build-cleanup.md). |
| `tkgate` | 1-in, 1-out | Conforms | `DURING_FRAG` copies and judges the copy (`tkgate_wire_ok`); `AFTER_FRAG` fills in an absent trace id (the RNG draw is a state change, so it is not in `DURING_FRAG`), publishes to `tkings` (`STEM_BURST` 1) and writes its two counters. |
| `tknorm` | 1-in, 1-out (+ optional diagnostic link) | Conforms | Publishes in `AFTER_FRAG` only, the diagnostic fragment after the pipeline publish (`STEM_BURST` stays 1: the unreliable diagnostic link draws no credit). |
| `tkdedu` | 1-in, 1-out (+ optional diagnostic link) | Conforms | Publishes in `AFTER_FRAG` only, the diagnostic fragment after the pipeline publish (`STEM_BURST` stays 1). |
| `tkaudt` | 1-in, 0-out (+ optional diagnostic link) | Conforms | `DURING_FRAG` builds the record into the next, still-uncommitted ring slot; `AFTER_FRAG` stamps `seq`/`prev_hash`, hashes, and advances the chain and `audit_count`. Sink: no pipeline publish; its only publish is the optional diagnostic fragment, last in `AFTER_FRAG`. See [`plans/v2.NN-sXX-tkaudt-stem-contract.md`](plans/v2.NN-sXX-tkaudt-stem-contract.md). With an agent input it also orders the chain (see the event-ordered chain row); in a topology with a payment chain and agent runs its `BEFORE_FRAG` holds the next payment record back until the previous agent record is committed. |
| `tkmodl` | 1-in, 2-out | Conforms (fixture/replay only) | `DURING_FRAG` stages a multipart fragment; `AFTER_FRAG` feeds the reassembler and, on a complete verified request, governs it (chat and embedding allowlists, vector width), resolves the fixture and its captured content, publishes the audit record and the first result fragments (`STEM_BURST` 5); `AFTER_CREDIT` sends the rest and stops polling input while a result is in flight. Per-instance config binds `(kind_id, tier)`. No provider I/O is reachable. Up to 11 instances; runs in `agentProcess(n)` and in the 14-tile investment workflow. |
| `tkagnt` (active agent worker) | 1+N in, N+2 out | Conforms | Admits requests (`BEFORE_FRAG` backpressure), asks the Zig-owned hooks (`decision.zig`) for routing and result interpretation, dispatches to the tkmodl instance serving the named tier, correlates results by ordinal, instance and model, and publishes only in `AFTER_CREDIT`: terminal results (after the audit watermark), audit records (admission order) and request fragments (`STEM_BURST` 4). One request, one dispatch, one result; no cascade. Drains on HALT. |
| `tkdisp` (terminal-result sink or scheduler) | sink: 1-in, 0-out; scheduler: 2-in, 1-out | Conforms | Sink (agent topology): bounded consumer of `tkagnt`'s terminal-result link; stages and validates in `DURING_FRAG`, appends to a fixed ring in `AFTER_FRAG`; no decisions, no publish. Scheduler (full workflow, when a `tkcase` feeds it): `BEFORE_FRAG` leaves an event upstream while its 64-entry queue is full; `AFTER_FRAG` queues the event's source offset or appends a result; `AFTER_CREDIT` sends the next request's fragments (`STEM_BURST` 4) from the run's dispatch template, with only the run id taken from the event. No dispatch policy. |
| `tkcase`, `tktool`, `tkadpt` (placeholders) | 1-in 2-out, 1-in 2-out, 1-in 1-out | Conforms | One stem implementation (`shim/tk_pass_stem.c`): `DURING_FRAG` validates and stages, `AFTER_FRAG` publishes (`STEM_BURST` 4). `tkcase` forwards each event unchanged to both consumers; `tktool` and `tkadpt` are idle bounded consumers that stop on HALT. No case, tool or adapter logic. |
| `tkdiag` (diagnostics and fan-in collector) | N-in (one unreliable diagnostic link per pipeline tile), 0-out | Conforms | One stem implementation (`shim/tk_diag_stem.c`), modelled on Firedancer's diag tile. `BEFORE_CREDIT` (every 100 ms, never sleeping) reads each tile's OS process statistics through the portable `shim/tk_os_stats.h` (one implementation per OS) into that tile's metrics region, applies the liveness rule (process gone while `TILE_STATUS` is not "shutdown": a crash, logged once) and reads tkrepl's CNC for the replay result. `DURING_FRAG` bounds-checks the chunk and size and stages a copy of the fragment; `AFTER_FRAG` offers it to the aggregation (`tkdiag_agg_accept` in `shim/tk_diag_fragment.h`: shape, sender identity bound from the topology, strictly increasing `seq`). `METRICS_WRITE` publishes the `tkdiag` metrics kind; CNC slots 0 to 4 for the supervisor. No publish (`STEM_BURST` 1, `out_cnt` 0), no `AFTER_CREDIT`, no socket: the metric tile serves its metrics. Plus the shared `DURING_HOUSEKEEPING` heartbeat. Fails closed on an output link, a reliable input, an input whose producer is not a diagnostic producer, or two inputs of one producer type; with no input links it still observes the tiles. `SHOULD_SHUTDOWN` is CNC HALT or tkrepl's `replay_checked`. `/proc` descriptors are opened in `privileged_init` and listed in `populate_allowed_fds`; no seccomp policy yet. See [`plans/v2.10-s14-tkdiag-fan-in.md`](plans/v2.10-s14-tkdiag-fan-in.md). |
| `tkmetr` | 0-in, 0-out | Conforms (liveness only) | Delegates to `fd_metric_tile.c`; Tickoni authors no fragment callbacks for it. The file is also linked into the native Firedancer binaries, so liveness is a NULL-by-default hook, `fd_metric_ctx_t.liveness`, that `shim/tk_metric_tile.c` sets to `stk_cnc_liveness`; native Firedancer leaves it NULL and is unchanged. It runs its stem loop under `__tile-run` (launch mode `tile` in the registry) and never took the generic path's `RUN` and heartbeat, so the supervisor never stale-checked it. |

Every stem tile above (all ten `tk_*_stem.c` files) and the metric tile advance the CNC heartbeat,
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
128-byte fragment). `tkings` uses `fd_stem` for its synthetic payment source under the S15
producer-only exception (it stages in `BEFORE_CREDIT` and publishes in
`AFTER_CREDIT`), and forwards an externally produced input in `AFTER_FRAG`. No tile
has a process-mode source any more; `tkings` has no `process_fn`, and the
registry has no test-source override.

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
