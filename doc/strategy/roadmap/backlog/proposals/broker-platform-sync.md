<!--
Tickoni backlog proposal template.

Use this template when an idea is not ready to become an epic or story yet.
A backlog proposal answers: why does this belong in Tickoni?

It should be product-fit first, implementation-light. Do not turn this into an
acceptance-criteria document. If the proposal is accepted, graduate it into an
epic or story using the relevant template.
-->

# Backlog Proposal: Broker Platform Sync — Read-Only Portfolio Ingestion

**Candidate issue type if accepted:** epic
**Candidate labels:** `investing`, `platform`, `security`, `audit`, `operations`
**Related docs / examples:**
- `doc/strategy/roadmap/milestones/m9.md` — M10 scope includes broker/crypto sync
- `doc/knowledge/architecture.md` — tkadpt boundary, tool broker, adapter pattern
- `doc/strategy/capabilities.md` — finance-native capability envelopes
- `doc/knowledge/tile-topology.md` — tkadpt, tktool tile definitions
- `doc/execution/testing/v1-1-investment-demo-integration.md` — broker adapter demo pattern
- `doc/strategy/roadmap/epics/v7.6.md` — sandbox adapter manifests (broker scaffolding)

## Proposal Summary

Add read-only synchronization with external broker platforms (one or more of eToro,
Interactive Brokers, SnapTrade, Robinhood) so Tickoni can ingest a user's existing
holdings and portfolio composition as canonical financial events. The sync populates
Tickoni's portfolio state in analytics store and is exposed through CaseOps for operator review.
All adapter calls are paper/sandbox — no live trading authority. A new broker-read
capability scope and associated policy gate must be introduced.

## Product Fit Thesis

This fits Tickoni because it closes the gap between Tickoni's portfolio model and a
user's real-world asset positions. Without broker sync, Tickoni has no way to know
what the user actually holds; the portfolio model is a blank slate that agents and
operators must fill from scratch. Read-only broker sync gives Tickoni a factual
starting point for all downstream capability checks, rebalance proposals, risk
analysis, and agent investigations.

It is not just a "portfolio dashboard" or "generic investment app" because the sync
produces deterministic, audit-grade financial events that flow through `tkings`,
`tknorm`, `tkdedu`, and `tkaudt` — the same pipeline used for all other financial
events. The broker platform is treated as an external source system, not a trusted
authority. Every holding snapshot becomes a source-attributed, hash-chained event
with capability envelope scope (account, asset class, venue, market). Policy gates
determine what Tickoni can do with that data; agents receive recommendations, not
autonomous execution.

## Tickoni Fit Checklist

| Fit question                                                                                                                                            | Answer |
| ------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| What financial or money-adjacent consequence does this help control?                                                                                    | Gives Tickoni a factual baseline of user holdings so all downstream policy checks, rebalance proposals, and risk calculations are anchored to real positions rather than blank-state assumptions. |
| Which user/operator trust problem does it reduce?                                                                                                       | Eliminates the trust gap where operators or agents cannot verify that Tickoni's portfolio model matches reality. Operators see exactly what was pulled, from which broker, and when. |
| How does it support policy-gated proposals instead of uncontrolled execution?                                                                           | New capability scope `broker_read` with `allow` outcome only; agents can query portfolio state but cannot propose trades against it without separate trading capability. |
| What audit, evidence, or replay value does it create?                                                                                                   | Every sync event is source-attributed, hash-chained in `tkaudt`, and replay-encapsulable. Divergence between broker-reported and Tickoni-ingested values is audit-logged. |
| What finance-native scope matters: account, beneficiary, wallet, rail, currency, market, venue, instrument, amount, exposure, frequency, approval path? | broker_account_id, asset_class, market, venue, instrument, currency, notional, exposure, sync_interval |
| How does it keep agents off the direct money path?                                                                                                      | Agents receive portfolio summaries as evidence for recommendations; they call `tktool`/`tkadpt` for reads, not `tkexec`. No live broker write calls. |
| How does it avoid becoming generic agent automation or trading-alpha UX?                                                                                | The epic is purely about ingestion and visibility. Trading, rebalance, or alpha features are out of scope. |

## User / Operator Problem

A Tickoni user has existing brokerage accounts with holdings across stocks, ETFs,
and possibly crypto. They want Tickoni to see those holdings so they can get
rebalancing recommendations, risk analysis, and auditability — without manually
entering each position. Currently Tickoni has no path to ingest an external
portfolio snapshot.

## Current Gap

Tickoni has:
- A portfolio data model in the analytics store (conceptual, not yet fully implemented).
- Agent scaffolding that assumes portfolio state exists.
- The `tkadpt` adapter boundary and `tktool` tool broker for external reads.
- The sandbox adapter manifest infrastructure (V8.6) for broker stubs.

Tickoni does not have:
- Any broker platform integration (read or write).
- A `broker_read` capability scope in `tkpoly`.
- A normalized schema for broker holding snapshots.
- A sync orchestration layer that pulls holdings, normalizes, dedupes, and audits them.
- Operator visibility into broker-sync state in CaseOps.
- Evidence of which broker platform was used for any given portfolio snapshot.

## Proposed Product Behavior

When a Tickoni operator enables a broker platform integration in CaseOps, Tickoni
should:

- Allow the operator to connect to a supported broker platform via a governed
  credential flow (stored behind `tkadpt`, not in the analytics store or Markdown).
- Run a scheduled or on-demand sync that pulls the current portfolio snapshot
  from the broker platform through a sandbox or stub adapter.
- Normalize the raw broker data into Tickoni's canonical financial event schema.
- Deduplicate against prior syncs using source offset and idempotency keys.
- Route the normalized events through `tkpoly` with the new `broker_read`
  capability scope for audit-only decisions.
- Record all sync events in `tkaudt` as an append-only, hash-chained audit chain.
- Persist the normalized holdings into the analytics store for analytics and agent use.
- Display sync status, last-sync timestamp, held-instrument count, and any
  normalization or dedupe anomalies in CaseOps.

Expected behavior:

* The operator selects a broker platform (eToro, IBKR, SnapTrade, Robinhood)
  and provides read-only credentials via a governed input flow. Credentials are
  stored in a secure backend accessible only through `tkadpt`.
* A sync event is created with `event_type = broker_snapshot.sync`, carrying
  `source_system` = the broker platform ID, `source_offset` = broker-assigned
  snapshot ID or timestamp, and a stable `idempotency_key`.
* `tknorm` maps the broker's proprietary holding format (asset types, quantities,
  prices, denominations) into Tickoni's canonical schema with normalized fields
  for instrument identifier, asset class, market, venue, currency, and notional.
* `tkdedu` drops duplicate snapshots; if the same broker report arrives twice,
  only one event becomes a runtime fact.
* `tkpoly` evaluates `broker_read` capability: `allow` for read-only sync,
  `deny` if the event attempts any write or transfer scope.
* `tkaudt` appends records for the sync start, each holding record, and sync
  completion with hash-chained continuity.
* the analytics store's portfolio table is populated/updated with the latest snapshot.
* CaseOps shows the sync result: instruments found, new vs. updated positions,
  any normalization rejections, and the full audit trail.

## Why Now

M10 explicitly requires "end to end working read-only system" with "sync with
brokers/crypto platforms." This epic provides the broker-read half of that
requirement. Without it, M10's read-only system is limited to synthetic data
and YouTube/social sources, which cannot demonstrate portfolio-level financial
control — the core Tickoni value proposition.

Additionally, the sandbox adapter infrastructure from V8.6 (broker stub manifests)
provides the scaffolding this epic can consume. The tool broker pattern from V2.19
and V8.13 is already wired. The capability envelope model in `tkpoly` supports
extending with new scopes. No foundational building block needs to be invented
from scratch.

## Example Scenario

```text
Given:  An operator enables SnapTrade as a broker platform in Tickoni CaseOps
        with read-only credentials stored via tkadpt
When:   The operator triggers a portfolio sync or the scheduler runs a periodic sync
Then:   Tickoni pulls the current holdings from SnapTrade through a sandbox adapter,
        normalizes them into canonical events, deduplicates against prior snapshots,
        policy-checks them with broker_read capability (allow),
        records hash-chained audit entries in tkaudt,
        populates the analytics store portfolio tables,
        and CaseOps displays: sync completed, 47 instruments found, 12 new, 35 updated,
        0 rejected, last sync timestamp, source_system=etoro
```

## Product Boundaries

### In Scope

* Broker platform selection and credential management (read-only, via `tkadpt`)
* Portfolio snapshot ingestion from one or more supported broker platforms
* Normalization of broker-specific holding formats into Tickoni canonical schema
* Deduplication of sync events using source offsets and idempotency keys
* New `broker_read` capability scope in `tkpoly`
* Audit trail of all sync events in `tkaudt` (append-only, hash-chained)
* the analytics store portfolio table population from normalized sync data
* CaseOps display of sync status, instrument counts, and audit trail
* Policy gate enforcement: read-only only, no write/trade scope from sync events

### Out Of Scope

* Live trading order placement through broker platforms (`tkexec` / trading execution)
* Real-time price feeds or market data ingestion
* Portfolio rebalancing proposals or auto-trading
* Crypto exchange sync (separate epic/story, though the adapter pattern extends)
* Portfolio performance analytics, PnL tracking, or tax reporting
* Multi-account aggregation across multiple users
* Direct Solana on-chain data ingestion (not a broker platform)
* Agent-driven portfolio analysis or recommendations (requires separate agent epic)

### Authority Boundary

| Action class        | Proposed boundary                                                     |
| ------------------- | --------------------------------------------------------------------- |
| Observe             | Allowed — CaseOps shows sync status and portfolio state                |
| Analyze             | Allowed — agents can query portfolio state through `tktool`/`tkadpt`   |
| Draft               | N/A — no draft state for read-only sync                                |
| Recommend           | Allowed — agents can recommend trades based on portfolio state         |
| Propose             | Policy check required — requires separate trading capability envelope  |
| Prepare             | Denied — no sandbox-only prepare for broker sync (sync is pull-only)   |
| Execute             | Denied — out of scope; broker writes not permitted in this epic        |
| Override/Administer | Denied — out of scope                                                  |

## Fit Against Product Principles

| Principle                                        | How this proposal fits | Concern / open question |
| ------------------------------------------------ | ---------------------- | ----------------------- |
| Financial consequence over generic tool access   | Sync produces deterministic financial facts (holdings) that become the basis for all downstream policy checks and agent recommendations. | N/A |
| Proposal-first agent behavior                    | Agents see portfolio state as evidence; they cannot push changes through broker sync. Trades require separate proposal flow. | N/A |
| Policy gates and approval paths                  | New `broker_read` capability scope in `tkpoly` enforces read-only boundary. | What approval level is required to enable a broker connection? Should it be operator-only or require explicit user consent in consumer context? |
| Audit-grade evidence                             | Every sync event is hash-chained in `tkaudt` with source attribution, allowing full forensic reconstruction. | Should individual holding records be content-addressed to avoid duplicating payload size in audit chain? |
| Deterministic replay or replay-safe substitution | Sync can be replayed from captured broker adapter responses without calling the live broker. | How do we handle broker API response format changes between sync runs? Should normalization be versioned? |
| Bounded model/tool/adapter spend                 | Sync adapter calls are scheduled, bounded by max calls per interval, and counted for token/budget accounting. | Should there be a per-sync cost ceiling to prevent runaway adapter calls? |
| Fail-closed behavior                             | If broker credentials are missing, malformed, or the adapter times out, no portfolio data is written. The event is logged and denied. | N/A |
| No live side effects unless explicitly approved  | All adapter calls are read-only. No orders, transfers, or account modifications occur. | N/A |

## Evidence Needed To Promote

* [ ] A concrete broker adapter (stub or sandbox) can pull a holdings snapshot and return a parseable response.
* [ ] The normalized event schema covers all relevant broker holding fields (instrument, quantity, price, currency, market, asset class).
* [ ] The `broker_read` capability scope is defined in `tkpoly` and returns correct allow/deny outcomes.
* [ ] The proposal has an observable audit/replay/evidence value (full hash chain visible in `tkaudt` output).
* [ ] Non-goals are explicit (no live trading, no market data, no rebalancing).
* [ ] The idea can be split into independently testable epic/story work.
* [ ] At least one broker platform has been investigated for integration feasibility (API docs, credential model, rate limits).

## Risks And Anti-Fit Signals

This should not move forward if:

* it mainly improves portfolio dashboard aesthetics without a financial-control outcome
* it encourages autonomous money movement, order placement, or ledger posting via broker sync
* it makes trading performance, alpha, PnL, or gamification the dominant product object
* it cannot identify the relevant policy, approval, evidence, or replay boundary
* it requires live external side effects before Tickoni has a safe paper/sandbox path
* it duplicates an epic/story that already covers broker integration (e.g., V8.6 sandbox manifests)
* the broker platforms' API models are fundamentally incompatible with Tickoni's canonical schema, requiring excessive transformation logic
* credential management for external broker platforms introduces unacceptable security surface (token storage, refresh, revocation)

## Open Decisions

| Decision | Options | Owner / next step |
| -------- | ------- | ----------------- |
| Which broker platform(s) to target first? | eToro (simple REST API), IBKR (complex but comprehensive), SnapTrade (banking aggregation), Robinhood (consumer, simpler) | Investigation required: review each platform's API docs for read-only portfolio access, credential model, and rate limits. |
| Should sync be on-demand, scheduled, or both? | On-demand only (operator triggers), scheduled only (configurable interval), or both | Depends on operator expectations and M10 demo needs. On-demand is simplest to prove. |
| How are broker credentials managed? | Stored encrypted in Tickoni backend, accessed via `tkadpt` with scoped tokens; or delegated to a credential vault (e.g., HashiCorp Vault) | Security boundary decision. Must fail closed if credentials are missing or expired. |
| What is the broker_read approval level? | Operator-only enable, user-level consent gate, or policy-gated per-account | Tied to consumer hardware tier constraint (no sudo/elevated privilege). |
| Should crypto exchanges be in the same epic? | In-scope (broker+crypto sync) or out-of-scope (broker-only, crypto separate) | M10 mentions both, but scope discipline suggests separating unless crypto adds zero marginal cost. |
| How are normalization schema versions managed? | Embed `schema_version` in event, version the normalizer in `tknorm`, require version upgrade for format changes | Must support replay of historical syncs; version mismatch should not break audit chain. |

## Graduation Path

If accepted, this should become:

* [x] Epic: spans multiple stories (credential management, adapter integration, normalization, policy, audit, CaseOps visibility)
* [ ] Story: each independently implementable and verifiable
* [ ] Documentation: updates to tile-topology, capabilities, and security docs

Suggested next artifact:

* [ ] Create epic using `epic-template.md` with the expanded scope from this proposal
* [ ] Create investigation story for broker platform API comparison (eToro, IBKR, SnapTrade, Robinhood)
* [ ] Create story for sandbox adapter stub (returns deterministic holdings fixtures)
* [ ] Create story for `broker_read` capability scope and policy definition
* [ ] Create story for canonical event schema extension (broker holdings)
* [ ] Create story for CaseOps broker-sync status display
* [ ] Keep in backlog with notes if additional broker platforms are deferred
