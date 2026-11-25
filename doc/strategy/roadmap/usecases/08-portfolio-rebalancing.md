# UC-08: Portfolio Rebalancing — GOOG trim / AMZN add

## Description

The user holds GOOG and decides to investigate. After analysis, the user decides to trim GOOG and add AMZN — same sector (tech), but more diversified or introducing a growth angle not previously present. This is a **case-scoped rebalancing**: a single case groups the investigation, the policy decisions, the agent findings, the human approval, and the multi-trade execution.

The flow creates a case (`case_rebalance_{timestamp}`) that scopes all events under one deterministic sequence. This is different from UC-03/UC-04 (single trade) and UC-07 (exposure monitoring) — it's a multi-trade operation driven by agent investigation with human approval.

## Flow

```mermaid
sequenceDiagram
    participant Term as Terminal (UI)
    participant tkA as tk_gate (semantic API)
    participant tkI as tkings (canonical framing)
    participant tkN as tknorm (normalization)
    participant tkD as tkdedu (deduplication)
    participant tkC as tkcase (Case scope)
    participant tkS as tkdisp (Dispatch)
    participant tkG as tkagnt (Agent — investigation)
    participant tkM as tkmodl (Model Gateway)
    participant tkP as tkpoly (Policy)
    participant tkR as tkport (Portfolio)
    participant tkX as tkexec (Execution)
    participant tkB as tkbrok (Broker Bridge)
    participant tkL as tkledg (Ledger)
    participant tkU as tkaudt (Audit)

    Term->>tkA: ui_cmd — investigate (GOOG, account_id=2001, case_id=X)
    tkA->>tkI: event (case_id=X, type=investigate)
    tkI->>tkN: normalized event
    tkN->>tkD: deduplicated event
    tkD->>tkC: case-scoped event
    tkC->>tkP: policy check (investigate — read event)
    tkP-->>tkC: allow
    tkC->>tkU: AUDIT case_created (case_id=X, workflow=rebalance)
    tkU-->>tkC: committed
    tkC->>tkS: SCHEDULE agent_run (investigation, case_id=X)
    tkS->>tkG: AGENT_REQUEST (GOOG investigation, case_id=X, capability envelope)
    tkG->>tkM: MODEL_REQUEST (GOOG analysis: fundamentals, valuation, risk)
    tkM-->>tkG: model response
    tkG->>tkR: tktool/tkadpt — portfolio.read (GOOG holding details)
    tkR-->>tkG: GOOG position data
    tkG->>tkG: agent analyzes GOOG, proposes AMZN as replacement
    tkG->>tkU: AUDIT investigation_propose (case_id=X, agent recommendation: trim GOOG, add AMZN)
    tkU-->>tkG: committed
    tkG-->>tkS: terminal result
    tkS-->>tkA: investigation result with recommendation
    tkA-->>Term: ui_rsp — GOOG analysis + recommendation (trim X shares GOOG, add Y shares AMZN)
    Term->>tkA: ui_cmd — trade_propose (case_id=X, trim GOOG, add AMZN)
    tkA->>tkI: event (case_id=X, type=trade_propose)
    tkI->>tkN: normalized event
    tkN->>tkD: deduplicated event
    tkD->>tkC: case-scoped event
    tkC->>tkP: policy check (rebalance: sell GOOG + buy AMZN, case_id=X)
    tkP->>tkR: tktool/tkadpt — portfolio.simulate (post-rebalance: less GOOG, more AMZN, same sector)
    tkR-->>tkP: simulated portfolio
    tkP-->>tkC: allow (same sector, within limits)
    tkC->>tkU: AUDIT trade_propose (case_id=X, GOOG sell, AMZN buy, outcome)
    tkU-->>tkC: committed
    tkC-->>tkA: dual-trade proposal with case context
    tkA-->>Term: ui_rsp — dual-trade proposal
    Term->>tkA: ui_cmd — trade_execute (case_id=X, ticket_ids=[goog_sell, amzn_buy])
    tkA->>tkI: event (case_id=X, type=trade_execute)
    tkI->>tkN: normalized event
    tkN->>tkD: deduplicated event
    tkD->>tkP: policy check (re-validation: case_id=X)
    tkP-->>tkD: allow
    tkD->>tkX: approved_execution.execute (case_id=X, signed envelope)
    tkX->>tkB: broker.place_order (GOOG, sell, quantity)
    tkB-->>tkX: GOOG fill
    tkX->>tkB: broker.place_order (AMZN, buy, quantity)
    tkB-->>tkX: AMZN fill
    tkX->>tkR: tktool/tkadpt — portfolio.update (reduce GOOG, add AMZN)
    tkR-->>tkX: updated
    tkX->>tkL: ledger_entry (GOOG sell transfer, AMZN buy transfer)
    tkL-->>tkX: ledger committed
    tkX->>tkU: AUDIT trade_execute (case_id=X, both fills, ledger entries)
    tkU-->>tkX: committed
    tkX-->>tkA: execution result
    tkA-->>Term: ui_rsp — rebalance complete (GOOG sold @X, AMZN bought @Y, case closed)
```

## Tile Inventory

| Tile | Runtime ID | Responsibility | Status |
|------|-----------|----------------|--------|
|| `tk_gate` | `tk_gate` | Semantic API tile — receives investigate/trade_propose/trade_execute via ui_cmd, routes to tkings, returns ui_rsp | **MISSING** |
| `tkcase` | `tkcase0` | Creates deterministic case scope, attaches events to case, provides replay capsule | **PARTIALLY** — `tk_pass_stem.c` placeholder exists |
| `tkdisp` | `tkdisp` | Schedules investigation agent run | **EXISTING** — in investment workflow topology |
| `tkagnt` | `tkagnt` | Bounded investigation agent — analyzes GOOG, proposes AMZN | **PARTIALLY** — `runInvestmentAgent` exists for trading; needs `runInvestmentInvestigationAgent` |
| `tkmodl` | `tkmodl` | Model gateway for GOOG analysis | **EXISTING** — fixture/replay |
| `tkpoly` | `tkpoly` | Policy check for rebalance capability envelope (sell GOOG + buy AMZN) | **PARTIALLY** — exists, needs rebalance capability rules |
| `tkport` | `tkport0` | Portfolio read + simulate post-rebalance | **MISSING** — see UC-03 |
| `tkbrok` | `tkbrok` | Broker bridge — executes GOOG sell and AMZN buy | **MISSING** — see UC-04, broker-bridge.md |
| `tkexec` | `tkexec0` | Approved execution for the swap | **MISSING** — see UC-04 |
| `tkledg` | `tkledg0` | Ledger — stores both transfers | **MISSING** — see UC-04 |
| `tkaudt` | `tkaudt` | Audit — records case_created, investigation_propose, trade_propose, trade_execute | **PARTIALLY** — needs `case_created`, `investigation_propose` record types |
| `tkmetr` | `metric` | Metrics | **EXISTING** |
| `tkdiag` | `tkdiag` | Diagnostics | **EXISTING** |

### What exists today (supporting)

- **`tk_pass_stem.c`** — placeholder for `tkcase` (exists in tile registry as stub).
- **`runInvestmentAgent`** — bounded agent that calls portfolio, quotes, policy; produces trade ticket.
- **`portfolio.BrokerageAccount`** — 5 fixture accounts with holdings.
- **`trade_ticket.TradeTicket`** — ticket with policy outcome, blocked reasons.
- **`mock_adapter`** — canned portfolio_snapshot, quote_snapshot.
- **`mock_broker_market_server`** — HTTP stub for portfolio and quotes.

### What's needed

1. Implement `tkcase` tile process: `case.create` creates a deterministic case scope with workflow, actor, account, and initial scope. `case.attach` attaches events to the case. `case.capsule` returns all events for replay.
2. Add `case_created`, `investigation_propose`, `rebalance_execute` record types to `tkaudt`.
3. Implement `runInvestmentInvestigationAgent` — bounded agent that analyzes a single ticker (fundamentals, valuation, risk profile) and proposes a rebalancing action (trim/add).
4. Add `rebalance` capability to `tkpoly` — checks sell-side (existing holding, no short-sale issues) and buy-side (notional limits, sector limits, instrument allowlist).
5. Register `tkcase` in tile registry with proper link shape (consumer of `tkgate`, producer to `tkaudt`).
6. Wire `tkcase` into a new rebalance topology.
7. Implement `tk_gate` command handlers: investigate, trade_propose, and trade_execute via shared-memory channels.
8. Implement `tkexec` case-scoped execution: verifies case_id, calls `tkbrok` for both trades, updates `tkport`, posts to `tkledg`, audits via `tkaudt`.

### System test approach

- Launch the rebalance topology with `tk_gate`, `tkings`, `tknorm`, `tkdedu`, `tkcase`, `tkdisp`, `tkagnt`, `tkmodl`, `tkpoly`, `tkport`, `tkbrok`, `tkexec`, `tkledg`, `tkaudt`, `tktool`, `tkadpt`, `metric`, `tkdiag`.
- Use `mock_adapter` with `technology_heavy` fixture (owns GOOG 500 shares, 15% of portfolio).
- Use `mock_model` for GOOG analysis with canned response recommending AMZN.
- Use `tkbrok` default backend (always returns filled).
- Send investigate command through `ui_cmd` channel (case_id=X, type=investigate, ticker=GOOG, account_id=2001).
- Verify: `tkcase` created the case with correct scope; `tkings` canonicalized all events; `tkagnt` ran the investigation and produced a proposal; `tkpoly` allowed the rebalance (same sector, within limits); `tkaudt` recorded `case_created` and `investigation_propose`; terminal received the recommendation via `ui_rsp`.
- Send trade_execute command through `ui_cmd` channel (case_id=X, type=trade_execute).
- Verify: `tkexec` executed both trades; `tkport` updated (less GOOG, more AMZN); `tkledg` posted both transfers; `tkaudt` recorded `rebalance_execute`; case is complete.
- Replay test: captured capsule with substituted model, broker, and ledger data produces identical rebalance result.
- Test policy deny: rebalance that exceeds sector limit (e.g., add 3 more tech positions when already at 20%) — `tkpoly` should deny.
