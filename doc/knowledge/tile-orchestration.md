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
5. Tickoni's supervisor owns OS-process launch, child tracking, crash visibility,
   and crash-only shutdown behavior. Firedancer's optional single-process
   pthread launcher is not used by the Linux full runtime.

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

### Process-Per-Tile Launch And Boot

Tickoni's Linux topology is process-per-tile:

```text
supervisor
  -> bootLite(): version + logging + shared memory; supervisor is not a tile
  -> std.process.spawn(): one child process per topology tile
       -> full fd_boot(): initialize child tile-local Firedancer state
       -> fd_topo_run_tile(): run lifecycle in that already-spawned child
```

Full `fd_boot()` in a child does not mean that Tickoni launches tiles as
threads. The child command line does not provide `--tile-cpus`; Firedancer
therefore configures a one-tile group, treats the calling thread as tile 0, and
creates no additional pthread. Tickoni does not call
`fd_topo_run_single_process()`, which is the separate Firedancer path that
creates tile pthreads.

`FD_HAS_THREADS` is likewise a compile-time capability switch, not a launch-mode
selector. It changes facilities such as `FD_TL` to thread-local storage. Linux
Tickoni shims omit it because their runtime contract is one execution thread in
each tile process. They retain `FD_HAS_ATOMIC=1` for atomic communication across
process-shared workspace memory.

### Stem Specialization Ownership

`fd_stem.c` is a macro-generated template, not one generic exported run loop.
Each inclusion fixes the context type, alignment, callbacks, burst, lazy
interval, and shutdown rule at compile time. A tile must therefore enter only
its own specialization:

- `tkaudt` generates and calls its private `tkaudt_run` specialization.
- `metric` delegates through `fd_tile_metric.run`, which enters the metric
  specialization generated with `fd_metric_ctx_t` and metric callbacks.

Calling a stem runner generated for another tile can reinterpret scratch memory
under the wrong context type and crash after `fd_topo_run_tile()` initialization.
This specialization mismatch, not the absence of `FD_HAS_THREADS`, caused the
`tkaudt`/`metric` runtime failure covered by `test-integration-tk-infra`.

How a Tickoni-authored stem tile must be built — callbacks, scratch layout,
counters, registration, and tests — is stated below under
[fd_stem Tile Implementation Standard](#fd_stem-tile-implementation-standard).

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
`metric`, `tkdiag`) run in distinct child processes. Each child enters
`fd_topo_run_tile`; ordinary pipeline tiles use Tickoni-owned callbacks, while
`tkaudt` and `metric` enter their own tile-specific stem specializations. All
paths must interleave heartbeat or CNC health, work, and HALT observation.

**Timing note — metric tile bootstrap:** The metric tile has a longer bootstrap
window than pipeline tiles. Its privileged initialization creates HTTP server
state; `fd_topo_run_tile` then fills links, registers metrics, and calls
`unprivileged_init`, which publishes `boot_ts` to the CNC app region. Only then
does `fd_tile_metric.run` enter the metric stem and poll `fd_http_server` through
`before_credit`. The CNC timestamp may therefore be visible before the HTTP
endpoint completes its first poll/listen cycle. See
[workspace-management.md](workspace-management.md#tile-boot-timing-pipeline-tiles-vs-metric-tile)
for the practical implications in tests and diagnostics.

Future tiles (`tkcase`, `tkrepl`, `tkmodl`, `tktool`, `tkadpt`, `tkapi`) must
adhere to the same discipline:

- **Model access (`tkmodl`):** Use bounded polling on shared memory or a
  non-blocking queue from the LLM server proxy. Never have the model gateway
  process block waiting for a response. Responses arrive via shared memory or a
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
guarantee tile-to-core exclusivity: multiple tile processes may share a core.
If each tile process spins for the full poll budget when genuinely idle, `N`
idle links can still burn `N` cores even though no work is being done.

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

- Unbounded or long `sleep()`/`nanosleep()`/`usleep()` calls — they block the
  tile process's only execution context and prevent shutdown/heartbeat from
  interleaving. The explicitly bounded idle sleep described above is allowed
  because every iteration rechecks CNC HALT and health.
- `pthread_cond_wait()` or an unbounded `futex()` wait — blocks that execution
  context. The stem loop cannot observe shutdown or health changes while it is
  waiting.
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

## fd_stem Tile Implementation Standard

Three Tickoni tiles are implemented as `fd_stem` specializations today:
`tknorm` (`shim/tk_normalize_stem.c`), `tkdedu` (`shim/tk_dedu_stem.c`), and
`tkaudt` (`shim/tk_audit_stem.c`). `metric` is an fd_stem tile too, but it
delegates to upstream `fd_metric_tile.c` and Tickoni authors none of its
callbacks.

Three further stem tiles exist for the agent path, recorded here as verified
facts rather than as part of the list above: `tkmodl` (`shim/tk_model_stem.c`),
**fixture/replay only** — it has no provider I/O and rejects a live-provider
configuration, so the non-blocking-provider rule for `tkmodl` below is not yet
exercised; `tkagnt` (`shim/tk_agent_stem.c`), the active agent worker that
admits requests, routes them through Zig-owned hooks, dispatches to the `tkmodl`
instance that serves the requested tier, correlates results and delivers one
terminal result per accepted request after its audit record is committed; and
`tkdisp` (`shim/tk_disp_stem.c`), the bounded sink for those terminal results,
which in the full workflow is also the scheduler that sends one agent request
per event from a run-configured template. The full workflow also runs
`tkcase`, `tktool` and `tkadpt` as placeholder stem tiles (`shim/tk_pass_stem.c`:
`tkcase` forwards, the other two are idle) with no case, tool or adapter logic.
All run in the agent process topology `agentProcess(n)` (1 to 11 `tkmodl`
instances) and in `investmentWorkflow()`; see
[`plans/v2.NN-sXX-tkagnt-fd-stem-migration-done.md`](../execution/plans/v2.NN-sXX-tkagnt-fd-stem-migration-done.md)
and
[`plans/v2.NN-sXX-tkmodl-fd-stem-migration-done.md`](../execution/plans/v2.NN-sXX-tkmodl-fd-stem-migration-done.md).

This section is the architecture-boundary standard for that tile shape: when
to choose it, which callbacks a Tickoni tile may define, what must be true of
its scratch, how it is observed, how it is tested, and which parts of the
current implementation are known deviations rather than examples to copy.

The callback-level statement of the stage/commit rule lives in
[`../execution/contribution/tickoni.md`](../execution/contribution/tickoni.md)
("fd_stem Callback Contract") and is restated at the top of
`src/tickoni/c_abi/shim/stem_helpers.h`, next to the helpers that enforce it.
Per-tile conformance is tracked in
[`../execution/tile-delivery-status.md`](../execution/tile-delivery-status.md).
This section does not restate those; it owns the surrounding decisions.

### When A Tile Should Be An fd_stem Tile

An fd_stem tile is the default for a tile whose entire job is *consume
fragments from Tango links, transform, publish fragments*. It is the right
choice when all of the following hold:

- the tile's work is driven by incoming fragments on one or more `in` links,
- per-fragment work is bounded, non-blocking, and allocation-free,
- all per-tile state fits in a bounded, startup-allocated scratch object,
- the tile needs Firedancer's flow control, credit accounting, overrun
  detection, and link metrics rather than a hand-written loop.

Keep a tile on the generic Tickoni callback path
(`runtime/tile_process.zig` + a `tile_registry.zig` `process_fn`) when it is
a source with no `in` links and an external driver (`tkings` today), when it
must do blocking or syscall-heavy work behind the proxy pattern described
under [Enforcement](#enforcement), or when it is an observer tile with no
fragment flow. `tkdiag` was the one such observer on this list; the owner
directed it onto `fd_stem` as a minimal observer (0-in, 0-out, `BEFORE_CREDIT`
only, no fragment I/O) so that every Tickoni-authored tile shares one launch
path and lifecycle. See
[`plans/v2.NN-sXX-tkdiag-fd-stem-migration.md`](../execution/plans/v2.NN-sXX-tkdiag-fd-stem-migration.md).
The owner has since had the whole of that migration's future work done, in
[`plans/v2.10-s14-tkdiag-fan-in.md`](../execution/plans/v2.10-s14-tkdiag-fan-in.md),
modelled on Firedancer's diag tile: in the payment process topology `tkdiag`
takes one unreliable diagnostic link from each of `tkings`, `tknorm`, `tkdedu`,
`tkpoly` and `tkaudt`; it watches every tile's process and writes each tile's
OS-level metrics into that tile's metrics region; it reads tkrepl's replay
result; and it publishes nothing and opens no socket. Its metrics are served by
the metric tile, as Firedancer serves its diag tile's.

Mixing the two paths in one tile is not allowed. A tile is either an fd_stem
tile — `process_fn = null` in the registry, booted through
`tile_main.zig`'s `stemRun`, lifecycle owned by its `fd_topo_run_tile_t` —
or a generic tile. There is no tile that has both a stem specialization and a
process-mode callback.

### Mandatory Shape

Every Tickoni-authored stem tile is one `.c` file under
`src/tickoni/c_abi/shim/` with this shape, in this order:

1. **Context struct first.** `fd_stem.c` declares `ctx` using
   `STEM_CALLBACK_CONTEXT_TYPE`, so the type must be complete before the
   include. The context holds counters, staging state, resolved link
   addresses, the CNC pointer, the event-count gate, and nothing that needs
   an allocator.
2. **Forward declarations** of every callback. All callbacks are `static`;
   `fd_stem.c` expands calls to them inside its own translation unit, so a
   non-static definition collides with its implicit declaration.
3. **`STEM_*` macro block, then `#include "disco/stem/fd_stem.c"`, then
   `#undef` of every macro defined.** One specialization per tile, entered
   only by that tile — see [Stem Specialization
   Ownership](#stem-specialization-ownership).
4. **Tile-specific `scratch_align` / `scratch_footprint`** functions, plus
   no-argument wrappers for `topob.c`.
5. **Callbacks**, then the run entry, then the `fd_topo_run_tile_t`, then the
   accessor set.

Rules that hold for every such tile:

- **`STEM_NAME` is the tile id.** The generated symbols (`tknorm_run`,
  `tkdedu_run`, `tkaudt_run`) then name the tile they belong to, which is
  what makes a wrong-specialization call visible at the call site.
- **`STEM_BURST` equals the maximum `fd_stem_publish` calls one loop
  iteration can make.** With publish confined to `AFTER_FRAG`, `1UL` is
  correct by construction for a one-output tile and is what all three tiles
  use. `fd_stem` validates `burst` against out-link depth at startup and
  `FD_LOG_ERR`s on a mismatch, but it cannot detect a tile that publishes
  more often than it declared.
- **`STEM_LAZY` is explicit.** All three tiles use `((long)10e6)` — a 10 ms
  housekeeping interval, which is what paces flow-control publication and
  link-metric flushing. Do not leave it to the default; a tile whose
  consumers need tighter credit turnaround states its own value and says why.
- **`SHOULD_SHUTDOWN` composes exactly two kinds of term**: the tile's own
  exhaustion flag (`ctx->input_exhausted`, set by `STK_EVENT_EXHAUSTED` in
  `AFTER_FRAG`) and the supervisor's `FD_CNC_SIGNAL_HALT`. Both are cheap
  reads; `fd_stem` evaluates this at the top of every iteration. Do not put
  work, I/O, or state mutation in it.
- **The run entry resolves the CNC, calls the generated `*_run`, then sets
  `tile->allow_shutdown = 1`.** `fd_topo_run_tile` `FD_LOG_ERR`s when `run`
  returns while that flag is clear, so setting it is how a tile declares that
  returning was intentional. Note the per-tile comments claiming the harness
  resets the flag before calling `run` are wrong — nothing clears it, and
  `stemRun` pre-sets it (see Known Deviations).
- **`.privileged_init` / `.unprivileged_init` are assigned without a cast.**
  The Tickoni callback signature is already the Firedancer typedef. `tkaudt`
  assigns them directly; `tknorm` and `tkdedu` cast, which would silently
  accept a signature that no longer matches. New tiles follow `tkaudt`.

### Callbacks: Which To Define, Which Not To

| Callback | Use |
|---|---|
| `DURING_FRAG` | **Required.** Stage only: clear the staging flag, validate framing, copy the fragment out of the input dcache into tile-local scratch, compute pure functions of that copy. |
| `AFTER_FRAG` | **Required.** Commit only: state mutation, counters, `stk_publish_counter`, `STK_EVENT_EXHAUSTED`, `fd_stem_publish`. |
| `SHOULD_SHUTDOWN` | **Required.** Exhaustion flag + CNC HALT. |
| `AFTER_CREDIT` | Only for work that is not driven by an incoming fragment — a timer, a backlog drain, a batch flush. Never as a second publish path. |
| `BEFORE_FRAG` | Only for signature-based filtering, when a tile is wired to a link carrying fragments it must ignore. None of the three tiles needs it. |
| `DURING_HOUSEKEEPING` / `METRICS_WRITE` | Not used today. See "Observability: CNC Counters, Not fd_metrics" below — a tile that accumulates high-rate counters locally should publish them here rather than per fragment. |
| `BEFORE_CREDIT`, `RETURNABLE_FRAG`, `AFTER_POLL_OVERRUN` | Reserve for a stated need. `AFTER_POLL_OVERRUN` is the natural home for an overrun-visibility counter if one is added. |

The split is not stylistic. `fd_stem` re-reads the input sequence number
*after* `DURING_FRAG` returns and abandons the fragment — skipping
`AFTER_FRAG` entirely — when the producer overran the reader
(`src/disco/stem/fd_stem.c`, the `seq_test != seq_found` branch). Anything
`DURING_FRAG` commits therefore has no withdrawal path. For `tkaudt` that
would mean an append-only, hash-chained audit record derived from a torn
read, with `prev_hash` already advanced — a direct violation of the audit
invariant in `AGENTS.md`. For `tknorm`/`tkdedu` it would mean a published
fragment, a counted event, or a dedupe-table entry for a fragment that was
never really consumed.

`AFTER_CREDIT` as a publish path is the second trap, and it is a
liveness bug rather than a correctness one: `SHOULD_SHUTDOWN` runs at the
*top* of the loop, so a tile whose own event-count gate fired during
`AFTER_FRAG` never reaches the following iteration's `AFTER_CREDIT` and
silently drops its last event. Publishing in `AFTER_FRAG` puts the publish in
the same iteration as the fragment that triggered the gate.

### Staging Discipline

Each tile needs a place to stage that nothing else observes until
`AFTER_FRAG` commits. Two patterns are in use, and both are acceptable:

- **Scratch staging buffer** (`tknorm`, `tkdedu`): a scratch-allocated
  `PaymentMessage` the tile owns, plus `stage_valid` / `stage_sz`.
  `AFTER_FRAG` reads the verdict back off the staged message rather than
  carrying a separate flag.
- **Next uncommitted slot** (`tkaudt`): `DURING_FRAG` builds the record into
  `audit_records[audit_count]` — the slot *past* the committed region — and
  leaves `seq`, `prev_hash`, and `record_hash` unset. `AFTER_FRAG` stamps the
  chain fields and then commits by incrementing `audit_count`. This needed no
  extra scratch and therefore no footprint change, which is why it was chosen
  over the staging buffer the plan first proposed.

Required in both cases:

- `stage_valid` is cleared as the **first statement** of `DURING_FRAG`, before
  any validation can `return`. A stale flag lets the next `AFTER_FRAG` commit
  an abandoned fragment.
- `AFTER_FRAG` returns immediately when `stage_valid` is clear, and clears it
  before doing anything else.
- The committed boundary is a single scalar (`audit_count`, the publish
  itself) that only `AFTER_FRAG` advances. Nothing reads past it — including
  test accessors.

### Scratch Layout And Footprint Discipline

A stem tile's context, tables, and staging buffers all live in one scratch
object that the topology reserves. The supervisor and every self-exec'd child
rebuild the same topology independently, so both must derive a *byte-identical*
layout or every object placed after the tile's shifts and the tile reads a
corrupted workspace.

- **`.scratch_align` and `.scratch_footprint` describe the tile object, never
  `fd_stem`'s own stack scratch.** `fd_stem.c` generates
  `STEM_(scratch_align)`/`STEM_(scratch_footprint)` for its in[]/cr_avail[]
  block, aligned to `FD_STEM_SCRATCH_ALIGN`. Wiring those into the
  `fd_topo_run_tile_t` is a layout bug; each tile provides
  `*_scratch_align_tile` / `*_scratch_footprint_tile` instead. The unit test
  that asserts `scratch_align() == 8` exists to catch exactly that
  substitution.
- **Alignment is derived, not restated.** `*_scratch_align_tile()` returns
  `alignof(ctx_t)`, and `topob.c` reads it back through the wired
  `.scratch_align` field so the builder cannot lay the object out on an
  alignment the tile does not declare.
- **Runtime layout parameters arrive by C setter, before any footprint
  query.** `tkdedu`'s dedupe-table size is the one such parameter today.
  `topo_build.build()` calls `c_abi.tkdedu.setEventCount()` (and the
  `tknorm`/`tkaudt` equivalents) from the value in `TopologySpec`, which the
  supervisor writes once and every child reads. **Environment variables must
  never carry a layout parameter**: `getenv()` in `privileged_init` reads the
  child's own environment, which can differ from the supervisor's. Removing
  the last of those (`TKAUDT_EVENT_COUNT`) is part of this migration.
- **One resolution point per derived size.** `tkdedu_layout_event_count()`
  is the single function the footprint reservation and `privileged_init`'s
  pointer arithmetic both call, so the reserved block and the pointers into
  it cannot disagree. A gating count of 0 must still reserve the default
  table — the gate and the layout are different concerns.
- **`privileged_init` resolves link addresses and pointers; `unprivileged_init`
  resolves the CNC and the output dcache.** Both re-derive from `topo` and
  `tile`; neither allocates.
- **Fail closed on an unexpected link shape.** `tknorm` and `tkdedu`
  `FD_LOG_ERR` when `out_cnt != 1`, when the output link has no dcache, or
  when its MTU is below the message size. A stem tile must not infer a link
  shape it was not given.
- **Derive the input workspace from the input link's mcache object**
  (`stk_derive_wksp`), not from `fd_wksp_containing`: the latter depends on
  `fd_shmem_join_query_by_addr`, which is hard-coded to `ENOENT` on Windows,
  so every fragment was silently rejected there.
- **`topob.c` is the registration point for scratch requirements.**
  `tk_topob_tickoni_tile_scratch_requirements()` dispatches on tile id to the
  tile's align/footprint wrappers, `topo_build.zig` publishes them as the
  `tickoni.scratch_align`/`tickoni.scratch_footprint` pod properties, and
  `tk_topo_validate_tile_scratch()` checks after `fd_topob_finish` that every
  tile owning scratch was placed on its declared alignment.

### Cross-Process Accessor Rules

A stem tile's scratch lives in a shared workspace the supervisor also maps —
at a *different base address*. Anything the supervisor or a test reads out of
that scratch must therefore:

- **recompute offsets from the scratch base the caller passes in**, never
  follow a pointer the tile stored in its context. `tk_audit_records_of()` is
  the single definition of the record-array offset and is used by both
  `privileged_init` and the accessors; the first version of those accessors
  read `ctx->audit_records` and segfaulted the integration test.
- **expose named field accessors from the tile's own `.c` file**, so the C
  file remains the only place that knows its layout. No Zig `extern struct`
  may mirror a C struct to read tile state — the deleted `AuditContext` /
  `AuditHeader` / `AuditRecord` mirrors in `test_tile_tkaudt.zig`,
  hand-placed padding included, are the anti-pattern: they duplicated a
  contract that already has one source of truth (the header, from which the
  `audit_schema` module is generated by translate-c) and would have misread
  records silently the moment a C field moved.
- **abort on an out-of-range index rather than returning a sentinel.** `0` is
  a legitimate `seq` and `prev_hash`, so a sentinel turns a harness bug into
  a passing assertion.
- **never read past the committed boundary.** `tk_audit_record_count()`
  returns `audit_count`, not capacity; slots at or beyond it are staging.

### Observability: CNC Counters, Not fd_metrics

Stem tiles publish progress by writing `ulong` slots in their CNC app region
through `stk_publish_counter`, from `AFTER_FRAG`. Slot ownership is declared
once in `tile_registry.zig`'s `TileEntry.counters` and read back through that
same schema by `supervisor.zig`; a tile passes the index the registry assigns
rather than hand-rolling an `app[]` write. There is deliberately no slot-0
convenience wrapper, because slot 0 names a different counter on every tile.

These counters are **advisory progress and liveness, not evidence**. They are
plain single-writer stores with no ordering guarantee relative to the state
they describe, so a reader must treat a counter as a lower bound and poll to a
threshold rather than assert on an instantaneous value. Financial evidence
lives in the audit records and the replay capsule, never in a counter.

Link-level metrics (`frag_consumed`, polling/reading overrun counters,
backpressure) come from `fd_stem` itself and need no tile code.

### Health And Lifecycle

The generic tile path (`tile_process.zig`) joins its CNC in
`privileged_init`, transitions `BOOT -> RUN`, heartbeats during the
halt-wait loop, and signals `BOOT` again on clean exit. A stem tile reaches
the same supervisor-visible state through one helper in
`shim/stem_helpers.h`, so `supervisor.zig`'s `refreshProcessHealth` covers it
with the existing staleness model:

- `stk_cnc_liveness( cnc )` — called from the tile's
  `STEM_CALLBACK_DURING_HOUSEKEEPING`, which `fd_stem` runs once per
  housekeeping event of the loop, whether or not any fragment arrives or credit
  is available. It writes the CNC heartbeat and, on the first call (the first
  loop iteration), moves the CNC `BOOT -> RUN` with a compare-and-swap, so a
  `HALT` that arrived while the tile was booting is never overwritten. A tile
  whose loop is wedged, not scheduled or stopped stops advancing the heartbeat
  and is classified stale like a generic-path tile.

**Why `RUN` is signalled from the loop, not the run entry.** The stem's own
setup runs between the run entry and the loop, and its first call to
`fd_tempo_tick_per_ns` calibrates the tick rate for about half a second in
every tile process. `RUN` signalled from the run entry would make the tile
eligible for staleness during that setup and it would be classified stale
against the 100 ms default before it had looped once; this is what the first
implementation did, and the integration lane showed every stem tile with a
heartbeat about 500 ms old. The supervisor already classifies staleness only
for a tile that has reached `RUN`, so the boot interval is correctly outside
the model.

Every `tk_*_stem.c` defines `STEM_CALLBACK_DURING_HOUSEKEEPING` as
`stk_cnc_liveness( (ctx)->cnc )`. A stem tile that omits it is silently
outside the staleness model, so the integration lane checks every stem tile of
each topology, selected from `tile_registry.zig`, rather than a hand-kept list.

**The metric tile.** `metric` runs an `fd_stem` loop too, from
`fd_metric_tile.c`, which is shared with the native Firedancer binaries and so
cannot call Tickoni symbols. It is launched under `__tile-run` (launch mode
`tile` in the registry) but is dispatched to its own run tile, so it never took
the generic path's `RUN` and heartbeat either, and its CNC stayed at `BOOT`
for the whole run. Liveness reaches it through a hook:
`fd_metric_ctx_t.liveness`, NULL in native Firedancer, which its
`STEM_CALLBACK_DURING_HOUSEKEEPING` calls with `ctx->cnc` when set.
`shim/tk_metric_tile.c` sets it to `stk_cnc_liveness` in `tk_metric_run`. The
integration lane includes metric explicitly, since the registry's launch mode
does not identify it as a stem-loop tile.

**Which CNC belongs to which tile.** `ProcessState`'s per-tile CNC joins,
launch-spec addresses and suppression mask, and `built_topo.tile_infos`, are
indexed by Firedancer tile index, while the supervisor's `handles` and
`children` are indexed by topology position. `topo_build` registers the metric tile last, so in the payment
pipeline and the investment workflow metric and tkdiag swap places (positions
6/7 and 12/13). Every place that pairs a handle or child with its CNC
(`refreshProcessHealth`, the HALT in `stopProcess`, the per-tile snapshot, the
launch spec) goes through `ProcessState.tile_cnc_idx`, built once at start by
`(name, kind_id)`. Indexing the CNC joins by topology position instead would
attribute a stalled tkdiag to the metric tile, and tkdiag's own staleness would be judged from the
metric tile's CNC. Child processes already look their own CNC up by identity.

**Clock and units.** The CNC heartbeat is Tickoni's wrapping `u32`
milliseconds of the monotonic clock, and the supervisor compares it against
`ProcessOperations.now()` (`util.process.monotonicNanos()`). The helper reads
`tk_monotonic_nanos()` (`shim/os.c`) and write through `tk_cnc_heartbeat`
(`shim/tango.c`), the same two functions the Zig side uses. Do not call
`fd_cnc_heartbeat` with `fd_log_wallclock()` or any other clock: the tile would
look stale or fresh depending on the epoch difference.

**Staleness budget.** `fd_stem` runs the housekeeping event (this callback),
the per-input credit returns and the per-consumer credit receives round-robin,
one every `async_min` to `2 * async_min` ticks, with `async_min` the largest
power of two not above `STEM_LAZY / event_cnt` (`fd_tempo_async_min`,
`fd_tempo_async_reload`). The order is reshuffled each cycle, so two
housekeeping events can be nearly two cycles apart: the gap between heartbeats
stays below `4 * STEM_LAZY` plus the longest callback (below `2 * STEM_LAZY`
for a tile with no links, such as `tkdiag` in a topology without diagnostic
links) and averages about `STEM_LAZY`.
Every Tickoni stem tile sets
`STEM_LAZY` to 10 ms, so the worst gap is about 40 ms. The supervisor's default
stale threshold is 100 ms (five times the 20 ms heartbeat interval), which
leaves a factor of 2.5 at the worst case. Measured on an idle payment
pipeline, about 175 supervisor samples per tile gave a mean heartbeat age of 8 ms
and a maximum of 25 ms for tknorm, tkdedu, tkpoly and tkaudt. A configured
`heartbeat_stale_after_ns` of 40 ms or less can classify a healthy stem tile
stale; that is a misconfiguration, not a tile fault, and changing a tile's
`STEM_LAZY` changes the bound. A callback that blocks for longer than the
threshold (a synchronous disk or network wait inside `AFTER_FRAG`) also makes
the tile stale, which is the intended signal.

**Exit.** On HALT the stem returns, the process exits, and the supervisor
reaps it; nothing waits for the CNC to return to `BOOT`, so a stem tile does
not write `BOOT` on exit. A tile that stops itself (event count reached) leaves
the CNC at `RUN`, and the supervisor skips staleness for any tile it has
already reaped.

Counters and heartbeat are separate: counter slots (above) are advisory
progress; the heartbeat is the liveness signal. Neither is financial evidence.

### Registration Checklist For A New Stem Tile

A new stem tile is not complete until every one of these is updated. Each is
a separate dispatch or list; none is derived from another.

1. `src/tickoni/c_abi/shim/tk_<id>_stem.c` — the tile, including
   `STEM_CALLBACK_DURING_HOUSEKEEPING` as `stk_cnc_liveness`
   (see "Health And Lifecycle").
2. `src/tickoni/c_abi/topo_run/tk_<id>_stem.h` — `extern` run tile, the
   no-argument align/footprint wrappers, the `set_event_count` setter, the
   `tk_get_<id>_run_*` accessor set, and any state accessors.
3. `src/tickoni/c_abi/shim/topob.c` —
   `tk_topob_tickoni_tile_scratch_requirements()` dispatch arm.
4. `src/tickoni/c_abi/shim/tile_run.c` — `tile_is_<id>()` predicate and the
   `tk_topo_run_tile_simple()` arm selecting `TK_<ID>_RUN`.
5. `src/tickoni/c_abi/<id>.zig` — the FFI module: `extern fn` declarations,
   thin Zig wrappers, and the identity/footprint unit tests.
6. `src/tickoni/c_abi/c_abi.zig` and `build-lib/mod/modules.zig` — export and
   wire that module.
7. `build-lib/lib/shims.zig`, `build-lib/lib/topo_run.zig`,
   `build-lib/lib/codec.zig` — add the `.c` file to the shim source lists.
8. `build-lib/lanes/unit.zig` — register the FFI module as a unit-test root,
   or its identity tests never run.
9. `build-lib/lanes/integration.zig` — register the tile's integration test
   file in the infra lane.
10. `src/app/tickoni/tile_registry.zig` — `process_fn = null`, the counter
    schema, and `in_cnt`/`out_cnt`.
11. `src/tickoni/runtime/topo_build.zig` — the `setEventCount` call, if the
    tile takes a runtime layout or gating parameter.

That list is long because tile selection is open-coded twice in C
(`topob.c`'s scratch-requirement dispatch and `tile_run.c`'s run-tile
selection, both `strcmp` chains) alongside the Zig `tile_registry.zig` table
that already exists for exactly this purpose, and because the shim source list
is repeated in three build files. Reducing those to one source of truth is
worthwhile work; it changes the registry's role, so it needs sign-off before
it is attempted — see Engineering Principles in
[`AGENTS.md`](../../AGENTS.md).

### Test Standard

A stem tile carries two test layers. Both are required; neither substitutes
for the other.

**Unit (`test-unit-tk`, via the tile's `c_abi/<id>.zig` module).** These are
linkage and layout contracts, runnable without a pipeline:

- tile identity: `name` equals the tile id; `run`, `scratch_align`,
  `scratch_footprint`, `privileged_init`, `unprivileged_init` are non-null.
- `scratch_align()` equals `alignof(ctx_t)` — the assertion that catches the
  `FD_STEM_SCRATCH_ALIGN` substitution described above.
- `scratch_footprint() % scratch_align() == 0`, so the next object's offset
  does not depend on slack.
- footprint determinism: the same layout parameter yields the same
  reservation, a larger parameter reserves exactly the expected delta, and `0`
  selects the documented default (`tkdedu`).
- footprint parity with the `topob.c` dispatch
  (`tk_topob_tickoni_tile_scratch_footprint("<id>")`), so the builder and the
  tile cannot diverge.
- any pure function the tile exports for parity checking — `tknorm`'s
  `stable_event_hash_compute` against the Zig `stableEventHash`, field order
  and seed included.

**Integration (`test-integration-tk-infra`).** Real supervisor, real
processes, real workspace. Beyond the baseline (all events flow, no tile
crashes, CNC HALT stops the tile cleanly, sequential runs on one workspace),
every stem tile carries these *contract regression* tests, which exist to fail
if the callback split is ever undone:

- **final-event-published, with `event_count = 1`.** The only event is the
  final one, so a publish or commit moved back to `AFTER_CREDIT` fails
  outright instead of losing one event in a thousand. Assert through the
  downstream sink (`tkaudt` auditing the event proves the upstream tile
  published it).
- **exact counter equality, never an inequality.** `expectEqual(1,
  metrics.duplicates)` with exactly one injected duplicate catches
  double-counting; `expect(0 < duplicates)` does not.
- **committed state equals its counter.** `tkaudt`'s record count must equal
  `audited` exactly: both advance in `AFTER_FRAG`, so any drift means a
  record was appended without its counter or a counter was bumped for a
  fragment that produced no record.
- **self-exit on event-count exhaustion**, asserted with no `stopProcess`
  call before the assertion, so a clean self-exit (`.stopped`) is
  distinguished from a tile still spinning.
- **hash-chain shape** for a tile that chains: `prev_hash[0] == 0`,
  `prev_hash[k] == record_hash[k-1]`, `seq[i] == i`, every `record_hash`
  non-zero.
- **CNC liveness** (`test_stem_heartbeat.zig` for the payment pipeline and
  `test_tile_tkagnt.zig` for the 14-tile investment workflow, which contains
  every stem tile kind; both use `stem_liveness.zig`): every stem tile of
  the topology, chosen from `tile_registry.zig` by launch mode, reaches CNC
  `RUN` with an advancing heartbeat while it is idle, and a tile frozen with
  `SIGSTOP` is classified `.stale` while its siblings are not. This is what
  fails if a stem tile omits its
  `STEM_CALLBACK_DURING_HOUSEKEEPING`. A `.running` state alone is not evidence
  of progress.

Supporting discipline for these tests:

- Read tile state only through the C accessors, with the scratch base from
  `topoObjLaddr(topo, tile_obj_id)`, and read it **before** `stopProcess`,
  which leaves every CNC join and detaches the workspace.
- Take ports from `util.nextMetricPort()` and workspace names from
  `util.nextWorkspaceName()`. The port helper probes each candidate because
  the integration lane's binaries run sequentially with nearby pids and a
  metric tile holds its port for its whole lifetime; handing out a bound port
  surfaces as an unrelated `.crashed` tile.
- Gate test-only injection on `runtime/test_build.zig`'s `enabled`, never on
  `@import("builtin").is_test`. Process-mode tiles run inside the
  `tickoni-supervisor` *executable*, where `is_test` is false, so
  `is_test`-gated injection is silently dead in every process-mode test.
- Describe injection as data, not as a boolean: `duplicate: ?DuplicateConfig`
  (`{ offset, source }`) says which event duplicates which, which is what
  lets the test assert an exact count. The replaced `inject_duplicate: bool`
  hid that relationship in `syntheticPayment`.
- A throwaway verification script is not a substitute. If a change seems to
  need one, the system is missing a test — wire it to the right lane in
  [`../execution/testing-tickoni.md`](../execution/testing-tickoni.md).

**Not testable from the integration lane:** the overrun path itself. Reaching
it requires a producer that violates `fd_stem` flow control. The guarantee
rests on the callback contract and on the single commit point, not on a test,
which is exactly why the split is stated as an invariant rather than left to
review.

### Known Deviations And Debt

These are current-state facts about the three migrated tiles, recorded so they
are not mistaken for the standard. None is a blocker for the migration; each
needs a deliberate pass.

- **`tkaudt` warns and drops when its record ring is full**
  (`audit_count >= TKAUDT_AUDIT_CAPACITY`, 16384): `DURING_FRAG` logs
  `FD_LOG_WARNING` and returns, so no record is written *and* `audited` stops
  advancing, so `STK_EVENT_EXHAUSTED` never fires and the tile spins until
  HALT. `tkdedu` in the same situation `FD_LOG_ERR`s and dies. For an
  append-only audit chain, crash-only is the correct posture and
  warn-and-drop is a fail-open on a resource bound; today's configured event
  counts (10 000 default, 8 in tests) keep it latent. The two tiles must
  agree, and the agreement should be fail-closed.
- **`tkaudt` records are in-memory only.** The ring lives in tile scratch and
  is never persisted; the append-only, hash-chained invariant holds for the
  run, not across runs. Durable audit storage is a separate phase.
- **`tknorm`'s `idle_ticks > 10000L` shutdown term is dead.** `idle_ticks` is
  zeroed in `privileged_init` and never incremented, so the term can never
  fire. Either increment it from a `DURING_HOUSEKEEPING`/`AFTER_CREDIT`
  callback with a stated idle policy, or delete it — a shutdown condition
  that cannot fire is worse than no condition, because it reads like one.
- **Unused context fields.** `tile` is declared in `tknorm`/`tkdedu` and never
  assigned (only `tkaudt` sets it). `tknorm`'s `output_chunk` is kept with a
  comment about preserving the scratch layout, but the footprint is derived
  from `sizeof(ctx_t)` by the same function the supervisor and every child
  call, so removing the field changes the reservation consistently everywhere.
  The stated reason does not hold.
- **`tkdedu`'s `processed` is not exposed.** Its registry schema maps only
  `app[0] = duplicates`, so the count that drives its shutdown gate is
  invisible to the supervisor. Either publish it or document that the gate is
  unobservable.
- **Three parallel `set_event_count` globals** (`tkdedu_set_event_count`,
  `tknorm_set_event_count`, `tkaudit_set_event_count`), identical in shape,
  with only `tkdedu`'s affecting layout. This is the shared-value-with-one-
  source-of-truth rule in `AGENTS.md` pointing at a single parameter-passing
  mechanism.
- **The `allow_shutdown` guard is pre-satisfied, so it never fires.** Both
  boot paths set the flag before the harness call — `tile_main.zig`'s
  `stemRun` for stem tiles, `tile_process.zig` for generic ones — and nothing
  clears it, so `fd_topo_run_tile`'s "run loop returned" `FD_LOG_ERR` cannot
  distinguish an intentional exit from an unexpected return out of the stem
  loop. Each stem tile's trailing `tile->allow_shutdown = 1` is therefore
  dead code, and the comments beside it in all three tiles describe harness
  behavior (a reset before `run`) that does not exist. Whether the pre-set is
  removed so the guard works again is an orchestration decision, not a
  per-tile one.
- **`tkdedu` dedupe is a linear scan** over `seen_count` entries per
  fragment, i.e. O(n²) over a run. Correct and bounded, but not a throughput
  design; a hash table is the obvious successor and changes no contract.
- **Stale forward-looking plans.** Several plans written before the contract
  still prescribe publishing in `AFTER_CREDIT`
  (`plans/v2.10-s14-fd-stem-migration.md`,
  `plans/v2.22-s5-fd-stem-migration.md`,
  `plans/v2.10-s14-tkrepl-capsule-io.md`, and the story
  `doc/strategy/roadmap/stories/v2.10-s14.md`). The contract wins; those
  need a product-owned pass before `tkpoly`, `tkings` or `tkrepl` migrate.
  `plans/v2.10-s14-tkdiag-fan-in.md` had the same defect and got that pass
  before it was implemented (its "Resolved Design" supersedes its sketches).
  Tracked in
  [`../execution/tile-delivery-status.md`](../execution/tile-delivery-status.md).
- **`plans/v2.NN-sXX-tkaudt-stem-contract.md` overstates its verification.**
  Its "Verification" item 1 claims a `_Static_assert` fails the build if
  `tk_audit_ctx_t` grows; no such assert exists in `tk_audit_stem.c`. Its
  "Files" entry also describes the test's `AuditContext` mirror gaining
  `stage_valid`, which a later commit superseded by deleting the mirrors.
  The code is correct; the plan's record of it is not.

### Anti-Patterns

- Committing anything in `DURING_FRAG` — a counter, a table write, a chain
  advance, a publish.
- Publishing in `AFTER_CREDIT` on a tile whose shutdown gate is its own
  progress.
- `STEM_BURST` smaller than the tile's real maximum publishes per iteration.
- Wiring `fd_stem`'s generated `scratch_align`/`scratch_footprint` into the
  `fd_topo_run_tile_t`.
- Reading a layout parameter from the environment in `privileged_init`.
- Restating a size, alignment, or offset in a second place instead of calling
  the one function that owns it.
- A Zig `extern struct` mirroring a C struct to read tile state.
- Following a context-stored pointer from another process.
- Entering another tile's generated `*_run`.
- Asserting an inequality where the test knows the exact expected count.
- Gating test-only code on `@import("builtin").is_test`.

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
- one supervisor-spawned OS process per tile; Firedancer lifecycle execution
  begins only after the child already exists
- crash and shutdown semantics
- tile-specific stem-loop guard patterns for shutdown, housekeeping, credit,
  and heartbeat
- Tickoni-owned process placement validation and `cpu_idx` topology metadata via
  `tk_topob_auto_layout()`; actual child-process affinity, when enabled, must be
  applied explicitly rather than inherited from Firedancer's pthread launcher

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

7. **Record CPU placement metadata:** `topo_build.zig` derives a `cpu_idx_arr`
   from each Tickoni `CpuPlacement` and passes it to
   `tk_topob_auto_layout(topo, cpu_idx_arr)`. The shim copies those values into
   `topo->tiles[]` before `fd_topob_finish()`:

   ```c
   void
   tk_topob_auto_layout( void * topo, ulong const * cpu_idx_arr ) {
     fd_topo_t * t = (fd_topo_t *)topo;
     for( ulong i=0UL; i<t->tile_cnt; i++ )
       t->tiles[ i ].cpu_idx = cpu_idx_arr[ i ];
   }
   ```

   Tickoni does not append its tile names to Firedancer's validator priority
   arrays. The supervisor validates placement against the live host affinity
   mask, while this adapter records the resulting topology metadata. The direct
   per-process `fd_topo_run_tile()` path does not call Firedancer's
   `run_tile_thread()` affinity setup, so `cpu_idx` alone is not proof that a
   child process was pinned.

8. **Run inside the child:** The Tickoni supervisor first spawns one OS process
   for the tile. That child passes `topo` and its selected `topo->tiles[]` entry
   to `fd_topo_run_tile()`. The harness joins workspaces, fills link pointers,
   enters the sandbox, registers metrics, and invokes the tile callbacks on the
   child's calling thread. It does not spawn another tile thread.

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

**What changes upstream:** Nothing for Tickoni placement. The Tickoni-owned
`tk_topob_auto_layout()` shim consumes the harness-provided placement array and
writes `tile->cpu_idx` without modifying Firedancer's validator priority lists.
The relevant upstream topology files remain covered by `engine-check-changes`
for drift detection.

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
│  Tickoni supervisor.zig                         │
│  - bootLite: version + log + shared memory      │
│  - spawn and track one child process per tile   │
└─────────────────────────────────────────────────┘
                          │ self-exec launch spec
┌─────────────────────────────────────────────────┐
│  Tickoni tile_process.zig / tile_main.zig       │
│  - rebuild matching topology                    │
│  - full fd_boot: caller becomes tile 0          │
│  - call fd_topo_run_tile through c_abi          │
│  - no additional tile pthread                   │
└─────────────────────────────────────────────────┘
                          │ calls through c_abi bridge
┌─────────────────────────────────────────────────┐
│  c_abi bridge (src/tickoni/c_abi/)              │
│  - boot.zig      + shim/util.c       → fd_boot  │
│  - wksp.zig      + shim/wksp.c       → fd_wksp_*│
│  - topo_run.zig  + shim/topo_run.c   → lifecycle│
│  - topob.zig     + shim/topob.c      → topology │
│  - tango wrappers                       → IPC    │
│  - tile-specific audit/metric shims     → stem  │
└─────────────────────────────────────────────────┘
                          │ links against
┌─────────────────────────────────────────────────┐
│  Firedancer infrastructure                      │
│  src/disco/{topo,stem,metrics}                  │
│  src/tango/{mcache,dcache,fseq,cnc,fctl,tempo}  │
│  src/util/{sandbox,util}                        │
└─────────────────────────────────────────────────┘
```

The diagram shows the current process boundary: Tickoni owns child-process
orchestration, while each child reuses the Firedancer lifecycle and selected
per-tile stem implementations through the C ABI. No thread-per-tile dispatcher
is inserted between the supervisor and `fd_topo_run_tile()`.

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
  `exclusive`, `shared`, and `floating`, plus validation that enforces
  exclusive collision detection and shared/exclusive co-existence rules.
  Placement is process scheduling policy, not evidence of a thread-mode
  topology. The current supervisor validates and serializes placement, but the
  direct child call to `fd_topo_run_tile()` does not use Firedancer's
  `run_tile_thread()` affinity path. Any process pinning must therefore be
  applied explicitly to the child process and verified independently; it must
  not be inferred from `tile->cpu_idx`.

#### 11-Item Reuse Categorization (from audit 8.md)

Firedancer infrastructure decomposes into 11 reuse categories. The first 4
require only `tk_*` shims (already covered or trivial). The remaining 7
require deliberate Tickoni implementation or are explicitly not reused:

1. **`fd_topo_run_tile` harness** — directly reused. `tile_process.zig` and
   the dedicated stem-tile path rebuild the topology, select one tile, and call
   the harness inside the supervisor-spawned child process.

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
   The registry is keyed by tile ID and owns: child launch mode, process-mode run callback
   (`ProcessFn`), counter schema
   (`CounterSchemaEntry`), expected link cardinality (`in_cnt`/`out_cnt`),
   and diagnostics naming. Beyond lookup and cardinality, the registry also
   owns **process-mode dispatch wiring** (link-joining shape per tile — each
   process-mode entry function joins the correct consumer/producer links and
   calls into the pipeline stage) and **configured-topology validation**
   (`validate()` checks that every configured tile is registered, identities
   are unique, and per-tile channel counts match the registry). Registered
   tiles may be absent from a topology. No supervisor, process dispatcher, metrics reader, or test
   harness should recreate these mappings.

6. **Heartbeat semantics** — `cnc_update` / `FD_CNC_HEARTBEAT` — the pattern is
   proven; Tickoni's `tile_process.zig` already implements heartbeat during work.

7. **Shutdown semantics** — `cnc` shutdown flag checked inside tile work loop,
   not only outside — preserved in Tickoni.

8. **Crash-only lifecycle** — the generic pipeline path preserves the
   lifecycle through Tickoni callbacks invoked by `fd_topo_run_tile`. Stem tiles
   preserve it through their own stem specialization and CNC HALT rule.

9. **Stem loop (multi-input multiplexer)** — selectively reused. Tickoni does
   not use one generic stem runner for every tile. `tkaudt` compiles a private
   `tkaudt_run`; `metric` enters the specialization owned by
   `fd_tile_metric.run`. Ordinary process tiles may continue to use
   Tickoni-owned bounded loops. A specialization generated for one context must
   never be called for another tile.

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
- **fd_topob_auto_layout()** — hardcodes validator tile name arrays. Tickoni
  does not call this policy function or add Tickoni names to those arrays; its
  `tk_topob_auto_layout()` wrapper copies explicit Tickoni placement metadata
  into the topology.

**Verdict:** Use the generic `fd_topob.c` construction and validation functions
with the three optional flags set to zero. Keep Tickoni placement policy in the
Tickoni-owned wrapper and supervisor, without importing validator tile names or
Firedancer's pthread-launch affinity path.

#### Structural Resolutions (from v2.14.s8-wip.md)

The following structural tensions were identified during S8 planning and have
been resolved:

1. **Scope too large for one story:** S8's 10 tasks span registry, links, c_abi
   bridge, lifecycle migration, sandbox/seccomp, stuck-tile detection, parent-path
   investigation, and engine drift guard. Resolved by splitting: S8 handles the
   core tasks, T11 handles tempo/fctl shims.

2. **tile_process.zig stays as product code:** The original resolution kept
   `tile_process.zig` as the product-level self-exec boot/heartbeat/halt entry.
   The current implementation preserves that ownership while delegating the
   lifecycle sequence to `fd_topo_run_tile` through the adapter. Generic tiles
   supply Tickoni callbacks; dedicated stem tiles enter their own specialization.
   `tile_process.zig` is therefore not a second parallel harness.

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
- process-mode run callback (`ProcessFn`), if any
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
