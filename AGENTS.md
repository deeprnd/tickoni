# Tickoni

This file is the operating guide for AI coding agents working in this repository.

Use it to understand:

- what Tickoni is and how it relates to Firedancer,
- which parts of the repo are the current source of truth,
- how the workspace, tiles, harness, agents, and tools are structured,
- which engineering standards are mandatory here,
- how to test and validate changes before handoff.

## How To Understand This System (Read First)

Before making changes, read these in order:

1. `README.md` — project overview
2. `doc/strategy/README.md` - product overview
3. `doc/knowledge/architecture.md` — product architecture
4. `doc/knowledge/tile-topology.md` - tile topology
5. `doc/execution/development.md` — dev environment, build, and workflow
6. `doc/execution/contribution/tickoni.md` - contribution guide
7. `doc/execution/testing-tickoni.md` - testing
8. this file — constraints, invariants, and engineering rules

### Mental model

Tickoni is an AI harness framework for agentic finance. It is built as
financial AI-harness tiles on top of Firedancer infrastructure, not as a
normal web backend with agents attached.

- This repository is `deeprnd/tickoni`, not upstream Firedancer. Treat
  Tickoni code and docs in this repo as the source of truth, and use
  Firedancer only as reused infrastructure context unless a task explicitly
  asks about upstream Firedancer.

Core layers:
1. Firedancer infrastructure provides the ultra-TPS systems substrate:
   `src/tango` queues, topology/workspace discipline, sandboxed tile
   processes, low-overhead metrics/diagnostics, `fd_http_server`,
   bounded polling, tile-local networking, seccomp/Landlock, and crash-only
   behavior.
2. Tickoni AI-harness tiles own financial correctness: ingest, normalize,
   dedupe, case routing, policy, audit, replay, metrics, diagnostics, bounded
   agents, model gateway, tool broker, signed adapters, and future approved
   execution.
3. Attached systems are governed integrations around the runtime: Next.js
   CaseOps UI, Zig `tkapi` HTTP/WebSocket API, Markdown memory/policy files,
   the analytics store analytics/backtest stores, LLM server/model providers, local Agent
   Daemon, the approved execution ledger, and trading/crypto/payment/risk/compliance APIs.

Core loop:
1. Financial events enter `tkings`.
2. `tknorm` canonicalizes events and `tkdedu` removes duplicates.
3. `tkcase` creates deterministic case state when cases are enabled.
4. `tkpoly` checks finance-native capability envelopes.
5. `tkaudt` records append-only, hash-chained audit events.
6. `tkrepl` replays from captured inputs with external effects disabled.
7. Agents run only after the event/case path is auditable and replayable.

Key principle:
- AI is not in the deterministic financial event critical path.
- The TPS claim comes from Firedancer infrastructure reused for Tickoni's
  financial event runtime.
- Firedancer validator tiles and Solana schemas are not Tickoni framework
  tiles; reuse the infrastructure patterns and generic primitives, not Solana
  semantics.
- Markdown files hold human-authored memory, theses, policies, and company
  notes; they are not deterministic runtime truth by themselves.
- The analytics store holds market data, analytics, backtests, and local research
  projections; it is not the finance ledger.
- The approved execution ledger holds balances, transfers, fills, and accounting state behind
  approved `tkexec` mutations, never a direct agent/UI dependency.
- LLM servers and model providers are accessed through `tkmodl`; local agent
  CLIs are accessed through a governed daemon; financial APIs are accessed
  through `tkadpt` or future `tkexec`.

#### Example Flow (Lifecycle Mapping)

Scenario: a user asks the trading-control agent to buy USD 2,000 of a US
Information Technology ETF through `brokerage.demo_ops`.

1. `tkapi` receives the user request and records source identity, workflow
   `trading_control`, case or run id, requested instrument, side, notional
   amount, venue, and environment.
2. `tkings`, `tknorm`, and `tkdedu` ingest, canonicalize, and deduplicate the
   request as a financial event.
3. `tkcase` attaches the request to a deterministic case or synthetic run so
   all later policy, model, tool, approval, and replay records share the same
   scope.
4. `tkpoly` builds a finance-native capability envelope for
   `trading_order.propose`, including actor role `trading_ops_reviewer`,
   account `brokerage.demo_ops`, asset class `etf`, market `US`, venue
   `NYSE` or `NASDAQ`, sector `Information Technology`, side `buy`, notional
   USD 2,000, policy version, and budget id.
5. `tkpoly` checks the envelope against the trading capability policy:
   account, asset class, market, venue, sector, restricted instrument list,
   daily/monthly notional limits, minimum recommendation interval,
   holding-period rules, same-day round-trip rule, and approval requirement.
6. If the product, venue, sector, or amount is outside scope, `tkpoly` returns
   `deny`, `tkaudt` records the failed scope dimension, and no model,
   adapter, or execution call is made.
7. If the proposal is in scope, `tkpoly` returns `require_approval` or `allow`
   for non-executing investigation steps, and `tkdisp` may schedule a bounded
   `tkagnt` run.
8. Any model analysis goes through `tkmodl`, never directly from the agent to
   the LLM server or cloud provider. `tkmodl` enforces model allowlist,
   context limit, retry limit, token budget, attribution, audit, and replay
   substitution.
9. Any portfolio, market-event, or quote lookup goes through `tktool` and
   `tkadpt`, where the tool request is normalized to the same financial
   capability scope before a stub or signed trading adapter is called.
10. The agent may produce a recommendation or structured
    `trading_order.propose` record with evidence, but it may not call
    `trading_order.place`; direct placement is denied by policy.
11. `tkaudt` records the user request, capability decision, model request and
    response references, adapter request and response references, proposal
    hash, approval state, policy version, budget id, and case id.
12. In CaseOps, the operator sees the proposal with notional, market, venue,
    sector, instrument, frequency, holding-period, evidence, and policy
    decision. Approval is tied to the exact proposal hash and policy version.
13. In current V1-style flows, approval records the human decision but does
    not execute an order. In a future approved-execution phase, `tkexec`
    performs a final pre-trade check, uses a signed action envelope, calls the
    broker or exchange API, records before/after audit events, and performs
    read-back reconciliation.
14. `tkrepl` replays the case from captured inputs. It substitutes model and
    adapter outputs, never calls the LLM server, trading API, or `tkexec`, and
    reports changed capability scope, missing evidence, or divergent proposal
    state.

### Supporting Documentation (Implementation & Operations)

Development:
- `doc/execution/contribution/tickoni.md` — contribution styleguide
- `doc/knowledge/tile-topology.md` — tile IDs, topology, reuse boundary, validator-tile decisions
- `doc/execution/tile-delivery-status.md` — current topology implementation, link table, synchronization debt

Runtime & Operations:
- `justfile` — workspace scripts and validation gates

## Source Of Truth

This ordering answers "what does the system currently do" — use it when you
need ground truth about present behavior, not when you need to know what the
system is supposed to do. Code decides on runtime behavior. Documentation is
future-looking: it describes decided target behavior, which code may not have
caught up to yet, or which code may have quietly drifted away from. A mismatch
between code and documented intent is a discrepancy to flag explicitly, not a
tiebreaker to resolve silently in whichever direction is convenient. Unless the
user or an explicit decision record says the documentation itself is stale,
the default remediation is to bring the code into alignment with the logic
described in the docs — not to rewrite the docs to match whatever the code
currently happens to do.

When documentation and code disagree on current behavior, trust sources in
this order:

1. `justfile`, `build.zig`, `build.zig.zon`, and `GNUmakefile`
2. Tickoni executable and supervisor code in `src/app/tickoni/**`
3. Tickoni framework runtime, topology, C ABI wrappers, and tiles in
   `src/tickoni/**`
4. Firedancer infrastructure reused by Tickoni, especially `src/tango/**`,
   `src/disco/**`, `src/discof/**`, `src/waltz/http/**`, and selected
   `src/util/**`
5. product-management and architecture sources under `doc/strategy/**` and
   `doc/knowledge/architecture.md`
6. Tickoni contribution, development, testing, security, observability, and
   workflow docs under `doc/execution`
7. tests wired through `zig build test`, `make ... test`, and `just test-*`
   recipes
8. READMEs, diagrams, and generated book content

Notes:

- The active Tickoni runtime workspace is `src/app/tickoni/` and
  `src/tickoni/`.
- Tickoni backend/control-plane code is Zig. Do not introduce or assume any other
  language, or generic service backend unless the user explicitly asks for that migration.
- Tickoni is an AI harness framework for agentic finance, not a Solana client,
  or generic yield application.
- Use Firedancer infrastructure tiles and primitives for the ultra-TPS runtime
  claim, but do not repurpose Solana validator schemas, RPC semantics, or
  validator-only tile identities as Tickoni framework concepts.
- `tkapi` is the Zig HTTP/WebSocket CaseOps API tile. It should use or wrap
  Firedancer HTTP infrastructure where practical.
- Markdown files hold memory, theses, policies, company notes, runbooks, and
  human-authored operating context.
- Analytics store holds market data, analytics, backtests, research tables, and local
  analytical projections.
- Execution ledger holds balances, transfers, fills, accounting entries, and
  approved ledger-style financial state behind `tkexec`, not a direct
  dependency of agents, UI, or ordinary API reads.
- LLM servers and model providers are reached only through `tkmodl`; local
  agent CLIs are reached only through a governed Agent Daemon; trading,
  crypto, payment, risk, and compliance APIs are reached through `tkadpt` or
  future `tkexec`.
- Do not rename tile IDs, capability names, policy concepts, or Firedancer
  infrastructure paths unless the user explicitly asks for that migration.

## Project Summary

Tickoni is an AI harness framework for agentic finance. The current
implementation in this repository is a Zig-native runtime scaffold under
`src/app/tickoni/` and `src/tickoni/`, built on Firedancer infrastructure for
ultra-throughput event processing. Treat generic web-service backends, direct
agent autonomy, and production financial connectors, as future or external
context unless they are actually present in this repository.

Business flow:

- Financial events enter the runtime from synthetic streams first, then later
  from external ingestion APIs.
- `tkings` receives events, validates framing, assigns source offsets, and
  applies ingress backpressure.
- `tknorm` maps source-specific payloads into canonical financial event facts.
- `tkdedu` removes duplicates using idempotency keys and content hashes.
- `tkcase` will create deterministic case records when the case runtime is
  enabled.
- `tkpoly` evaluates finance-native capability envelopes for payment, ledger,
  trading, fraud/risk, banking destination, crypto destination, amount,
  frequency, and approval scope.
- `tkaudt` records append-only, hash-chained audit events for source events,
  policy decisions, model calls, tool calls, adapter calls, proposals,
  approvals, denials, and replay results.
- `tkdisp` and `tkagnt` will run bounded agents only after event/case state is
  auditable and replayable.
- `tkmodl` owns LLM server and model-provider access, budget enforcement,
  token accounting, request/response audit, and replay substitution.
- `tktool` and `tkadpt` normalize model-native function calls and MCP-style
  requests into finance-native adapter reads and proposals.
- CaseOps exposes operator review: cases, evidence, agent findings, policy
  decisions, approval workflow, audit timeline, and replay status.
- `tkexec` is future approved execution only. It owns privileged mutation paths
  such as the approved execution ledger accounting-ledger writes, payment execution, or trading
  execution after policy, approval, signed envelope, audit, and read-back.

Framework requirements:

- deterministic financial event processing,
- Firedancer-based ultra-throughput queues, topology, workspaces, sandboxing,
  metrics, diagnostics, HTTP/WebSocket service, and crash-only behavior,
- finance-native capability envelopes instead of OS-style permissions,
- explicit destination, venue, product, amount, exposure, frequency,
  holding-period, and approval constraints,
- model access only through `tkmodl`,
- financial tool and adapter access only through `tktool` and `tkadpt`,
- no direct database, model-provider, ledger, trading, payment, crypto, or
  unrestricted shell/network access for agents,
- append-only audit records and content-addressed evidence,
- deterministic replay with external effects disabled,
- human approval for money-impacting, ledger-impacting, trading-impacting,
  risk-impacting, and compliance-impacting mutations,
- clear separation between human-authored Markdown memory/policy context,
  analytical analytics store state, and the approved execution ledger financial ledger state.

Autonomous execution is not the priority in the current framework. Throughput,
determinism, isolation, finance-native permissions, auditability, replay, and
human-approved control of money-adjacent actions are.

## Framework Invariants

Do not change these assumptions without explicit approval:

- Financial events must be authenticated, framed, source-attributed, and
  assigned stable source offsets before becoming runtime facts.
- Event normalization must remain canonical and replay-stable; equivalent
  source payloads must produce the same normalized financial facts and hashes.
- Deduplication must use stable idempotency keys and content hashes, not
  process-local timing or database insertion order.
- `tkings`, `tknorm`, `tkdedu`, `tkcase`, `tkpoly`, and `tkaudt` have distinct
  ownership; do not merge ingestion, normalization, dedupe, case routing,
  policy, and audit responsibilities for convenience.
- Audit records must be append-only and hash-chained. Do not introduce mutable
  audit state or summary-only logs for material boundary events.
- Replay must run with external effects disabled. It must substitute captured
  model, adapter, proposal, approval, and execution results instead of calling
  LLM servers, trading APIs, payment APIs, the approved execution ledger, or `tkexec`.
- Every model, tool, adapter, proposal, approval, and execution request must
  carry a finance-native capability envelope with actor, role, workflow,
  case/run id, scope, policy version, and budget where applicable.
- Capability checks must return explicit outcomes such as `allow`, `deny`,
  `require_approval`, `require_more_evidence`, or `escalate`; do not encode
  authorization only in prompts or UI state.
- Sensitive capability scope must include the relevant financial dimensions:
  account, destination, rail, venue, market, sector, instrument, asset class,
  side, amount/notional, exposure, frequency, holding period, environment, and
  approval path.
- Agents are proposal-first. They may inspect, classify, summarize, draft,
  recommend, prepare evidence, and propose; they must not directly place
  trades, move money, post ledger entries, freeze accounts, approve payouts, or
  override risk/compliance controls.
- Model access must go through `tkmodl`. Agents must not call cloud providers,
  local LLM servers, or local GPU inference directly.
- Financial tool and adapter access must go through `tktool` and `tkadpt`.
  Model-native function calls and MCP-style requests are integration formats,
  not trust boundaries.
- Approved execution, when enabled, must go through `tkexec` with policy,
  human approval, signed action envelope, deterministic action id, audit
  before/after records, and downstream read-back.
- TigerBeetle is the authoritative finance database for balances, transfers,
  fills, and accounting state. Agents, UI, `tkapi`, `tkmodl`, and `tkadpt`
  must not connect to it directly.
- DuckDB is for market data, analytics, backtests, research tables, and local
  analytical projections. Do not treat DuckDB analytics state as authoritative
  balances, fills, transfers, or accounting truth.
- Markdown files are human-authored memory, theses, policies, company notes,
  runbooks, and operating context. Do not treat Markdown as deterministic
  runtime truth unless it is explicitly versioned and captured into audit or
  replay inputs.
- CaseOps state must remain reconstructable from authenticated financial
  events, accepted requests, deterministic case order, capability decisions,
  audit records, evidence references, and replay capsules.
- Tile links must keep explicit answers for owner tile, backing workspace,
  mapping mode, producer/consumer, depth/MTU, reliability, overrun behavior,
  restart behavior, shutdown behavior, and health metrics.
- Firedancer infrastructure may be reused for queues, topology, workspaces,
  sandboxing, metrics, diagnostics, HTTP/WebSocket service, and lifecycle, but
  Solana validator schemas, RPC semantics, and validator tile identities must
  not become Tickoni framework semantics.

When modifying code:
- preserve tile ownership and explicit link answers
- keep agents, model calls, adapter calls, and privileged actions outside the
  deterministic event critical path
- never introduce state that cannot be reconstructed from authenticated
  financial events, accepted requests, deterministic case order, audit records,
  and replay capsules
- never give agents direct database credentials, model credentials, ledger
  credentials, trading keys, unrestricted shell, or unrestricted network access
- make every material boundary event policy-checked, audited, and replayable

## Engineering Principles

These are mandatory unless the user explicitly directs otherwise.

- Do not make framework, architecture, policy, storage, or financial-semantics
  decisions silently. If a change affects tile ownership, link shape,
  capability scope, audit/replay behavior, storage role, external contracts, or
  execution authority, ask first.
- The coding agent is the implementor, not the framework owner or policy owner.
  Resolve ambiguity by asking for guidance instead of inventing financial
  policy, approval rules, trading limits, adapter authority, or storage
  semantics.
- Prefer explicit Zig structs, tagged unions, enums, comptime tables, and narrow
  interfaces over dynamic wiring or stringly-typed registries.
- Preserve separation of concerns: ingestion, normalization, dedupe, case
  routing, policy, audit, replay, model access, tool brokering, adapter access,
  execution, storage, and UI/API transport must remain clearly separated.
- Keep `tkapi` thin. HTTP/WebSocket handlers should validate transport shape,
  authenticate, route, and fan out state; financial correctness belongs in the
  owning tiles.
- Keep `tkpoly` as the authority for finance-native capability decisions. Do
  not duplicate policy checks in prompts, UI code, adapter code, or ad hoc
  helper functions.
- Keep `tkmodl`, `tktool`, `tkadpt`, and `tkexec` as hard boundaries. Do not
  let agents or UI code call LLM providers, financial APIs, the approved execution ledger, or
  execution backends directly.
- Prefer domain-driven naming from the position docs: use terms such as
  `trading_order.propose`, `payment_retry.propose`, `ledger_correction.propose`,
  `require_approval`, `replay_capsule`, and `capability_envelope` instead of
  generic tool or permission names.
- Reuse existing Tickoni tile IDs, capability names, policy outcomes, and audit
  fields instead of creating parallel vocabulary. When referencing Firedancer,
  use its infrastructure names only for actual reused primitives such as
  `tango`, workspaces, sandboxing, metrics, diagnostics, and `fd_http_server`;
  do not reuse Solana validator tile IDs or protocol vocabulary as Tickoni
  framework concepts.
- Do not scatter repeated hardcoded string literals through the codebase. If a
  value has bounded options, model it as an enum or shared constant set. If
  there is one reused fixed value, define a named `const`.
- Prefer unification and templating across similar financial domains where it
  clarifies behavior, especially for capability envelopes, destination
  allowlists, amount/frequency limits, audit records, replay substitution, and
  adapter manifests.
- Use Strategy, Factory, Adapter, and Template Method patterns when they make
  boundaries clearer, especially for model providers, financial adapters,
  storage backends, and policy evaluators. Do not add patterns for abstraction's
  sake.
- Keep storage roles explicit: Markdown is memory/policies/notes, DuckDB is
  analytics/backtests/market data, and TigerBeetle is balances/transfers/fills/
  accounting. Do not blur these roles for convenience.
- Do not introduce hidden state. State must be reconstructable from
  authenticated events, accepted requests, deterministic case order, audit
  records, evidence references, and replay capsules.
- Keep Firedancer integration narrow and deliberate. Reuse infrastructure such
  as queues, topology, workspaces, sandboxing, metrics, diagnostics, and
  `fd_http_server`; do not import Solana validator semantics into Tickoni
  framework code.
- Do not add developer tooling targets to upstream Firedancer Makefiles. Use the
  `justfile` and Tickoni-owned scripts for repository tooling.
- When a value, schema, manifest, capability catalog, or registry must be shared
  across runtime contexts, keep one source of truth in Zig or an explicit data
  file and generate or wire consumers from it. Do not create duplicate shim
  modules or parallel contract definitions.

### Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

### Goal-Driven Execution

**Documents, requirements, and tests first. Implementation follows, verified against them.**

Transform tasks into verifiable goals, in this order — docs/requirements,
then tests, then implementation:
- "Add validation" → "Write down what invalid input should trigger, write tests for it, then make them pass"
- "Fix the bug" → "Write down the correct behavior, write a test that reproduces the bug, then make it pass"
- "Refactor X" → "Confirm the documented behavior is still accurate, ensure tests pass before and after"

Docs are future-looking: they describe decided target behavior, not a
write-up produced after the fact to match whatever the code happened to do.
Once written, scan code against docs for correctness — don't reverse-engineer
intended behavior by tracing through implementation details and deducing the
logic behind it. If code and docs disagree, that is a discrepancy to flag,
not to silently resolve by rewriting the doc to match the code (see Source
Of Truth).

If development appears to require a custom throwaway verification script or
one-off test command, treat that as evidence that the system is missing a
proper test. Write the test instead and wire it to the correct unit,
integration, e2e, system, quality, or security scope described in
`doc/execution/testing-tickoni.md`.

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

### Ask Before You Change

Stop and get guidance before:

- changing tile ownership, tile IDs, tile lifecycle, or link semantics,
- changing source event authentication, framing, source offsets, normalization,
  dedupe, or canonical event hash behavior,
- changing case lifecycle semantics, deterministic case ordering, evidence
  attachment, or replay capsule shape,
- changing policy outcomes, capability envelope shape, destination allowlists,
  amount/exposure/frequency limits, approval requirements, or proposal state,
- changing audit record schema, audit hash chaining, append-only behavior, or
  replay substitution rules,
- changing public API contracts for `tkapi`, CaseOps, agent daemon sessions,
  model requests, tool requests, adapter requests, or approval actions,
- changing storage roles for Markdown, DuckDB, or TigerBeetle,
- changing TigerBeetle balance, transfer, fill, accounting, idempotency, or
  read-back assumptions,
- changing LLM-server/provider access rules, token budgets, retry limits,
  context limits, model allowlists, or replay behavior for model outputs,
- changing financial adapter authority for trading, crypto, payment, risk, or
  compliance APIs,
- introducing new infrastructure services, languages, queues, databases,
  schedulers, workers, or background daemons,
- introducing new abstractions that alter the existing tile-based architectural
  style,
- changing operator approval, maker-checker, settlement, reconciliation,
  fraud/risk, compliance, or privileged-execution guarantees.

## Hard Constraints

### Security Posture

- This is a financial application. Security and correctness take priority over performance, convenience, and implementation speed.
- Treat every external input as potentially malicious until proven otherwise.
- This includes HTTP inputs, L1 provider data, trading broker data,
  user event datums, environment variables, and generated test transactions.
- Validate all inbound data for presence, shape, bounds, encoding, and semantic correctness before it influences state transitions or persistence.
- Runtime environment configuration must also fail closed: production code must not silently default missing env vars to hardcoded values. Required env vars must be present, parsed to the expected type, and rejected explicitly when missing or malformed. Test-only helpers may set defaults locally when needed.
- Guard explicitly against overflow, underflow, truncation, missing fields, malformed metadata, inconsistent identifiers, and partial or ambiguous state.
- Cross-check parsed on-chain facts against canonical chain data and persisted database state, and reconcile mismatches explicitly instead of assuming either side is correct by default.
- If an input cannot be validated deterministically, fail closed, log useful identifiers, and avoid mutating business state.

## In Short

Build explicit, deterministic, test-backed changes.

Do not improvise business semantics.
Do not hide complexity behind dynamic tricks.
Do keep node, SDK, codec, DB modules, and tests consistent.
