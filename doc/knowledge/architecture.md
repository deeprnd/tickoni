# Tickoni Architecture

The infrastructure thesis:

> Agentic finance will only be trusted when every action is controlled, every decision is replayable, and every outcome is auditable.

Tickoni is a high-throughput AI harness for agentic finance. The architecture
starts from financial event integrity, then adds controlled agents after the
runtime can prove bounded processing, audit, replay, and isolation.

The implementation rule is:

```text
runtime first
cases second
agents third
privileged actions last
```

AI is not part of the deterministic event critical path. A financial event must
be ingestible, normalized, audited, and replayable before any agent investigates
the resulting case.

## System Layers

Tickoni has a Firedancer infrastructure layer and a Tickoni AI-harness layer.
The TPS claim comes from running financial event processing on Firedancer's
core tile infrastructure: bounded shared-memory queues, explicit topology,
workspaces, sandboxed tile processes, low-overhead metrics, and tile-local
network services. The web application, storage systems, agent daemon, LLM
server, the approved execution ledger, and trading APIs are attached systems around that runtime.
They do not replace the runtime.

```text
┌────────────────────┐      ┌──────────────────────┐      ┌─────────────────────┐
│      Next.js       │<────>│   Zig CaseOps API    │<────>│  Markdown + the analytics store  │
│ CaseOps operator UI│      │  tkapi HTTP + WS     │      │ memory + analytics  │
└────────────────────┘      └──────────┬───────────┘      └─────────────────────┘
                                       │
                                       v
┌───────────────────────────────────────────────────────────────────────────────┐
│                         Tickoni AI-harness tiles                              │
│                                                                               │
│  tkapi                                                                        │
│    CaseOps API tile: board reads, evidence reads, approvals, audit timeline   │
│                                                                               │
│  tkings -> tknorm -> tkdedu -> tkcase -> tkpoly -> tkaudt                     │
│    ingestion, normalization, dedupe, deterministic cases, policy, audit       │
│                                                                               │
│  tkdisp -> tkagnt -> tkmodl                                                   │
│    bounded agent runs and governed model access                               │
│                                                                               │
│  tkagnt -> tktool -> tkadpt                                                   │
│    finance-native tool broker and signed/stub adapters                        │
│                                                                               │
│  tkrepl, tkmetr, tkdiag, future tkexec                                        │
│    replay, metrics, diagnostics, approved privileged execution                │
└───────────────────────────────┬───────────────────────────────────────────────┘
                                │
┌───────────────────────────────┴───────────────────────────────────────────────┐
│                    Firedancer infrastructure tiles/substrate                  │
│  tango queues, topology, workspaces, sandbox, metric/diag, fd_http_server,    │
│  bounded polling, tile-local networking, seccomp/Landlock, crash-only model   │
└───────────────────────────────────────────────────────────────────────────────┘

Governed external systems:

  tkmodl  <────>  LLM server / model providers
                   local OpenAI-compatible server, OpenAI, Anthropic,
                   Qwen, DeepSeek, future local GPU inference

  daemon  <────>  local agent CLIs on the operator/developer machine
                   Claude Code, Codex, GitHub Copilot CLI, OpenCode, OpenClaw,
                   Hermes, Gemini, Pi, Cursor Agent, Kimi, Kiro CLI

  tkadpt  <────>  financial read/proposal APIs
                   payment processors, crypto venues, broker or stock-exchange
                   gateways, risk systems, compliance systems

  tkexec  <────>  approved mutation backends
                   the approved execution ledger balances, transfers, fills, accounting,
                   approved payment/trading execution
```

The **Firedancer infrastructure layer** is the systems layer Tickoni reuses for
ultra-throughput execution: `src/tango` queues, topology/workspace discipline,
tile lifecycle, sandboxing, low-overhead metric and diagnostic paths,
`fd_http_server` for tile-local HTTP/WebSocket service, bounded polling loops,
and crash-only behavior. Tickoni should reuse or wrap Firedancer infra tiles
and primitives where they are generic.
For the detailed orchestration boundary, see
[`tile-orchestration.md`](tile-orchestration.md).

Tickoni application, runtime, tile, schema, codec, and business logic is Zig.
Firedancer and vendored C code are reachable only through one explicit bridge:
Zig code calls narrow Zig wrappers in `src/tickoni/c_abi/*.zig`; those wrappers
declare private `extern fn tk_*` symbols; the `tk_*` symbols are implemented by
Tickoni-owned C shims under `src/tickoni/c_abi/shim/**`; only those shim files
include Firedancer or vendored C headers. This applies to Tango, Util,
Workspace, Sandbox, Ballet protobuf/hash primitives, and vendored JSON. C code
outside `src/tickoni/c_abi/shim/**` is not part of the canonical Tickoni
architecture and should be treated as boundary debt to remove, not as a pattern
to extend.

Tickoni reuses generic Firedancer tiles and infrastructure primitives, but Solana validator tiles and Solana schemas are not Tickoni framework concepts. That generic Firedancer reuse is what lets Tickoni position itself as an ultra-TPS financial event harness instead of a normal web backend with agents attached.

The **Tickoni AI-harness tiles** own financial correctness. Financial events
enter `tkings`, become canonical in `tknorm`, are deduplicated in `tkdedu`,
become deterministic cases in `tkcase`, are policy-checked by `tkpoly`, and
are ordered into the audit chain by `tkaudt`. Agent, model, tool, adapter,
replay, metrics, diagnostics, and future execution paths are additional tiles
on top of the same engine substrate.

The **Zig CaseOps API** is the HTTP/WebSocket control-plane edge implemented
inside Tickoni. It should serve ingestion and CaseOps APIs, authenticate
clients, fan out live state, and coordinate operator approvals, but it must not
own normalization, deduplication, policy decisions, model access, adapter
access, or financial execution. Those stay with the owning Tickoni tiles.

The **Markdown memory/policy store** holds human-authored operating context:
memory, theses, policies, company notes, runbooks, and case narratives. These
files are useful context for agents and operators, but they are not
deterministic runtime truth by themselves.

The **analytics store** holds market data, analytics, backtests,
research tables, local projections, and investigation datasets. It is optimized
for analytical reads and reproducible research, not authoritative balances or
money movement.

The **approved execution ledger** holds balances, transfers, fills,
accounting entries, and approved ledger-style financial state. Agents, the UI,
and non-executor tiles do not connect to the approved execution ledger directly. `tkexec` owns
approved execution after policy, audit, replay, and human approval are already
proven.

The **LLM server and model providers** are external inference backends. Agents
do not call them directly. `tkmodl` owns configured endpoints, model allowlists,
timeouts, context limits, retry limits, token accounting, budget enforcement,
request/response audit, and replay substitution.

The **Agent Daemon** runs on the operator or developer machine and launches
approved local agent CLIs or SDKs. It is useful for integrating Claude Code,
Codex, GitHub Copilot CLI, OpenCode, OpenClaw, Hermes, Gemini, Pi, Cursor
Agent, Kimi, Kiro CLI, or similar tools, but it is not a trust boundary. The
daemon receives scoped work and returns auditable outputs; it does not receive
database credentials, model credentials, ledger credentials, trading keys, or
raw authority over the runtime.

The **trading, crypto, payment, risk, and compliance APIs** sit behind
`tkadpt` for reads and proposals, and behind future `tkexec` for approved
mutations. A trading agent may recommend or propose within market, venue,
instrument, sector, amount, frequency, and approval limits. It must not place
orders directly.

## Product Shape

```text
Financial event streams
  payments / accounting ledger / fraud / compliance / disputes
        |
        v
Tickoni event runtime
  Zig AI-harness tiles on Firedancer infrastructure
  ultra-TPS bounded queues, deterministic processing, explicit ownership
        |
        v
Policy and audit boundary
  capability checks, denials, append-only records, replay capsules
        |
        v
Controlled agent harness
  role agents, model gateway, tool broker, signed adapters
        |
        v
CaseOps board
  case lifecycle, evidence, approvals, audit timeline
        |
        v
Privileged action executor
  disabled by default, approved mutations only
```

## Phase 0 Runtime Spike

Current implementation status: the Zig supervisor runs the Phase 0 financial
event spike in dev/test mode:

```text
synthetic payment stream
  -> tkings
  -> tknorm
  -> tkdedu
  -> tkpoly
  -> tkaudt

tkrepl -> deterministic re-injection path
tkmetr -> runtime metrics
tkdiag -> process and queue diagnostics
```

The spike proves:

- bounded channel depths
- stable event hashes
- append-only audit records
- deterministic replay comparison
- visible backpressure and queue health
- audited malformed-event rejection
- crash-only supervisor behavior
- no Solana validator tiles in the Tickoni topology

The current implementation uses heap-backed in-process bounded queues. The
next runtime hardening step is to replace those spike rings with the selected
shared-memory backing while keeping the same tile identities and link answers.

That hardening step must use real Firedancer-style substrate, not just Zig
workers named as tiles. For tier scope, see
[`platform-tiers.md`](platform-tiers.md). In Linux full-runtime process mode:

- each configured tile runs as a supervisor-managed OS process with its own
  address space; a thread-only topology may remain for fast dev/unit tests but
  does not satisfy process-isolation acceptance;
- correctness-bearing links use Firedancer Tango `mcache`/`dcache` shared
  memory, with `fseq` or `fctl` progress/flow-control state so reliable links
  backpressure instead of dropping;
- tile lifecycle exposes boot, heartbeat, halt, and fail state through
  `src/tango/cnc` or a narrow Tickoni wrapper around the same control model;
- workspaces, objects, join modes, and process-start behavior follow
  Firedancer `src/disco/topo` patterns through Tickoni-owned wrappers;
- seccomp, Landlock, file-descriptor discipline, and process isolation reuse
  `src/util/sandbox` where the Linux full-runtime tier can support them.

CPU placement is Tickoni-owned policy. Tickoni may support `exclusive`,
`shared`, and `floating` placement modes; it must not inherit a hard Firedancer
validator assumption that every tile owns an exclusive CPU core. Shared-core
placement means multiple tile processes intentionally reuse a CPU, not that
tiles share a process or address space. Undeclared CPU oversubscription,
malformed CPU ids, and unavailable CPU ids fail closed.

Do not add Tickoni product fields or financial semantics to upstream-hot
Firedancer topology structs. Keep Tickoni tile IDs, placement policy, financial
contracts, and product schema in `src/tickoni/**`, with narrow C ABI wrappers
under `src/tickoni/c_abi/` for reused Firedancer substrate.

### How Firedancer Reuse Actually Works

`src/tickoni/c_abi/` is composition over Firedancer, not a parallel
reimplementation. Each Zig wrapper file (`queue.zig`, `dcache.zig`,
`fseq.zig`, `cnc.zig`, `wksp.zig`, `process.zig`, ...) exposes lower-camel Zig
functions to the rest of Tickoni and keeps its `extern fn tk_*` declarations
private. Those `tk_*` symbols resolve to Tickoni-owned C shims in
`src/tickoni/c_abi/shim/**`. The shims call real Firedancer C implementation
for object lifecycle, footprint/alignment math, workspace setup, sandboxing,
command-and-control state, protobuf/tokenizer helpers, hashing, and vendored
JSON. The build links upstream `libfd_tango.a`, `libfd_util.a`,
`libfd_ballet.a`, or related libraries only so the shim object files can
resolve their upstream calls; Tickoni source must not call or bind `fd_*`
symbols directly.

A small number of hot-path functions have no exported symbol to bind at all.
Firedancer declares these as `static inline` in their headers (`fd_mcache.h`,
`fd_fseq.h`), and C's `static inline` has no exported symbol in the compiled
`.a` — there is nothing for an `extern fn` to bind to. Confirmed empirically
with `nm` against the built `libfd_tango.a` and `libfd_disco.a`: zero matches
for `mcache_publish`, `fseq_query`, `line_idx`, or Firedancer's own
higher-level `fd_stem_publish`/`fd_stem_advance`.

The standing approach is a thin, non-inline Tickoni-owned shim under
`src/tickoni/c_abi/shim/**` that calls the real Firedancer function and does
nothing else. The current split is `tango.c`, `util.c`, `wksp.c`,
`sandbox.c`, and `ballet.c`; `firedancer.h` exposes only Tickoni-owned `tk_*`
types and declarations to Tickoni-owned C shim consumers. Zig code still goes
through `src/tickoni/c_abi/*.zig`, not through this header. `queue.zig`'s
`mcacheLineIdx`, `mcachePublish`, and `fragMetaSeqQuery`, and
`shm_link.zig`'s `fseq` query/update helpers, bind to `tk_*` symbols via
private `extern fn` declarations rather than reimplementing the logic natively
in Zig. No Firedancer file is edited; the shim files are compiled and linked
alongside upstream libraries via `linkTickoniFiredancer` in `build.zig`.

This also explains why `src/disco/stem` (Firedancer's tile polling/
backpressure framework) is not linked directly, even though it looks like
exactly the abstraction process-mode links need. `fd_stem_publish` itself
just calls the same inline `fd_mcache_publish` underneath, so linking it
would not add real reuse — it would only add `fd_stem`'s "credit"/burst
accounting, which is tied to `fd_topo_t`'s full validator tile-housekeeping
model. Tile-topology.md's [Reuse Boundary](tile-topology.md#reuse-boundary)
already rules that model out for Tickoni (no Tickoni fields on
`fd_topo.h`, no `fd_topo_run_tile` validator lifecycle). `fd_stem` stays a
design reference for the bounded-polling/backpressure pattern, not a linked
dependency.

The working rule: default to a real Firedancer primitive behind a `tk_*` shim
even at FFI cost. Whether the upstream function is exported, `static inline`,
or macro-like does not change the Tickoni boundary: Tickoni Zig calls a Zig
wrapper, the Zig wrapper calls `tk_*`, and the C shim calls Firedancer.

```text
┌─────────────────────────────────────────────────────────────────────┐
│ Tickoni Zig logic                                                    │
│ app, runtime, tiles, schema, codec, policy, audit, replay            │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ lower-camel Zig calls
                               v
┌─────────────────────────────────────────────────────────────────────┐
│ src/tickoni/c_abi/*.zig                                              │
│ narrow Zig wrappers with private extern fn tk_* declarations         │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ tk_* symbols only
                               v
┌─────────────────────────────────────────────────────────────────────┐
│ src/tickoni/c_abi/shim/**                                            │
│ Tickoni-owned C shim; only layer that includes Firedancer/vendored C │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ fd_* / cJSON_* calls contained here
                               v
┌─────────────────────────────────────────────────────────────────────┐
│ Firedancer and vendored C substrate                                  │
│ Tango, Util, Workspace, Sandbox, Ballet, protobuf, hash, JSON        │
└─────────────────────────────────────────────────────────────────────┘
```

See [rant/static-inline-and-ffi.md](rant/static-inline-and-ffi.md) for why
this is the standing default over the alternatives.

### Integration Direction And Porting Rules

The integration boundary between Tickoni and Firedancer is strictly one
directional: Tickoni Zig calls down into Firedancer C through the shim layer.
Tickoni code never embeds, includes, or depends on Firedancer source files
directly. The call graph is:

```
Tickoni Zig  -->  Zig wrappers (c_abi/*.zig)  -->  C shims (c_abi/shim/**)  -->  Firedancer C
```

This directionality is an invariant. If a requirement forces Tickoni to depend
on something that breaks this direction, the requirement changes, not the
direction.

#### When to port embedded Firedancer code to Zig

Firedancer contains embedded implementation blocks inside its own source trees
(`src/ballet/**`, `src/util/**`, `src/tango/**`, etc.) that serve Tickoni
needs — cryptographic primitives, encoding helpers, memory layout utilities,
hash functions, and similar low-level routines. The default path is to call
them through the existing `tk_*` shim layer.

However, when such embedded code carries platform or resource assumptions that
conflict with Tickoni's operational requirements, it must be ported to Zig
instead of routed through C. The trigger conditions are:

- **Linux-only constraints** — the code assumes `mmap` with `MAP_HUGE`,
  seccomp filters, `prctl` syscalls, `/proc` filesystem access, NUMA node
  enumeration, CPU affinity via `sched_setaffinity`, or any other Linux API
  that is not portable to the retail tier. If the Tickoni requirement is to
  run on non-Linux platforms (retail tier, CI parity, developer machines), the
  Linux-specific path must become a Zig implementation and the shim routes to
  the Zig version.

- **High RAM footprint** — the embedded code allocates fixed-size buffers,
  alignment padding, or workspace objects that scale poorly on constrained
  memory. Examples: `wksp_alloc` calls multiplied by link depth,
  `fd_shmem_gaddr` lookups that require pre-reserved shared-memory regions,
  large static tables in the binary, or SIMD-accelerated paths that duplicate
  input buffers. If the allocation pattern causes OOM on less-than-16 GB
  systems or prevents the retail tier from fitting in normal-page workspaces,
  port the allocation strategy to Zig with bounded, explicit sizing.

- **Validator-specific state** — the code reads or writes Solana validator
  topology structs, keyswitch objects, tower state, or consensus-adjacent
  fields. These must never leak into Tickoni; port only the generic
  computation (hashing, encoding, math) to Zig and drop the validator state
  references.

When a block is ported to Zig:

1. The Zig implementation owns the logic end-to-end. No `extern fn` in the
   shim calls back into the original Firedancer source.
2. The smaller helper functions that the ported block depended on (hash
   routines, byte-swappers, bit-packing helpers, alignment math) still route
   through Firedancer via the existing `tk_*` shim. The shim becomes a
   fan-out: the top-level ported function lives in Zig; the leaf primitives
   it calls are still `tk_*` symbols that resolve through `c_abi/shim/**` to
   the real Firedancer implementation.
3. The Zig port carries a comment referencing the original Firedancer source
   file, line range, and function name it replaced, so future reviewers can
   diff behavior across upstream bumps.

#### Decision flow

```
Does the Firedancer code carry Tickoni-relevant logic?
  |
  +-- Yes --> Does it have Linux-only or high-RAM or validator-state deps?
  |             |
  |             +-- Yes --> Port the top-level logic to Zig.
  |             |             Keep leaf primitives (hash, bits, math) as
  |             |             tk_* shims into Firedancer.
  |             |
  |             +-- No  --> Call through the existing tk_* shim.
  |
  +-- No  --> Do not reuse. Tickoni owns its own implementation.
```

#### What this prevents

- **Cross-platform build breakage** from Linux-only syscalls buried inside
  a "just a utility" header pulled in by a shim.
- **Memory OOM in retail or CI lanes** where large-page workspaces are not
  available but the C shim still demands them.
- **Validator semantics bleeding into Tickoni** through shared structs or
  zeroed union fields that look harmless until a future bump changes the
  memset order or the harness starts reading a field that was previously
  unused.

The rule is not anti-Firedancer. It is pro-boundary: every Tickoni
requirement that conflicts with Firedancer's assumptions gets a Zig
implementation; every compatible leaf primitive stays in Firedancer and
routes through the shim.

### How the Firedancer Harness Works

The Firedancer harness at `src/disco/topo/fd_topo_run.c` is a single function
(`fd_topo_run_tile`) that manages 6 layers:

1. **Launch** — `fd_topo_run_tile_t` struct with `privileged_init`,
   `unprivileged_init`, `run`, seccomp, and resource limits
2. **Lifecycle** — join workspaces → privileged_init → sandbox → fill tile
   → unprivileged_init → run
3. **Topology** — `fd_topo_t` / `fd_topo_tile_t` (Solana-shaped at the union
   level, but the harness reads only `name`, `kind_id`, `cpu_idx`,
   `allow_shutdown`, `metrics` — none are Solana union fields)
4. **Shared memory** — `mcache`, `dcache`, `fseq`, `cnc`, `fctl` (already
   wrapped by Tickoni's `c_abi` bridge)
5. **Execution** — stem loop (`fd_stem.c`) — multi-input multiplexer with
   callbacks (not reused by Tickoni; see tile-orchestration.md)
6. **Supervisor** — `run.c` fork+exec + PID namespace + `wait4` (not reused;
   Tickoni keeps its own self-exec supervisor)

The harness has a clear contract: take a `fd_topo_run_tile_t` descriptor, call
the callbacks in order, enforce sandbox and lifecycle ordering. Tickoni's own
`tile_process.zig` is an equivalent but independent implementation of the same
pattern, using the same Firedancer primitives through the `c_abi` bridge. The
two implementations are structurally parallel — Tickoni does not need to replace
`tile_process.zig` with `fd_topo_run_tile`, but keeping the callback signatures
compatible means switching would be trivial if needed.

See [tile-orchestration.md](tile-orchestration.md) for the full reuse boundary
and what Tickoni reuses versus rebuilds.

## Runtime Model

Tickoni follows Firedancer's topology discipline: tiles, links, workspaces,
mapping modes, and queue depths are explicit. A design is not ready until each
link can answer:

1. Which tile owns the state?
2. Which workspace holds it?
3. Which process maps it, and in what mode?
4. Which fields are written concurrently, and by whom?
5. What happens on overrun, restart, and shutdown?
6. Which metrics or logs expose unhealthy behavior?

For the Phase 0 pipeline, the default ownership model is one producer per link
and one owning tile for every mutable state object. Consumers read from bounded
links and publish their own progress counters.

Process-mode validation should include negative runtime-boundary tests:
malformed or stale workspace identifiers, wrong workspace join modes, missing
queue/control objects, dcache bounds errors, link depth/MTU/burst mismatches,
non-advancing reliable consumers, accidental heap-backed correctness queues in
process mode, and forced tile crashes that leave shared-memory state readable
for diagnostics or deterministic shutdown. Arbitrary kernel-memory attack
resistance, full Firedancer workspace fuzzing, cross-platform queue
substitutes, and production throughput saturation are separate security,
platform, fuzzing, or performance stories.

### Phase 0 Tiles

| Runtime ID | Logical name | Responsibility |
| --- | --- | --- |
| `tkings` | `ingest_tile` | Receive synthetic payment events, validate framing, assign source offsets, and apply ingress backpressure |
| `tknorm` | `normalize_tile` | Convert source events into the canonical financial event schema |
| `tkdedu` | `dedupe_tile` | Deduplicate events by idempotency key and content hash |
| `tkpoly` | `policy_tile` | Evaluate versioned capability policy for runtime-visible decisions |
| `tkaudt` | `audit_tile` | Own append-only hash-chain ordering and JSONL export |
| `tkrepl` | `replay_tile` | Re-inject replay capsules with external effects disabled and report divergence |
| `tkmetr` | `metric_tile` | Export queue, tile, and runtime metrics |
| `tkdiag` | `diag_tile` | Export process, queue, crash, and supervisor diagnostics |

### Link Shape

Phase 0 links are implemented with this shape:

| Link | Producer | Consumer | Reliability | Payload |
| --- | --- | --- | --- | --- |
| `tkings_tknorm` | `tkings` | `tknorm` | reliable until ingress backpressure trips | canonicalizable payment event |
| `tknorm_tkdedu` | `tknorm` | `tkdedu` | reliable | normalized financial event |
| `tkdedu_tkpoly` | `tkdedu` | `tkpoly` | reliable | deduplicated event decision input |
| `tkpoly_tkaudt` | `tkpoly` | `tkaudt` | reliable | policy decision and event envelope |
| `tkrepl_tkings` | `tkrepl` | `tkings` or replay entrypoint | reliable in replay mode | replay capsule event |
| `*_tkmetr` | tile-local producers | `tkmetr` | unreliable where safe | metrics samples |
| `*_tkdiag` | tile-local producers | `tkdiag` | unreliable where safe | diagnostics samples |

Correctness-bearing event and audit links should prefer bounded reliable flow
control. Telemetry links may be unreliable if loss is counted and visible.

## Financial Event Schema

The first schema should be intentionally small. It only needs enough structure
to prove hashing, normalization, deduplication, policy decisions, and audit.

Required fields:

```text
source_system
source_offset
source_event_id
event_type
occurred_at_ns
received_at_ns
subject_id
amount
currency
idempotency_key
payload_hash
schema_version
```

The normalized event hash should be stable across process restarts and replay.
Fields that depend on local runtime receipt, such as `received_at_ns`, must be
handled explicitly so replay can distinguish source facts from runtime facts.

## Policy Boundary

Policy is a runtime control layer, not prompt guidance. Every meaningful action
is checked against:

- actor or service identity
- event or case scope
- environment
- data classification
- requested capability
- policy version
- action risk level
- required approvals

Phase 0 only needs enough policy machinery to prove allow, deny, and
require-approval records. Full agent and tool policy arrives in Phase 2.

Example:

```yaml
requested_action: create_case_candidate
event_type: payment.failed
environment: development
decision: allow
reason: phase0_non_mutating_runtime_event
policy_version: policy_2026_06_01
```

## Audit Journal

Tickoni's audit layer is a first-class system, not log text. `tkaudt` owns
append-only ordering for material runtime events.

Phase 0 audit records should include:

```text
audit_event_id
previous_hash
record_hash
timestamp_ns
source_system
source_offset
source_event_id
normalized_event_hash
policy_version
decision
reason
tile_id
schema_version
```

Later phases add case IDs, agent IDs, model IDs, prompt hashes, tool calls,
approval IDs, downstream action IDs, signatures, and evidence references.

Large payloads should be content-addressed instead of duplicated into every
audit record.

### Why Binary And JSONL Both Exist

Tickoni needs two audit encodings because one format is optimized for runtime
correctness and replay discipline, while the other is optimized for operator
inspection and durable export.

Binary audit encoding is the canonical machine format inside the runtime and
replay path. It gives `tkaudt` and `tkrepl` a fixed field order, explicit
record length, early schema-version check, and skip-forward behavior for
unknown future records. That keeps hashing, append ordering, and replay
comparison independent of parser quirks, map key ordering, whitespace, or
string formatting. Binary is for deterministic transport and storage of the
typed audit record itself.

JSONL is the durable text export and operator-facing interchange format. It is
for append-only files, inspection, debugging, offline analysis, and simple
tooling such as `jq`, `rg`, and spreadsheet or notebook import. The JSONL line
keeps the same schema-versioned fields as the binary record, but in a form a
human or generic log-processing tool can read without Tickoni-specific binary
decoders.

These formats do not serve different truths. They are two encodings of the same
typed audit record. The binary form is the runtime canonical form. The JSONL
form is the readable export form. Hashing rules, especially the exclusion of
`timestamp_ns` from `record_hash`, must remain consistent across both so replay
and export inspection describe the same event chain.

## Replay

Replay is a deterministic comparison path. It is not allowed to invoke
privileged external mutations.

Phase 0 replay must answer:

- Did normalized event hashes match?
- Did deduplication decisions match?
- Did policy decisions match?
- Did audit chain hashes match?
- What was the first divergent event?

Replay command concept:

```bash
tickoni replay capsule phase0-payment-001
```

Expected result shape:

```text
Replay: phase0-payment-001
Event hashes: matched
Dedup decisions: matched
Policy decisions: matched
Audit chain: matched

Result: REPLAY MATCH
```

## Agent Harness

Agents are Phase 2. They operate as controlled workers, not unrestricted actors.

Agents may:

- read permitted evidence
- classify events
- summarize cases
- call approved tools
- draft responses
- propose actions
- request human review

Agents may not directly:

- move money
- post accounting ledger adjustments
- release payouts
- freeze accounts
- change compliance status
- override policy
- access secrets
- delete audit records

Agent workers should be networkless. Model-provider network access belongs
behind `tkmodl`. Tool access belongs behind `tktool` and signed `tkadpt`
instances.

## Tool Broker And Adapters

The tool broker is Phase 2. It normalizes model-native function calls and
MCP-compatible tool requests into the same capability envelope. MCP is an
integration protocol, not a trust boundary.

The broker enforces:

- capability scopes
- environment boundaries
- input validation
- output validation
- rate limits
- data access controls
- audit logging
- policy checks

Signed adapters expand integration reach without expanding agent authority.

## CaseOps Board

The CaseOps Board is Phase 3. It is Tickoni's operational control plane, not a
generic Kanban board.

Each card represents a financial case backed by event data, evidence, agent
actions, policy decisions, approvals, and audit records.

Default V1 columns:

```text
New Event
-> Enriched
-> Agent Reviewed
-> Policy Decision
-> Human Review
-> Action Proposed
-> Resolved
-> Audited
```

## Privileged Actions

Privileged execution is last. Agents never receive direct authority to mutate
money-adjacent systems.

`tkexec` may be added only after policy, audit, replay, approval, and adapter
boundaries are already proven. For accounting ledger integrations such as
the approved execution ledger, only `tkexec` receives ledger network credentials. Replay uses
deterministic mock connector results and never invokes production mutation.

## Sandboxing

Tickoni avoids using Docker as the primary security model for the runtime.
Docker may be useful for development and packaging, but the runtime security
model should be lower-level and explicit.

Runtime isolation:

- small tile processes
- seccomp profiles
- dropped capabilities
- restricted filesystem access
- explicit network permissions
- shared-memory channels
- bounded resources
- crash-only process design

Agent and adapter isolation:

- no production secrets by default
- no direct database mutation from agents
- no direct financial action from agents
- read-only access unless explicitly granted
- writable temporary workspace only
- capability-scoped envelopes
- full tool-call logging
- network access controlled per tile or adapter

## Related Docs

- [Development](../execution/development.md)
- [Build System](../build-system.md)
- [Testing](../execution/testing-tickoni.md)
- [Observability](../execution/observability.md)
- [Telemetry](../execution/telemetry.md)
- [Security](../execution/security.md)
- [Contribution Guide](../execution/contribution/tickoni.md)
