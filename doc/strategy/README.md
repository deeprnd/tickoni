# Tickoni Strategy

## Purpose

This directory owns Tickoni product strategy: what the product is, who it is
for, how the roadmap is organized, and where product decisions should be made.
Architecture, tile topology, implementation status, and verification details
remain in the knowledge and execution docs.

The current product direction is consumer finance:

```text
invest -> pay -> move -> hold -> prove
```

Tickoni should feel like a consumer-money product with a finance-native AI
control layer underneath. The user experience leads with investment, payment,
transfer, crypto/stablecoin, cash, and portfolio decisions. The platform
advantage remains deterministic processing, capability-scoped permissions,
audit, replay, bounded inference, signed adapters, and approval-gated
execution.

## What Tickoni Is

Tickoni is an AI harness for agentic finance.

It is a controlled execution and audit layer for financial workflows where AI
agents investigate events, use governed tools, and propose actions across
payment systems, accounting ledgers, trading workflows, crypto/stablecoin
flows, risk systems, compliance workflows, and operator case queues.

Tickoni combines:

- high-throughput financial event processing
- finance-native capability policy
- controlled AI case operations
- deterministic replay
- append-only audit and evidence capture
- human approval gates
- bounded model, tool, and adapter access
- MCP-compatible and model-native function-call adapter surfaces
- agent identity tied to role, workflow, case, policy version, and scope

The core rule is:

> AI agents may investigate, summarize, classify, recommend, draft, and
> propose. They must not directly move money, post accounting ledger
> adjustments, place trades, override controls, or bypass policy.

## What Tickoni Is Not

Tickoni is not:

- a generic AI agent framework
- a Claude Code clone
- a personal automation assistant
- a browser automation tool
- a project management app
- a trading strategy generator
- a quant research notebook
- a retail trading bot
- a plugin marketplace
- an autonomous money-moving agent

Tickoni is built for regulated agentic finance workflows where every material
event, decision, proposal, approval, and action must be attributable,
policy-checked, auditable, and replayable.

## Positioning

One-line positioning:

> Tickoni is the Zig-native AI harness for high-throughput fintech operations
> where every event, decision, and action is policy-gated, replayable, and
> audit-ready.

Financial institutions do not need another chatbot. They need an AI harness
that can process high-volume financial events, let agents operate on cases
safely, and prove exactly what happened afterward.

Tickoni exists because most agent frameworks are built around prompts, broad
tool access, and workflow automation. Financial infrastructure needs stricter
answers:

- Which event triggered the case?
- How was the event normalized and deduplicated?
- What data did the agent see?
- Which tools or adapters did it use?
- Which capability policy allowed, denied, escalated, or required approval?
- Which human approved the proposal?
- What downstream system changed?
- Can the sequence be replayed with external effects disabled?
- Did the agent attempt forbidden behavior?

See [Competitive Positioning](positioning.md) for comparisons with adjacent
agent harnesses, developer tools, and operational platforms.

## Runtime Thesis

Tickoni is built as financial AI-harness tiles on Firedancer infrastructure,
not as a normal web backend with agents attached.

The product sequence is:

```text
runtime first
cases second
agents third
privileged actions last
```

AI is not in the deterministic financial event critical path. Financial events
must be ingestible, normalized, deduplicated, policy-checked, audited, and
replayable before any agent investigates the resulting case.

Firedancer is relevant as systems substrate: bounded queues, explicit topology,
workspaces, sandboxed tile processes, low-overhead metrics and diagnostics,
tile-local networking, crash-only behavior, and `fd_http_server`. Solana
validator schemas, RPC semantics, and validator tile identities are not
Tickoni product semantics.

Tickoni applies that infrastructure pattern to fintech event operations:

```text
financial event streams
  -> Tickoni event runtime
  -> capability policy and audit boundary
  -> controlled agent harness
  -> CaseOps board
  -> approved privileged execution path
```

The runtime must preserve strict control over high-volume events such as:

- payment authorization, settlement, payout, and retry events
- reconciliation breaks and accounting ledger mismatches
- fraud, compliance, dispute, customer-risk, and merchant-risk alerts
- investment, portfolio, trading, crypto, and stablecoin proposal workflows

## Core Principles

1. AI is off the critical path. Agents do not sit in the hot path for
   settlement, ledger posting, account freezing, payout release, trading
   execution, or other money-impacting actions.
2. Policy beats prompting. Security and compliance are enforced by code and
   finance-native capability envelopes, not natural-language instructions.
3. Every material action is audited. Events, model calls, tool calls, adapter
   calls, policy decisions, approvals, proposals, rejected actions, evidence,
   failures, and replay results must be captured as audit-relevant facts.
4. Every material case is replayable. Replay capsules use captured inputs and
   substituted model/adapter outputs instead of calling external systems.
5. Runtime comes before agents. Tickoni is not a thin wrapper around LLM APIs;
   agents attach to a deterministic, high-throughput tile runtime.
6. Narrow beats generic. Tickoni focuses on high-value financial operations
   instead of general-purpose automation.

## Source Of Truth

| Document | Owns | Does not own |
| --- | --- | --- |
| [`README.md`](README.md) | Product identity, strategy directory guide, current product direction, non-goals, operating model | Tile topology, implementation facts, or detailed roadmap work |
| [`positioning.md`](positioning.md) | Market position, differentiation, buyer framing, non-positioning | Delivery sequencing or implementation tasks |
| [`roadmap/`](roadmap/) | Consumer-finance increment sequence, story files, evidence gates, increment status, backlog work | Market narrative or tile topology |
| [`templates/`](templates/) | GitHub issue templates for epics, stories, tasks, proposals, and status | Runtime or policy source of truth |
| [`capabilities.md`](capabilities.md) | Finance-native permission model, action classes, policy outcomes, scopes, destination allowlists, and capability roadmap | OS sandbox permissions or implementation-specific tile APIs |
| [`lore/`](lore/) | Origin story and mythological framing for Tickoni — brand narrative, milestone connections, competitive metaphors | Implementation facts, tile topology, or roadmap sequencing |
| [`doc/knowledge/architecture.md`](../knowledge/architecture.md) | System layers, runtime model, event path, attached systems, audit/replay architecture | Product backlog sequencing |
| [`doc/knowledge/tile-topology.md`](../knowledge/tile-topology.md) | Tile IDs, tile ownership, topology, reuse boundary, validator-tile replacement decisions | Product backlog, roadmap sequencing, WBS tasks |
| [`doc/knowledge/platform-tiers.md`](../knowledge/platform-tiers.md) | Supported platforms (Windows, macOS, Linux on x86_64 and ARM64, all on par), Linux-only features postponed to a server-only version, visibility rules | Per-OS shim implementation details or CaseOps integration |
| [`doc/execution/retail-runtime-support.md`](../execution/retail-runtime-support.md) | Canonical retail runtime trust surface: supported binaries, install/update/uninstall paths, storage locations, manual verification, privacy defaults, unsupported features | Platform support definitions themselves, low-level topology ownership, or release-signing claims that do not exist |
| [`doc/execution/tile-delivery-status.md`](../execution/tile-delivery-status.md) | Current topology implementation facts, link table, readiness prerequisites, synchronization debt, completion gate | Architecture or tile ownership |

## Product Operating Model

### Planning Cadence

- Roadmap review: update when product priority, version order, or strategic
  scope changes.
- Story grooming: update when stories split, merge, or change acceptance
  criteria.
- Capability review: update when a financial action class, policy outcome,
  destination allowlist, scope dimension, approval path, or default-deny rule
  changes.
- Tile-plan review: update when a product requirement changes tile ownership,
  link shape, runtime boundary, or Firedancer infrastructure use.

### Decision Rules

1. If the question is "what is Tickoni and why does it exist?", update this
   README.
2. If the question is "how is Tickoni positioned in the market?", update
   `positioning.md`.
3. If the question is "when does this happen?", update the relevant roadmap
   story under `roadmap/`.
4. If the question is "what exact work remains?", update the relevant roadmap
   story under `roadmap/`.
5. If the question is "which tile owns this?", update
   `doc/knowledge/tile-topology.md`. If the question is "what is implemented or
   still outstanding?", update `doc/execution/tile-delivery-status.md`.
6. If the question is "which financial action is allowed?", update
   `capabilities.md`.
7. If the question is "which model, tool, or adapter path is allowed?", update
   `capabilities.md` unless a dedicated governance document is restored.

## Senior Product Constraints

- Lead with consumer-money outcomes, not governance-console language.
- Keep the first increments focused on safe decisions: investment intent to
  paper trade, payment/transfer guardrails, cash/portfolio impact, crypto
  guard, sandbox execution, trust, and capability control.
- Make constraints useful to the operator or user: buying power, trusted
  recipients, wallet allowlists, amount limits, venue scope, concentration,
  frequency, holding period, approval state, and blocked reasons.
- Prove audit, permissions, telemetry, replay, and no-bypass behavior before
  real financial APIs.
- Prefer deterministic stubs until the product flow and control surface are
  measurable.
- Treat model integration as governed infrastructure, not a feature shortcut.
- Keep autonomous money movement, autonomous ledger posting, autonomous account
  freezing, autonomous payout approval, autonomous compliance decisions, and
  autonomous trading outside V1.

## Current V1 Narrative

V1 proves that Tickoni can turn consumer-money intent into safe, explainable,
replayable financial proposals:

1. Investment intent becomes an explainable basket, trade ticket,
   affordability check, and paper trade.
2. Payment, payout, retry, or transfer intent becomes an allowed, blocked,
   evidence-required, escalated, or approval-required proposal.
3. Portfolio, cash, pending obligation, approval, and drift impact are visible
   before and after action.
4. Crypto and stablecoin proposals are checked against wallet, network, asset,
   custody, chain-risk, travel-rule, and amount scope.
5. Sandbox broker, payment, bank, and crypto actions run only through signed
   adapters, signed envelopes, deterministic action ids, approvals, read-back,
   and kill switch.
6. Trust and capability-control surfaces expose audit timeline, replay capsule,
   policy version/hash, model/tool/adapter attribution, full action classes,
   policy outcomes, scope dimensions, evidence prerequisites, aggregate limits,
   and denied-by-default execution paths.

## Users

Tickoni is built for teams operating high-volume financial systems:

- payment processors
- payment service providers
- neobanks
- banking-as-a-service platforms
- card issuers
- acquirers
- remittance companies
- lending platforms
- marketplaces with payment operations
- fintech infrastructure companies
- agentic finance teams
- fraud operations teams
- reconciliation teams
- compliance operations teams

## Strategic Differentiation

Most AI harnesses optimize for autonomy. Tickoni optimizes for accountable
autonomy.

The differentiation is the combination of:

```text
high-throughput event runtime
+ finance-native capability policy
+ governed model/tool/adapter access
+ append-only audit journal
+ deterministic replay
+ fintech case workflows
```

Generic agent frameworks show what the agent did. Tickoni proves whether the
agent was allowed to do it, what evidence it used, what changed, and whether
the decision can be replayed.

## Status

The current repository contains the Agave-free Tickoni runtime foundation under
`src/app/tickoni/` and `src/tickoni/`. The active implementation is the
Zig-native `tickoni-supervisor` and Phase 0 financial event spike.

The intended V1 is a narrow, opinionated implementation focused on:

- high-throughput financial event processing
- controlled AI case operations
- strict policy enforcement
- forensic auditability
- deterministic replay
