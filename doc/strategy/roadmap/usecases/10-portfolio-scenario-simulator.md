# UC-10: Portfolio Scenario Simulator — "What If" Risk Analysis

## Description

The user asks counterfactual questions about their portfolio:

1. **"What if QQQ drops 20%?"** — simulate the impact on the current portfolio given a hypothetical market move.
2. **"What if I had allocated 25% instead of 0.5% to each position?"** — rerun the current portfolio with different allocation weights to show the difference.
3. **"What if interest rates rise 100bps?"** — simulate portfolio impact given a macro shock.

This is a **scenario simulation**: the agent takes the user's current portfolio, applies hypothetical conditions, and shows the projected impact. It's not replaying past events — it's simulating futures that haven't happened.

Unlike Bloomberg or Interactive Brokers, which only show current state and basic risk metrics, this gives the user **counterfactual simulation** grounded in their actual portfolio with full policy, audit, and traceability.

## Flow

```mermaid
sequenceDiagram
    participant Term as Terminal (UI)
    participant API as tkapi (CaseOps API)
    participant Case as tkcase (Case scope)
    participant Disp as tkdisp (Dispatch)
    participant Agnt as tkagnt (Agent — scenario analysis)
    participant Modl as tkmodl (Model Gateway)
    participant Port as tkport (Portfolio — read current state + simulate)
    participant Tkr as tktkr (Market Data — reference indices, rates, etc.)
    case User asks question
        Term->>API: POST /simulate {scenario: "QQQ -20%", account_id: 2001}
    end
    API->>Case: tkcase.create (workflow=simulation, account=2001, scenario)
    Case-->>API: case_id = sim_QQQ20_20240615
    API->>Disp: SCHEDULE scenario_agent (case_id, account, scenario)
    Disp->>Agnt: AGENT_REQUEST (scenario analysis, capability envelope)
    Agnt->>Port: portfolio.read (account=2001, current holdings)
    Port-->>Agnt: current portfolio snapshot
    Agnt->>Tkr: reference_data (QQQ current price, sector weights, sector index data)
    Tkr-->>Agnt: reference data
    Agnt->>Port: portfolio.simulate (holdings, scenario parameters)
    Port-->>Agnt: simulated portfolio (new values, sector drift, per-position impact)
    Agnt->>Modl: MODEL_REQUEST (scenario analysis: breakdown impact, explain drivers, suggest actions)
    Modl-->>Agnt: model analysis
    Agnt->>Agnt: synthesizes findings
    Agnt->>Audt: AUDIT scenario_result (case_id, scenario, portfolio impact, suggested actions)
    Agnt-->>Disp: terminal result
    Disp-->>API: simulation report
    API-->>Term: scenario report (before/after values, impact breakdown, suggested actions)
```

## Tile Inventory

| Tile | Runtime ID | Responsibility | Status |
|------|-----------|----------------|--------|
| `tkapi` | `tkapi0` | Receives simulation request | **MISSING** — see UC-01 |
| `tkcase` | `tkcase0` | Creates scenario scope | **PARTIALLY** — `tk_pass_stem.c` placeholder |
| `tkdisp` | `tkdisp` | Dispatches scenario agent | **EXISTING** — in investment workflow |
| `tkagnt` | `tkagnt` | Runs scenario analysis agent | **PARTIALLY** — needs `runScenarioAgent` |
| `tkmodl` | `tkmodl` | Model gateway for analysis | **EXISTING** — fixture/replay |
| `tkport` | `tkport0` | Portfolio — `portfolio.read` + `portfolio.simulate(holdings, scenario)` | **MISSING** — see UC-03 |
| `tktkr` | `tktkr0` | Market data — reference indices, rates, sector data for scenarios | **MISSING** — see UC-01 |
| `tkaudt` | `tkaudt` | Audit — records `scenario_result` | **PARTIALLY** — needs `scenario_result` record type |
| `tkmetr` | `metric` | Metrics | **EXISTING** |
| `tkdiag` | `tkdiag` | Diagnostics | **EXISTING** |

### What exists today (supporting)

- **`portfolio.BrokerageAccount`** — `Holding`, `AffordabilityResult`, five fixture accounts.
- **`portfolio.checkAffordability`** — affordability check logic.
- **`mock_adapter`** — canned `portfolio_snapshot`, `quote_snapshot`.
- **`mock_broker_market_server`** — HTTP stub for portfolio and quotes.

### What's needed

1. Implement `tkport.portfolio.simulate(holdings, scenario)` — takes current holdings and hypothetical parameters (e.g., "QQQ -20%", "rates +100bps"), computes new portfolio values, sector exposure, per-position impact, and total P&L.
2. Implement `tktkr.reference_data(scenario_type)` — returns reference indices, sector weights, rates, or other macro data needed to interpret the scenario (e.g., QQQ current price, SPY level, Treasury yield).
3. Implement `runScenarioAgent` — bounded agent that:
   - Reads current portfolio state
   - Reads reference data for the scenario
   - Runs `portfolio.simulate` with scenario parameters
   - Calls model for analysis (explain impact, identify drivers, suggest actions)
   - Produces a scenario report with before/after values and recommended actions
4. Add `scenario_result` record type to `tkaudt` — includes case_id, scenario description, before/after portfolio values, impact breakdown.
5. Implement `tkapi` handler for `POST /simulate` — accepts scenario description and account ID.
6. Wire `tkcase` into the simulation topology.

### System test approach

- Launch the scenario simulation topology with `tkapi`, `tkcase`, `tkdisp`, `tkagnt`, `tkmodl`, `tkport`, `tktkr`, `tkaudt`, `metric`, `tkdiag`.
- Use `mock_adapter` with `technology_heavy` fixture (82% tech, owns GOOG/AMZN/NVDA).
- Use `mock_model` for scenario analysis with canned response.
- Send `/simulate?scenario=QQQ-20%&account_id=2001` through `tkapi`.
- Verify: `tkport` computed correct simulated portfolio values for QQQ -20% scenario; `tkagnt` ran analysis and produced findings; `tkaudt` recorded `scenario_result`; terminal received the report.
- Verify impact: QQQ position shows ~-20% impact; total portfolio impact is weighted average of all tech positions affected by QQQ move.
- Test multiple scenarios: "rates +100bps", "tech sector -15%", "NVDA +30%".
