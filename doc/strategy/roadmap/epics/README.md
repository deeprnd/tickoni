# Roadmap - Tickoni Consumer Finance V1

Use this folder for per-increment planning, tracking, and reference. GitHub is
the issue tracker: epics, stories, and tasks are all GitHub issues with
different labels and sub-issue relationships.

## Issue Hierarchy

| Type | GitHub label | Purpose | Relationship |
| --- | --- | --- | --- |
| Epic | `type/epic` | Huge new feature or product increment. Groups related stories that deliver a complete capability across domains. | Has story sub-issues |
| Story | `story` | Single implementable deliverable that can be independently verified. | Sub-issue of one epic, has task sub-issues |
| Task | `task` | Domain-scoped implementation work for one story. | Sub-issue of one story |

Use these templates:

- [`epic-template.md`](../../templates/epic-template.md)
- [`story-template.md`](../../templates/story-template.md)
- [`status-template.md`](../../templates/status-template.md)

Use these project docs to fill and implement issues:

- [`README.md`](../../README.md) for product identity, supported
  workflows, and non-goals.
- [`architecture.md`](../../../knowledge/architecture.md) for runtime layers, tile
  ownership, audit, replay, and attached systems.
- [`execution/contribution/tickoni.md`](../../../execution/contribution/tickoni.md) for Tickoni Zig
  runtime style and Firedancer substrate reuse.
- [`build-system.md`](../../../build-system.md) and [`development.md`](../../../execution/development.md)
  for repo-facing build/run commands and justfile command policy.
- [`testing-tickoni.md`](../../../execution/testing-tickoni.md) and
  [`ci.md`](../../../execution/ci.md) for local verification and CI expectations.
- [`security.md`](../../../execution/security.md) for fail-closed and no-bypass
  requirements.
- [`observability.md`](../../../execution/observability.md) and
- [`telemetry.md`](../../../execution/telemetry.md) for metrics, diagnostics, and
  operator-visible evidence.

## Increments

| Increment | Description |
| --- | --- |
- `[V5.26](v5.26.md): Portfolio Management And Valuation Queue` — Portfolio CRUD, exposure charts, rebalance suggestions, watchlist with automatic valuation queue
|- `[V5.2](v5.2.md): Model Selection And Governance` — Per-portfolio model tier selection stored as `tkmodl` capability scope with budget enforcement |
|| [V1.0](v1.0.md) | Runtime Proof |
|| [V1.1](v1.1.md) | Investment Intent To Paper Trade |
|| [V1.11](v1.11.md) | Investment Demo Release Closure |
|| [V2.14](v2.14.md) | Firedancer Process And Shared-Memory Topology |
|| [V1.3](v1.3.md) | Portfolio And Cash Impact Loop |
|| [V11.28](v11.28.md) | Pay And Move Money Guard |
|| [V11.20](v11.20.md) | Guarded Crypto Transfers |
|| [V3.19](v3.19.md) | Tickoni Terminal CaseOps UI |
|| [V2.21](v2.21.md) | macOS Retail Runtime Support |
|| [V2.22](v2.22.md) | Windows Retail Runtime Support |
|| [V4.32](v4.32.md) | Core DCF Valuation Engine — tkval tile, WACC, FCFF, Gordon Growth, exit-multiple cross-check |
|| [V4.34](v4.34.md) | Valuation Data Layer — ERP (FreeXL), EDGAR (Edgartools), XBRL (Arelle), market data, financial validation |
|| [V4.24](v4.24.md) | Monte Carlo and Scenario Analysis — native Monte Carlo, cross-check suite, sensitivity tables, methodology audit |
|| [V4.25](v4.25.md) | Investment Conclusion and Governance — per-share value, verdict engine, valuation.propose, audit, replay |
|| [V6.31](v6.31.md) | Crypto And Stablecoin Guard |
|| [V6.9](v6.9.md) | Crypto Thesis To Guarded Spot Trade |
|| [V7.12](v7.12.md) | Runtime Hooks |
|| [V7.15](v7.15.md) | Bounded Agent Run Governance |
|| [V7.17](v7.17.md) | Tkmodl Budget And Call-Limit Governance |
|| [V7.18](v7.18.md) | Replay Proof Bundle And Evidence Integrity |
|| [V7.7](v7.7.md) | Trust Layer |
|| [V7.8](v7.8.md) | Capability Control Surface |
|| [V8.13](v8.13.md) | Non-Investment Operations Workflows |
|| [V8.33](v8.33.md) | Financial Telemetry, Audit, And Observability Governance |
|| [V8.6](v8.6.md) | Guarded Broker, Payment, And Crypto Sandbox |

## How Roadmap Files Are Organized

Roadmap files capture product sequencing and acceptance context. They may link
to the GitHub epic/story/task issues that own active execution.

**Roadmap section** - product intent, user story, what the user can do, what the
user sees, capability depth, success demo, non-goals.

**Breakdown section** - story issues (S1, S2, ...), each with task sub-issues
and acceptance criteria. Split by domain only where it helps deliver a
self-contained, testable story.

## Status Legend

For full epic, story, and task issue statuses, use
[`status-template.md`](../../templates/status-template.md).

All issue types use the same status enum:

`Backlog | Refining | Ready | In Progress | Review | Verification | User Accepted | Done | Blocked`

## Cross-References

- Product bet, target user, and priority stack: [`positioning.md`](../../positioning.md).
- V1 completion criteria and non-goals: [`positioning.md`](../../positioning.md).
- V1 capability set, denied-by-default list, and capability depth by increment: [`capabilities.md`](../../capabilities.md).
- Product language conventions: [`execution/contribution/tickoni.md`](../../../execution/contribution/tickoni.md).

## Increment Gate Checklist

Every increment must answer before closing:

- What can the consumer-money user do now?
- What changed from the previous increment?
- What is the demo moment?
- Which account, beneficiary, IBAN, wallet, rail, currency, market, venue,
  asset class, instrument, notional, amount, exposure, and frequency checks are
  enforced?
- What happens when the user asks for too much money?
- What happens when an instrument, recipient, wallet, rail, or network is
  restricted?
- Is execution paper-only, draft-only, sandbox, live, or disabled?
- Which artifacts are needed for later partner trust?
- Which demo command or script closes the increment?
- Which fixture data is used for thesis, portfolio, market, payment, transfer,
  crypto, model, tool, and adapter boundaries?
- Are policy decisions, destination checks, venue checks, wallet checks, and
  limit checks visible in audit output where they apply?
- Can replay run without model, broker, payment, trading, crypto, or execution
  side effects?
- What intentional divergence or blocked-flow example proves failure behavior?

## Evidence Work Items

Every story should include child task issues for evidence and quality gates.
Use conditional evidence: require topology, policy, tool-broker, adapter, audit,
or replay proof only when the story touches that boundary. Mark an item
`N/A - reason` when reviewers may otherwise expect it.
