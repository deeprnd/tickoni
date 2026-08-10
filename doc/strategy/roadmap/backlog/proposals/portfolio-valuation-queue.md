<!--
Tickoni backlog proposal template.

Use this template when an idea is not ready to become an epic or story yet.
A backlog proposal answers: why does this belong in Tickoni?

It should be product-fit first, implementation-light. Do not turn this into an
acceptance-criteria document. If the proposal is accepted, graduate it into an
epic or story using the relevant template.
-->

# Backlog Proposal: Portfolio Management And Valuation Queue

**Candidate issue type if accepted:** epic
**Candidate labels:** [`investing` | `platform` | `enhancement` | `documentation`]
**Related docs / examples:** [doc/strategy/roadmap/epics/v3.22.md] (DCF valuation engine), [doc/strategy/capabilities.md] (valuation capabilities, trading_portfolio.read), [doc/strategy/roadmap/milestones/m4.md] (source M5 description)

## Proposal Summary

Build the portfolio management surface and valuation queue that turns Tickoni's
governed runtime into a consumer-facing investing app: users manage portfolios
(add/edit/delete holdings), view exposure by industry and sector through pie
charts, receive rebalance suggestions against target exposure, maintain watchlists,
and get every portfolio and watchlist company automatically queued for DCF-style
valuation via V4.32. A model selector lets users choose which LLM model backs each
investigation from four tiers: local open-source, OpenAI, Anthropic Claude, or
Tickoni subscription (finance-tuned models fine-tuned on financial reasoning).

## Product Fit Thesis

This fits Tickoni because it delivers the consumer-money investing increment that
proves the framework can govern a complete, visible, auditable portfolio lifecycle
from intent through valuation evidence to policy-gated rebalance proposals. Every
portfolio action (add, edit, delete) creates a deterministic financial event that
passes through `tking`->`tknorm`->`tkdedu`->`tkcase`->`tkpoly`->`tkaudt`, so the
portfolio state is reconstructable from authenticated events, not from an opaque
database session.

It is not just a portfolio dashboard or generic investment UX because the observable
surface -- exposure charts, rebalance suggestions, valuation evidence cards -- is
backed by the same capability policy, audit chain, and replay discipline that governs
payment and trading proposals in Tickoni. An operator can replay any portfolio
change, inspect which model produced which valuation, and see the exact policy
decision that allowed or denied a rebalance proposal.

## Tickoni Fit Checklist

| Fit question | Answer |
| --- | --- |
| What financial or money-adjacent consequence does this help control? | Portfolio composition changes (add/hold/delete positions), rebalance proposals that shift sector or asset-class exposure, and valuation-driven recommendation envelopes. All carry `trading_portfolio.read` scope and `valuation.analysis.propose` capability checks. |
| Which user/operator trust problem does it reduce? | Eliminates the trust gap between "my app says I'm exposed 30% to IT" and "prove that the exposure was computed from auditable holding records through a policy-checked normalization path." |
| How does it support policy-gated proposals instead of uncontrolled execution? | Rebalance suggestions surface as `portfolio.rebalance.propose` capability requests with explicit scope dimensions (sector, asset class, concentration limits). Execution remains denied or approval-required; the app proposes, never places. |
| What audit, evidence, or replay value does it create? | Every portfolio mutation is a source event with a stable payload hash. Every valuation run is captured as a replay capsule substituting model/adapter outputs. Exposure charts are deterministic functions of auditable holding records. |
| What finance-native scope matters: account, beneficiary, wallet, rail, currency, market, venue, instrument, amount, exposure, frequency, approval path? | Account (portfolio id), instrument (ticker/ISIN/CUSIP), amount (shares/notional), exposure (sector/industry/asset-class breakdown), concentration limits (single-name, sector caps), currency (position currency vs portfolio base), approval path (rebalance proposals over concentration limits). |
| How does it keep agents off the direct money path? | Agents (via `tkdisp`->`tkagnt`->`tkmodl`) only produce investigation reports and `valuation.analysis.propose` records. The rebalance suggestion is a `portfolio.rebalance.propose` envelope; no adapter call or order placement occurs. |
| How does it avoid becoming generic agent automation or trading-alpha UX? | No performance ranking, no alpha generation, no gamification. The product object is a governable portfolio state machine with audit, replay, and policy gates. Valuation is deterministic math (V4.32), not generative alpha. |

## User / Operator Problem

The user is a consumer investor who wants to build and track a portfolio, see where
their money actually is (by industry, sector, asset class), understand when the
portfolio drifts from their target allocation, and get grounded, audited company
valuations before making changes. Currently, Tickoni has the governed runtime, the
DCF valuation engine (V4.32), and the capability model -- but no end-to-end
app surface that wires these together. The user has a runtime without a wallet.

## Current Gap

Tickoni can process financial events, normalize them, deduplicate them, policy-check
them, and audit them. V4.32 can run a full DCF valuation and produce a
proposal-grade record. But there is no:

- Portfolio state object (holdings, cash, base currency) that users can create and
  mutate through the governed event path.
- Exposure computation that aggregates holdings into sector/industry/asset-class
  pie charts from auditable holding records.
- Rebalance suggestion logic that compares current exposure to a user-defined target
  and surfaces `portfolio.rebalance.propose` envelopes.
- Watchlist that feeds into the V4.32 valuation queue.
- Automatic valuation queue: when a ticker enters a portfolio or watchlist, it should
  be queued for DCF valuation with all V4.32 capability checks.
- Model selection: users need to choose which LLM model powers each investigation.
  Four tiers: local open-source (e.g., Qwen, Llama), OpenAI, Anthropic Claude,
  or Tickoni subscription (finance-tuned models fine-tuned on financial reasoning).

## Proposed Product Behavior

When [user/operator] is in [the portfolio management app], Tickoni should [manage
portfolios, view exposure, receive rebalance suggestions, maintain watchlists, queue
valuations, select models, and receive subscriptions], so that [every investing
action is policy-checked, audited, replayable, and evidence-bound].

Expected behavior:

* Portfolio CRUD: users create, edit (add/adjust/delete holdings), and delete
  portfolios. Each mutation flows through `tkings`->`tknorm`->`tkdedu`->`tkaudt`.
  The portfolio state is reconstructable from the audit chain.
* Exposure visualization: the app renders pie charts of current exposure by industry
  and sector, computed from auditable holding records. Charts are deterministic
  functions of the same state that powers policy checks.
* Target exposure and rebalance suggestions: users define target exposure
  (percentages by sector/industry/asset-class). The system compares current to
  target and surfaces `portfolio.rebalance.propose` envelopes for any material
  drift, with explicit scope (which holdings to buy/sell, by how much, against
  which concentration limits).
* Watchlist: users add and remove tickers. Watchlist tickers enter the V4.32
  valuation queue automatically.
* Automatic valuation queue: when a company appears in any portfolio or watchlist,
  it is queued for DCF valuation. The queue respects V4.32 capability checks
  (`valuation_market_data.read`, `valuation_financials.read`, `valuation_analysis.analyze`).
  Valuation runs use the user's selected model for any LLM-powered evidence
  generation, but the DCF math itself is deterministic.
* Model selection: users select an LLM model per portfolio or per watchlist item
  from four tiers: (1) local open-source (e.g., Qwen, Llama), (2) OpenAI,
  (3) Anthropic Claude, (4) Tickoni subscription (finance-tuned models fine-tuned
  on financial reasoning). The selection is stored as capability scope on the
  `tkmodl` model request, so token budgets, retry limits, and audit attribution
  follow the same governance as any other model call.

## Why Now

M5 has been sitting as a two-line description in the milestone backlog. The runtime
(P0), the capability model (P1), and the V4.32 valuation engine are all specified
and partially implemented. Wires the three together now converts Tickoni from a
governed event engine with a valuation calculator into a demonstrable consumer
investing product. It also produces a clean demo moment: create a portfolio, see
exposure, get a rebalance suggestion, watch a company get auto-valued. This is the
minimum end-to-end investing flow that proves Tickoni's value proposition to a
consumer audience.

## Example Scenario

```text
Given:  A user creates a portfolio "Growth" with holdings: AAPL (50 shares),
        MSFT (30 shares), TSLA (10 shares), NVDA (20 shares), and USD 5,000 cash.
        The user sets target exposure: Technology 40%, Healthcare 20%,
        Financials 20%, Consumer 15%, Energy 5%.
When:   The user opens the portfolio view.
Then:   Tickoni renders pie charts showing Technology 82% (drift: +42%),
        Healthcare 0% (drift: -20%), Financials 0% (drift: -20%),
        Consumer 0% (drift: -15%), Energy 0% (drift: -5%).
        A rebalance suggestion appears: "Sell 20 shares AAPL, buy 15 shares JNJ,
        buy 10 shares JPM, buy 5 shares XOM" as a
        `portfolio.rebalance.propose` envelope with capability scope,
        concentration limits, and approval-required status.
When:   The user adds "AMZN" to their watchlist.
Then:   Tickoni queues AMZN for V4.32 DCF valuation. The valuation uses
        the user's selected model (e.g., "local-openai/gpt-4o") for evidence
        generation but runs the DCF math deterministically. When complete,
        the user receives a subscription event: "AMZN valuation complete:
        intrinsic value USD 175-220 (Monte Carlo 90% CI), recommendation:
        hold within current sector limits." The recommendation includes
        a `valuation.analysis.propose` record with evidence hashes and
        assumption transparency report.
```

## Product Boundaries

### In Scope

* Portfolio CRUD: create, edit (add/adjust/delete holdings with shares/notional),
  delete. Base currency support.
* Exposure computation and pie chart rendering: sector, industry, asset-class
  breakdown from auditable holding records.
* Target exposure management and rebalance suggestion generation.
* Watchlist CRUD: add/remove tickers with optional notes.
* Automatic valuation queue for portfolio and watchlist companies.
* V4.32 DCF valuation integration with capability checks.
* Model selection: per-portfolio or per-watchlist LLM model choice from four tiers
  (local open-source, OpenAI, Anthropic Claude, Tickoni subscription finance-tuned).

### Out Of Scope

* Live order placement or any execution path.
* Portfolio optimization or modern portfolio theory (Markowitz, Black-Litterman).
* Factor models, alpha generation, or performance ranking.
* Direct market data ingestion (assumed provided as input/fixture per V4.32).
* Social/clone/copy portfolio features (deferred to M7).
* Multi-currency portfolio reconciliation (single base currency per portfolio).
* Tax-lot accounting or harvest-loss tracking.
* Options, futures, leveraged/inverse ETFs.
* Push notifications / device push: server-side subscription delivery of valuation
  completions and rebalance updates is a separate feature (future iteration).

### Authority Boundary

| Action class | Proposed boundary |
| --- | --- |
| Observe | Allowed for portfolio/watchlist owners; scoped to owned portfolios only |
| Analyze | Allowed; exposure computation, valuation math are deterministic |
| Draft | Allowed; rebalance suggestions are drafts, not execution |
| Recommend | Allowed; `valuation.analysis.propose` and `portfolio.rebalance.propose` envelopes carry evidence |
| Propose | Policy check required; `trading_portfolio.read` scope; `portfolio.rebalance.propose` requires approval for concentration-limit breaches |
| Prepare | Signed envelope for proposal; sandbox only for adapter reads |
| Execute | Denied / paper only / approval-required for money-impacting changes |
| Override/Administer | Denied / out of scope |

## Fit Against Product Principles

| Principle | How this proposal fits | Concern / open question |
| --- | --- | --- |
| Financial consequence over generic tool access | Every UI action (add holding, delete position, accept rebalance suggestion) produces a policy-checked capability envelope with explicit financial scope | Valuation queue needs a clear "queued" state that users can inspect without triggering model calls |
| Proposal-first agent behavior | Agents only produce investigation reports and proposal envelopes; execution is always denied or approval-required | Need to decide if rebalance suggestions are agent-drafted or computation-drafted |
| Policy gates and approval paths | `portfolio.rebalance.propose` goes through `tkpoly`; concentration-limit breaches require approval; valuation proposals carry full capability scope | Concentration limits: per-name cap, per-sector cap, or both? |
| Audit-grade evidence | Every portfolio mutation is audited; every valuation run produces a replay capsule; every proposal carries evidence hashes | Audit trail for portfolio state: append-only holding changes, or a separate state log? |
| Deterministic replay or replay-safe substitution | Replay runs portfolio mutations against the same event stream; valuation uses deterministic seeds and substituted model outputs | Replay of valuation: do we substitute the full DCF output or just the model evidence portion? |
| Bounded model/tool/adapter spend | Model selection is stored as `tkmodl` capability scope; token budgets, retry limits, and context limits apply per-valuation | Multiple watchlist tickers queued simultaneously: per-ticker budget or aggregate portfolio budget? |
| Fail-closed behavior | Invalid holding records rejected by normalization; missing ERP data blocks valuation; malformed rebalance proposals denied by policy | What happens when a watchlist ticker is delisted mid-valuation? |
| No live side effects unless explicitly approved | Paper-only rebalance suggestions; no adapter calls to broker APIs; valuations run against local/fixture data | Subscription delivery: does the subscription system itself need audit? |

## Evidence Needed To Promote

* [ ] A concrete workflow or demo moment exists (create portfolio -> see exposure -> get rebalance suggestion -> watch ticker -> see valuation).
* [ ] The controlled financial consequence is clear (portfolio state machine, not an opaque database).
* [ ] The relevant policy/capability boundary is known (`portfolio.rebalance.propose`, `trading_portfolio.read`, concentration limits).
* [ ] The proposal has an observable audit/replay/evidence value.
* [ ] Non-goals are explicit (no execution, no optimization, no alpha).
* [ ] The idea can be split into independently testable epic/story work.

## Risks And Anti-Fit Signals

This should not move forward if:

* it mainly improves portfolio UI polish without a financial-control outcome
* it encourages autonomous portfolio rebalancing or auto-trading
* it makes portfolio performance, PnL, or Sharpe ratio the dominant product object
* it cannot identify the relevant policy, approval, evidence, or replay boundary
* it requires live broker or market-data integration before Tickoni has a safe
  paper/sandbox path
* it duplicates an epic/story that already covers the same outcome (check V1.11
  investment demo -- does it already partially cover portfolio management?)
* the valuation queue becomes an unbounded background job that bypasses
  `tkdisp`->`tkagnt`->`tkmodl` bounded-agent governance

## Open Decisions

| Decision | Options | Owner / next step |
| --- | --- | --- |
| Rebalance draft source | Agent-drafted (`tkagnt` produces suggestion) vs computation-drafted (deterministic exposure diff produces suggestion) | Product: computation-drafted is simpler and replay-stable; agent-drafted adds evidence but is non-deterministic |
| Valuation queue ownership | `tkdisp` schedules queued valuations as bounded agent runs vs a dedicated `tkvalq` tile | Platform: `tkdisp` keeps governance consistent; `tkvalq` isolates the queue but adds a new tile |
| Model selection granularity | Per-portfolio model vs per-watchlist-item model vs global model | Product: per-portfolio is sufficient for V1; per-watchlist adds complexity |
| Subscription delivery | WebSocket to CaseOps API vs event-sourced analytics store table vs both | Platform: WebSocket to `tkapi` is the minimal path; analytics store table for audit/replay |
| Concentration limit model | Per-name cap only vs per-sector cap only vs both | Policy: both is safer but requires policy table changes |
| Portfolio state storage | Audit chain reconstruction only vs indexed holding table in the analytics store | Platform: audit chain is the source of truth; the analytics store indexed table for performant exposure queries |

## Graduation Path

If accepted, this should become:

* [x] Epic: when it spans multiple stories and delivers a complete product increment
* [ ] Story: when it is independently implementable and verifiable
* [ ] Documentation: when it clarifies positioning, policy, capability, or operator behavior
* [ ] Decision record: when it primarily resolves a product/architecture/policy choice

Suggested next artifact:

* [ ] Create epic using `epic-template.md`
* [ ] Create stories using `story-template.md` for: (1) portfolio CRUD, (2) exposure + rebalance, (3) watchlist + valuation queue, (4) model selection + subscriptions
* [ ] Update `capabilities.md` with `portfolio.rebalance.propose`, `portfolio.read`, `watchlist.read`, `valuation_queue.manage`
* [ ] Create capability/policy decision for concentration limits and rebalance approval thresholds
* [ ] Update `doc/strategy/roadmap/milestones/m4.md` with the graduated epic/stories
* [ ] Keep in backlog with notes if rejected
