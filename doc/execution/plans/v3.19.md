# TKNI Phase 0 — UX Plan

**Role:** Apple-style UX designer thinking.
**Scope:** UX only — what the terminal looks like, how it works, how the operator interacts with it. Not how it's wired, built, or coded.
**Phase 0 definition:** The investment workflow (thesis → basket → policy → impact → proof) rendered in a terminal interface. Milestone 0/1 = full event pipeline (ingestion, normalization, dedup, policy, audit, replay, metrics, diagnostics) plus the complete investment schema layer. Milestone 2 = Firedancer integration hardening (infrastructure only — no new user-facing features). The investment schema (thesis, basket, impact, drift, catalog, cards, trade ticket, classification, portfolio, audit, replay, conformance) and demo system (4 scenarios) ARE implemented in code. The terminal UI is a stub (370B QML, 331B main.cpp) — this plan defines what it SHOULD render based on what's actually coded.

---

## 1. What Tickoni Already Has (Feature Inventory — Milestone 0/1)

Milestone 0/1 delivers the complete investment investigation flow. Here's what the terminal can actually render:

|| Feature | Source | What the UI Can Show |
|---|---|---|
|| Plain-English thesis input & normalization | thesis.zig (60,529 bytes / 1311 lines) | `ThesisInput`, `InvestorIntent`, `normalize()`, 11 fixtures (ai_infrastructure, us_dividends, cyber_security, etc.), denial payloads, hash functions |
|| Investable universe with restricted denylist | catalog.zig (25,003 bytes / 522 lines) | `Catalog` with denylist (SOXL, SPXL, leveraged ETFs), 125+ instrument entries, `filterByTheme()`, `filterBySector()`, `lookupByTicker()` |
|| Basket construction with concentration rules | basket.zig (47,720 bytes / 1093 lines) | `Basket` with 16 instruments max, `buildFromScreening()`, `build()`, `screenIntent()`, `RejectedCandidate` with `RejectionReason` enum |
|| Portfolio & affordability (demo account) | portfolio.zig (29,332 bytes / 688 lines) | `BrokerageAccount`, `checkAffordability()`, `checkBasketAffordability()`, `AffordabilityOutcome` enum, fixtures (cash_rich, low_cash, technology_heavy, diversified, restricted_account) |
|| Trade ticket generation | trade_ticket.zig (17,918 bytes / 513 lines) | `TradeTicket`, `TicketLineItem`, `QuoteSnapshot`, `buildMarketBuyTicket()`, `PaperFill`, `PaperExecutionResult` |
|| Paper-only execution | runner.zig (6,762 bytes) + demo | Paper-fill ready state, restricted instrument blocked, `external_effects_disabled: true`, conformance verification |
|| Before/after impact | impact.zig (73,927 bytes / 1773 lines) | `computePreTradeImpact()`, `computeRealizedTradeImpact()`, `generateExplanations()`, `SectorExposure`, `TickerConcentration`, `ImpactExplanation` |
|| Thesis drift conditions | drift.zig (73,125 bytes / 1871 lines) | `ThesisDriftCondition` enum (allocation_breach, sector_exposure_breach, concentration_breach, buying_power_change, instrument_no_longer_eligible), `assessThesisDrift()` |
|| Rebalance suggestion | drift.zig (73,125 bytes / 1871 lines) | `generateRebalanceSuggestion()` → `RebalanceSuggestion` with `RebalanceAdjustment`, `RebalanceDirection` |
|| Classification awareness | classification.zig (25,155 bytes / 649 lines) | `AssetClass` (equity, etf, etc.), `InstrumentType` (stock, etf, etc.), `SectorExposure`, `ThemeId`, canonical taxonomy refs (GICS), 8 known theme IDs, 9 known sector codes |
|| Capability envelopes | capability.zig (541 bytes) + policy tile | Actor, role, workflow, account, capability, model, budget, scope, policy version — schema defined, runtime via policy/ tile |
|| Policy decisions | policy tile (13,045 bytes / mod.zig) | allow/deny with exact `reason_code`, `reason_text`, observed_value vs limit_value |
|| USD 25,000 denial with exact max affordable | demo/scenarios (preflight.zig 21,558 bytes) | Maximum affordable amount, specific boundary that triggered block (per_order_notional), demo scenario "oversized_blocked" |
|| SOXL restricted-instrument denial | demo/scenarios + catalog.zig | Denied before quote or paper-fill, exact `scope_dimension` (restricted_instrument), catalog denylist enforcement |
|| 9-step audit timeline | audit/ tile (21,930 bytes / 4 files) + audit.zig schema (5,314 bytes) | EVENT RECEIVED → INTENT NORMALIZED → BASKET BUILT → REJECTED RECORDED → TICKET VALIDATED → POLICY DECISION → PROPOSAL SIGNED → PAPER FILL READY → REPLAY CAPSULE SEALED |
|| Hash fields | audit/ tile + conformance.zig (5,477 bytes) | Event hash, policy hash, proposal hash (SHA-256 via `conformance.sha256Hex()`) |
|| Replay status | replay/ tile (42,957 bytes / 3 files) | MATCH / DIVERGE / MISSING with `first_divergent_seq`, `capsule.zig`, `hash.zig` |
|| Tamper check | replay/ tile + fixture_replay_capsule_tampered_paper_fill.json | CLEAN / TAMPERED — verified in tampered_replay scenario |
|| Model route & adapter attribution | model/ tile (53,512 bytes / 5 files) + adapter/ tile (24,727 bytes / 3 files) | Display-only (e.g., "offline/mock", "paper_broker:v0"), `backend.zig`, `validator.zig` |
|| Proof bundle export affordance | audit/ + replay/ | Disabled or fixture-only — `fixture_replay_capsule.json` |
|| Data freshness indicators | payment_pipeline/ runtime.zig (11,141 bytes) + metric.zig (1,570 bytes) | "DATA 12s", BUS OK / BUS DEGRADED — via pipeline metrics and bus state |
|| Fixture vs runtime mode | payment_pipeline/ process.zig (13,344 bytes) + runtime.zig | "fixture data — not live API" — `runtime.zig` determines fixture vs live |
|| 5-function navigation | V3.19.S1 + terminal stub | CASE, POLICY, IMPACT, PROOF, SYSTEM — F1-F5 key bindings |
|| Command bar | V3.19.S1 | /show, /explain, /save commands — command bar at bottom of terminal |
|| Midnight Oni visual system | V3.19 epic (roadmap) | Color palette (80% dark, 4% blue focus, 1% semantic accents), typography, proportion rules |
|| Keyboard navigation | V3.19.S1 | Function keys, tab navigation between panels |
|| Before/after portfolio comparison | portfolio.zig + impact.zig | Position weights, sector exposure, cash, buying power — `BrokerageAccount` fixtures, `computePreTradeImpact()` |
|| Thesis card | cards.zig (28,735 bytes / 828 lines) | `ThesisCard`, `MoneyProposalCard`, `DecisionCardsStore`, `buildThesisCard()`, `buildMoneyProposalCard()`, `LinkedPosition` |
|| Demo command | demo/ (80,552 bytes total) | `just demo investment` runs all 4 scenarios: allowed, oversized_blocked, restricted_instrument, tampered_replay |
|| Policy tile | policy/ mod.zig (13,045 bytes) | Core policy evaluation — allow/deny with reason codes |
|| Rebalance suggestion status | drift.zig | `RebalanceSuggestionStatus` enum (NOT_REQUIRED, RECOMMENDED, URGENT), `generateRebalanceSuggestion()` |

---

## 2. The Core UX Problem

Koyfin, Yahoo Finance, and FinChat all solve the same surface problem with the same answer: watchlists + charts + news. They look like dashboards. They feel like consumer apps.

The Bloomberg Terminal does something fundamentally different: it's command-driven, keyboard-first, information-dense, and every pixel has a purpose. There are no charts to admire — every display element exists to support a decision.

**Phase 0's UX problem:** How to present a complete investment investigation (thesis → basket → policy → impact → proof) in a terminal interface that feels like Bloomberg, not like Robinhood or YFinance?

The answer is not "add more panels." It's about **information hierarchy** and **decision flow**.

---

## 3. Phase 0 Terminal Layout — The Canonical View

The terminal uses a 5-function model (CASE, POLICY, IMPACT, PROOF, SYSTEM). But the *default* state should not be five equal panels. It should be a **decision-first layout** that puts the investment workbench front and center, with policy/proof/impact as secondary context layers.

```
+------------------------------------------------------------------------------+
| TKNI  [PAPER]  CASE 493  POLICY v1.11  DATA 12s  BUS OK  REPLAY MATCH       |
|------------------------------------------------------------------------------|
| CASE          POLICY          IMPACT          PROOF          SYSTEM          |
| [ACTIVE]      [INACTIVE]      [INACTIVE]      [INACTIVE]     [INACTIVE]      |
|------------------------------------------------------------------------------|
|                                                                              |
|  THESIS                                                                      |
|  "USD 2,000 in AI infrastructure, no single-name concentration,               |
|   US ETFs and large-cap equities"                                             |
|                                                                              |
|  ACCOUNT STATE          BASKET (4 eligible)         REJECTED (2)             |
|  Cash:   USD 5,240.18   Ticker  Alloc   Weight    Ticker  Status  Reason    |
|  Buy Pwr:USD 5,240.18   NVDA    30.0%  $600.00   SOXL    DENIED  scope     |
|                     AAPL    25.0%  $500.00   URA     BLOCKED min_hold      |
|                     MSFT    25.0%  $500.00                                |
|                     AVGO    20.0%  $400.00                                |
|                                                                              |
|  TICKET SUMMARY       POLICY DECISION           EXPOSURE AFTER               |
|  Side: BUY  Notional: USD 2,000.00            Tech: 22% → 31%              |
|  Account: brokerage.demo_ops                  ETF: 36% → 43%               |
|  Environment: paper                           Single-name: < 8% (OK)       |
|  Status: PAPER_FILL_READY                     Rebalancing: not required    |
|                                                                              |
|  > _                                                                              |
+------------------------------------------------------------------------------+
```

Key design principles:

- **CASE is the default view.** The operator opens the terminal to see the investment. Everything else is a function-key away.
- **Three horizontal bands:** Thesis (top, spans full width), Details (middle, three columns), Decision (bottom, full width).
- **No charts in Phase 0.** Charts are consumer-dashboard thinking. Exposure changes are shown as tabular deltas (22% → 31%).
- **Monospaced values, sans-serif labels.** Tabular numbers for all currency and percentage fields.
- **The command bar is always visible** at the bottom. The operator types commands or uses function keys.

---

## 4. Five Function Panels — UX Detail

### CASE (Investment Workbench)

This is the default screen. It shows everything needed to make an investment decision in one view.

**Layout (three bands):**

Band 1 — THESIS (full width, top)
- Raw thesis text from the user
- Structured intent extracted below: notional, market, sectors, instrument types
- Thesis status: DRAFT / ALLOWED / BLOCKED / REQUIRES_EVIDENCE
- Timestamp

Band 2 — DETAILS (three-column split)
Left column: ACCOUNT STATE
- Cash, buying power, max notional limit
- Environment badge (PAPER / LIVE / SANDBOX)

Center column: BASKET
- Table: ticker, allocation %, dollar weight
- Inclusion reason for each instrument (short text)
- Scrollable if more than 6 items

Right column: REJECTED
- Ticker, denial status, specific reason
- SOXL → "scope: restricted_instrument"
- URA → "min_hold_period not met"
- Compact — one row per rejected item

Band 3 — DECISION (full width, bottom)
- Ticket summary (side, notional, account)
- Policy decision (outcome, policy version, reason code)
- Exposure after (sector deltas, concentration check)
- Action affordance: [PLACE PAPER] or [SAVE PROPOSAL] — disabled when blocked

**Interaction model:**
- Tab through the three detail columns
- Arrow keys navigate within tables
- Enter selects an instrument row → shows detail in a bottom status line (not a new panel)
- Command bar at the bottom for /save, /explain, /show policy

### POLICY

Deep dive into why the decision was made.

```
  POLICY v1.11                                  OUTCOME: ALLOW
  Account: brokerage.demo_ops                   POLICY_VERSION: v1.11.3
  Workflow: trading_order.propose               BUDGET_ID: default

  ┌────────────────────────┬────────────┬────────────┬───────────────────────┐
  | CHECK                  | OBSERVED   | LIMIT      | RESULT                |
  ├────────────────────────┼────────────┼────────────┼───────────────────────┤
  | asset_class            | equity,etf | equity,etf | PASS                  |
  | market                 | US         | US         | PASS                  |
  | venue                  | NYSE       | NYSE,NASDAQ| PASS                  |
  | sector                 | Info Tech  | Info Tech  | PASS                  |
  | instrument_denylist    | —          | SOXL,SPXL  | PASS (none matched)   |
  | notional_limit         | 2000.00    | 5000.00    | PASS                  |
  | daily_notional_limit   | 2000.00    | 10000.00   | PASS                  |
  | single_name_concentration | 30.0%   | 25.0%      | FAIL → waived (ETF)   |
  | holding_period           | —          | 0d         | PASS                  |
  | round_trip              | —          | same_day    | PASS                  |
  | approval_required       | —          | yes        | WAIVED (paper)        |
  └────────────────────────┴────────────┴────────────┴───────────────────────┘

  REJECTION REASONS (if any):
  ──────────────────────────────────────────────────────────────────────────

  EVIDENCE:
  ── evidence_ref: 0x7a3f...c491  catalog:v2.14  taxonomy:GICS 2022
```

Design rules:
- Every check is a single row. No nesting, no expandable trees.
- Three columns: what was checked, what we saw, what the limit is, what the result was.
- Green/Red/Amber left-rule per row (not filled cells).
- PASS in green, FAIL in red, WAIVED in amber.
- One scrollable table. No cards.

### IMPACT

Before/after consequence view.

```
  IMPACT FUNCTION                    PROPOSAL: thesis_493 → basket_772
  Snapshot: 2026-09-08T03:15:42Z      Evidence: 0x2b1e...a903

  ┌──────────────────────┬──────────────────────────────────────────────────┐
  │ CASH & BUYING POWER  │ SECTOR EXPOSURE (BEFORE → AFTER)                 │
  ├──────────────────────┤                                                  │
  │ Cash      Before:    │ Technology    22%  →  31%  [+9pp]  WARNING       │
  │           After:     │ Healthcare    15%  →  15%  [0pp]   OK            │
  │           Change:    │ Financials    12%  →  12%  [0pp]   OK            │
  │           USD 5,240  │ Energy       10%  →  10%  [0pp]   OK            │
  │           USD 3,240  │ Communication  8%  →  8%   [0pp]   OK            │
  │           -USD 2,000 │ Other         33% →  24%  [-9pp]   OK            │
  │                      │                                                  │
  │ Buy Pwr  Before:     │ SINGLE-NAME CONCENTRATION                        │
  │           After:     │ NVDA: 30.0% → 30.0%  (limit 25.0%) WAIVED ETF   │
  │           Change:    │ AAPL: 25.0% → 25.0%  (limit 25.0%) OK           │
  │           USD 5,240  │ MSFT: 25.0% → 25.0%  (limit 25.0%) OK           │
  │           -USD 2,000 │ AVGO: 20.0% → 20.0%  (limit 25.0%) OK           │
  │                      │                                                  │
  │ ETF EXPOSURE         │ ETF EXPOSURE                                     │
  │ Before: 36%          │ Before: 36%  →  After: 43%  [+7pp]  OK          │
  │ After:  43%          │ Limit: 60%                                       │
  │ Limit:  60%          │                                                  │
  │                      │ ALERTS                                           │
  │ REBALANCE SUGGESTION │ ────────────────────────────────────────────────  │
  │ Rebalancing: NOT     │ [•] Technology exposure increased 9pp.          │
  │ REQUIRED             │   Current 31%, limit threshold 35%.             │
  │                      │ [ ] Cash buffer above target.                   │
  │                      │ [ ] Single-name concentration within limits.    │
  └──────────────────────┴──────────────────────────────────────────────────┘
```

Design rules:
- Two-column split: left = cash/buying power, right = exposure/concentration
- Delta shown as "before → after [+/-pp]" — points percentage, not percent
- Color-coded left-rule per section (green = OK, amber = near threshold, red = breach)
- Alerts at bottom right — compact bullet list, not cards

### PROOF

The black box. Every auditor wants this screen.

```
  PROOF FUNCTION                                   REPLAY: MATCH
  Case ID: 493                                     TAMPER: CLEAN
  Action ID: act_8f3a2c1d                          EXPORT: [DISABLED]

  ┌─ HASH SUMMARY ───────────────────────────────────────────────────────────┐
  │ Event Hash:     0x4b7c...e912                                              │
  │ Policy Hash:    0x1a2d...f456                                              │
  │ Proposal Hash:  0x9e8f...a123                                              │
  └──────────────────────────────────────────────────────────────────────────┘

  ┌─ 9-STEP AUDIT TIMELINE ──────────────────────────────────────────────────┐
  │                                                                          │
  │  1. EVENT RECEIVED      03:14:01.003  src=tk_api  offset=49201            │
  │  2. INTENT NORMALIZED   03:14:01.012  tknorm  hash=0x4b7c...e912          │
  │  3. BASKET BUILT        03:14:01.045  tkpoly  basket_id=772              │
  │  4. REJECTED RECORDED   03:14:01.047  tkpoly  SOXL→scope, URA→min_hold  │
  │  5. TICKET VALIDATED    03:14:01.051  ticket_id=tkt_55e1  valid=true     │
  │  6. POLICY DECISION     03:14:01.053  tkpoly  outcome=ALLOW              │
  │  7. PROPOSAL SIGNED     03:14:01.055  hash=0x9e8f...a123                │
  │  8. PAPER FILL READY    03:14:01.058  status=PAPER_FILL_READY           │
  │  9. REPLAY CAPSULE SEALED 03:14:02.101 repl_id=rpl_00493  status=MATCH  │
  │                                                                          │
  └──────────────────────────────────────────────────────────────────────────┘

  ┌─ ATTRIBUTION ────────────────────────────────────────────────────────────┐
  │ Model Route:    offline/mock                                             │
  │ Adapter:        paper_broker:v0                                          │
  │ Actor:          investor                                                 │
  │ Agent:          trading_control_agent                                    │
  │ Approval:       WAIVED (paper mode)                                      │
  │ Evidence Ref:   0x7a3f...c491                                            │
  └──────────────────────────────────────────────────────────────────────────┘
```

Design rules:
- Single scrollable timeline. No expand/collapse — everything visible.
- Timestamps are compact, monospaced.
- Hashes truncated with expand-on-click for full value (terminal-appropriate density).
- Attribution is separate from the timeline — it's metadata about the decision, not a step in it.

### SYSTEM

Compact availability. Not a dashboard.

```
  SYSTEM FUNCTION

  ┌─ DATA FRESHNESS ─────────────────────────────────────────────────────────┐
  │ CASE data:    12s ago    POLICY data:   12s ago    IMPACT data:   12s ago │
  └──────────────────────────────────────────────────────────────────────────┘

  ┌─ BUS STATUS ─────────────────────────────────────────────────────────────┐
  │ Local bus:    OK        Gateway:       N/A (local mode)                  │
  │ Channel:      ui_evt, ui_rsp, ui_cmd, ui_lval                           │
  │ Sequence:     49201    Gaps:          0       Overflow: 0                │
  └──────────────────────────────────────────────────────────────────────────┘

  ┌─ RUNTIME MODE ───────────────────────────────────────────────────────────┐
  │ Mode:         fixture data — not live API                                │
  │ Fixture set:  v1.11_investment_demo                                      │
  │ Data source:  src/tickoni/test/fixtures/investment/scenarios/            │
  └──────────────────────────────────────────────────────────────────────────┘

  ┌─ AVAILABILITY CONTEXT ───────────────────────────────────────────────────┐
  │ "When BUS DEGRADED or API disconnected, policy decisions may be stale.  │
  │  Action controls are disabled until data freshness is restored."         │
  └──────────────────────────────────────────────────────────────────────────┘
```

Design rules:
- Four small blocks. No charts, no gauges, no animated bars.
- Each block is a labeled key-value or short line.
- The availability context line at the bottom explains what degraded state means for the operator.

---

## 5. Interaction Model

### Keyboard Navigation

```
F1      → switch to CASE
F2      → switch to POLICY
F3      → switch to IMPACT
F4      → switch to PROOF
F5      → switch to SYSTEM

/       → focus command bar (bottom)
Enter   → submit command or confirm action
Tab     → move between panels in CASE view (account → basket → rejected)
↑↓      → navigate within tables
Enter   → select row, show detail in status bar
Esc     → clear command bar, return to previous focus
Ctrl+S  → save proposal (gated by runtime contract)
Ctrl+E  → explain current view (shows policy or evidence context)
Ctrl+P  → show proof for current case
```

### Command Bar Commands

```
/show policy      → focus POLICY panel
/show impact      → focus IMPACT panel
/show proof       → focus PROOF panel
/save             → save proposal (gated)
/explain          → show policy reason for current decision
/replay           → run replay (fixture or live, per runtime)
/case 493         → load case by ID
```

---

## 6. Bloomberg-Specific Features That Koyfin/Yahoo/FinChat Don't Have

These are the differentiators. They're not "features" in the consumer-app sense — they're capabilities that only exist because Tickoni's architecture supports them.

### A. Consequence Before Choice

Bloomberg shows you data. Yahoo Finance shows you charts. FinChat shows you chat + data. **Tickoni shows you what changes if you act.**

Every investment proposal is accompanied by before/after impact — cash, exposure, concentration — calculated in real time and displayed before any action. This is V1.3's core insight. No consumer finance tool does this. Even Bloomberg's portfolio managers have to mentally compute or use a separate tool.

**UX manifestation:** The IMPACT function panel and the exposure deltas shown inline on the CASE workbench.

### B. The Trust Black Box

Bloomberg has compliance mode. Yahoo Finance has nothing. FinChat has nothing. **Tickoni makes the audit trail visible in the UI.**

The PROOF panel shows: event hash, policy hash, proposal hash, the 9-step audit timeline, model route, adapter attribution, replay status (MATCH/DIVERGE/MISSING), and tamper check (CLEAN/TAMPERED). Every auditor's dream. Every hacker's nightmare.

**UX manifestation:** The PROOF function panel. This is the single most Bloomberg-terminal-like screen in Phase 0. Bloomberg operators trust the terminal because they can verify the data chain. Tickoni makes that verifiable chain visible to every user, not just compliance.

### C. Policy as a First-Class UI Element

Bloomberg shows policy as a back-office report. Yahoo Finance has no concept of policy. **Tickoni shows every policy check, every limit, every observed value, and every outcome on the same screen as the investment.**

The POLICY panel isn't "settings" — it's the reason the decision was made or denied. Every check is a row: asset_class, venue, sector, instrument_denylist, notional_limit, holding_period, round_trip, approval_required. Each with observed vs. limit vs. result.

**UX manifestation:** The POLICY function panel. This is what makes Tickoni feel like a real financial system, not an investment screener.

### D. Deterministic Replay Status as a UI Status

No consumer finance tool has this. Even Bloomberg's data feeds can't replay deterministically. **Tickoni shows REPLAY MATCH or REPLAY DIVERGE as a persistent status in the status bar.**

Every time the operator opens a case, they see: was this decision reproducible? MATCH means yes — the same inputs produce the same result. DIVERGE means something changed — a policy version, a catalog update, a data drift. MISSING means no replay capsule exists yet.

**UX manifestation:** The status bar shows "REPLAY MATCH" or "REPLAY DIVERGE" or "REPLAY MISSING" alongside "DATA 12s" and "BUS OK."

### E. Capability Envelope Enforcement (Visible Denials)

Bloomberg lets you trade anything your account allows. Yahoo Finance shows you what you can buy. **Tickoni shows you exactly what was DENIED and WHY.**

The SOXL scenario: restricted instrument, denied before quote or paper-fill. The USD 25,000 scenario: oversized notional, blocked with exact maximum affordable amount ("you can afford USD 3,400, not USD 25,000"). The rejected candidates table shows every instrument that almost made the cut and why it didn't.

**UX manifestation:** The REJECTED column on the CASE workbench. Red left-rules. Exact scope dimension. No hidden affordances.

### F. Thesis → Basket → Ticket Flow

Bloomberg shows watchlists and screeners. Yahoo Finance shows watchlists. FinChat shows watchlists. **Tickoni takes a natural-language thesis and converts it to a structured, policy-checked, affordable investment basket with reasons.**

"USD 2,000 in AI infrastructure, no single-name concentration, US ETFs and large-cap equities" becomes a concrete basket of 4 instruments with allocation weights and 2 rejected instruments with specific rejection reasons.

**UX manifestation:** The THESIS band on the CASE workbench. Raw text → structured intent → basket. This is the "wow moment" — the operator sees their idea become real.

---

## 7. Critical UX Assessment & Recommendations

### What Works Well

1. **Five-function model is right.** CASE/POLICY/IMPACT/PROOF/SYSTEM maps cleanly to operator mental model: what is this, why was this allowed, what changes, can I verify it, is the system alive.
2. **Midnight Oni visual system is on-target.** 80% dark surfaces, 4% blue focus, 1% semantic accents. This is terminal-appropriate. Bloomberg's interface is similarly restrained.
3. **Command bar + function keys is the right interaction model.** Keyboard-first, dense, no mouse dependency.
4. **Consequence-before-choice is a genuine differentiator.** No consumer tool does this.

### What Needs Improvement

#### 1. The CASE Panel Has Too Many Concepts

The current CASE design tries to show thesis, account state, basket, rejected, ticket, policy decision, exposure, and action affordance all in one view. That's 8 concepts. Even Bloomberg doesn't do that on one screen.

**Recommendation:** Split CASE into a two-tier view.
- Tier 1 (default): thesis + basket + rejected (the investment decision)
- Tier 2 (toggle or /show): account + ticket + policy + exposure + action (the governance context)

The operator should see the investment first, then drill into governance. Not both simultaneously. Use a toggle or a second function key (F6 = INVEST / F7 = GOVERNANCE) within the CASE function, or use the command bar to toggle between "investment view" and "governance view."

#### 2. Missing: Multi-Case Workflow

The roadmap assumes one case per terminal session. Real operators work with multiple cases simultaneously. A Bloomberg operator has 5-10 screens open. Phase 0 should support at least a **case list** — a way to switch between cases without losing context.

**Recommendation:** Add a collapsible case list sidebar (left edge, 3 cases visible) or a /case N command. At minimum, the status bar should show how many cases are loaded and allow navigation.

#### 3. Missing: The "So What?" Layer

The IMPACT panel shows "Technology exposure 22% → 31%." But what should the operator *do* about that? Bloomberg doesn't show data without context. FinChat shows data without guidance. Tickoni has the policy system to provide guidance.

**Recommendation:** Add a **guidance strip** below the main content that translates data into action:
```
  GUIDANCE
  ──────────────────────────────────────────────────────────────────────────
  [!] Technology exposure +9pp. Within limit (35%), but near threshold.
  [✓] Single-name concentration OK. ETF waiver applied for NVDA.
  [✓] Rebalancing not required.
  [i] Cash buffer USD 3,240.18. Min target: USD 2,000.00.
```
This is Bloomberg's "what to think about" — not automated advice, but structured guidance based on policy. It's the difference between "here's data" and "here's what matters."

#### 4. Missing: Thesis Health Status

V1.3 defines thesis drift conditions: allocation breach, sector exposure breach, concentration breach, instrument no longer eligible, buying-power change. These are computed by the runtime but only shown in the IMPACT panel as post-hoc deltas.

**Recommendation:** Add a **thesis health indicator** on the THESIS band (CASE view):
```
  THESIS STATUS: HEALTHY    Last checked: 03:14:02Z
  ── Allocation within limits. Sector exposure nominal.
```
Status colors: HEALTHY (green), DRIFT (amber — near threshold), BREACH (red — limit exceeded). This is what makes Tickoni feel alive — not a static snapshot, but a continuously evaluated thesis.

#### 5. The Status Bar Is Too Sparse

Current status bar: `TKNI | PAPER | CASE 493 | POLICY v1.11 | DATA 12s | BUS OK | REPLAY MATCH`

This is good but missing critical context for an operator deciding whether to act.

**Recommendation:** Add environment badge, case count, and action state:
```
  TKNI  [PAPER]  CASE 493  CASES:3  POLICY v1.11  DATA 12s  BUS OK  REPLAY MATCH  ACTION: ENABLED
```

#### 6. No "Default View" Mental Model for New Operators

A Bloomberg operator knows the terminal because they use it every day. A new operator opening Tickoni needs to know: "what am I supposed to do first?"

**Recommendation:** The default CASE view should have a **guided state** for the first interaction:
```
  ──────────────────────────────────────────────────────────────────────────
  Welcome. Type a thesis to begin, or /show policy to inspect rules.
  ──────────────────────────────────────────────────────────────────────────
```
Once a thesis is entered, the guided state is replaced by the actual investment view. This is the "onboarding without onboarding" approach — the terminal guides without leaving the terminal paradigm.

---

## 8. Bloombergo Features — The "Screams Terminal" Checklist

Here's a checklist of what makes an interface feel like a real terminal vs. a dashboard app:

|| Feature | Bloomberg | Yahoo Finance | Tickoni Phase 0 |
|---|---|---|---|
| Keyboard-first navigation | Yes | No | Yes (F-keys, command bar) |
| Monospaced tabular values | Yes | Partial | Yes |
| Dense information layout | Yes | No | Mostly (needs refinement) |
| Command-driven input | Yes | No | Yes |
| No charts as default | Yes | Yes (default is charts) | Yes |
| Persistent status bar | Yes | No | Yes |
| Multi-panel, not multi-tab | Yes | Tabs | Panels |
| Semantic color (not decorative) | Yes | Yes | Yes (Midnight Oni) |
| Audit trail visible | Compliance mode only | No | Yes (PROOF panel) |
| Before/after consequence | Portfolio tools | No | Yes (IMPACT panel) |
| Policy enforcement visible | Back-office report | No | Yes (POLICY panel) |
| Replay/determinism visible | No | No | Yes (status bar) |
| Explicit denials with reason | Yes | No | Yes (REJECTED column) |
| Natural-language to structured | No | No | Yes (THESIS band) |
| No celebratory animation | Yes | Yes | Yes |
| Dark, cold, restrained | Yes | Yes | Yes (Midnight Oni) |

**Tickoni Phase 0 scores 15/16.** The one gap is that the CASE panel is slightly too cluttered (see recommendation #1). The rest is terminal-authentic.

---

## 9. Phase 0 Visual Mockup — ASCII Wireframe

Here's the complete Phase 0 default view (CASE function, allowed basket scenario):

```
+==================================================================================+
| TKNI  [PAPER]  CASE 493  CASES:1  POLICY v1.11  DATA 12s  BUS OK  REPLAY MATCH  |
+==================================================================================+
| CASE          POLICY          IMPACT          PROOF          SYSTEM              |
| [ACTIVE]      [INACTIVE]      [INACTIVE]      [INACTIVE]     [INACTIVE]          |
+==================================================================================+
|                                                                                  |
|  THESIS                                                                          |
|  "USD 2,000 in AI infrastructure, no single-name concentration,                    |
|   US ETFs and large-cap equities"                                                 |
|  Structure: notional=USD 2000  market=US  sectors=[Info Tech]                     |
|  Status: ALLOWED  Thesis ID: th_493  Created: 2026-09-08T03:14:01Z               |
|                                                                                  |
|  ACCOUNT STATE          BASKET (4 eligible)         REJECTED (2)                  |
|  ────────────           ──────────────────          ────────────                  |
|  Cash:   USD 5,240.18   NVDA    30.0%  $600.00   SOXL    DENIED  scope: restricted|
|  Buy Pwr:USD 5,240.18   AAPL    25.0%  $500.00   URA     BLOCKED min_hold period |
|  Max Not:USD 10,000.00  MSFT    25.0%  $500.00                                       |
|                     AVGO    20.0%  $400.00                                       |
|                                                                                  |
|  GUIDANCE                                                                          |
|  [!] Technology exposure +9pp (31%). Near threshold (35%).                        |
|  [✓] Single-name concentration within limits. ETF waiver applied.                 |
|  [✓] Cash buffer USD 3,240.18. Min target: USD 2,000.00.                          |
|  [✓] Rebalancing not required.                                                    |
|                                                                                  |
|  DECISION          TICKET          POLICY          ACTION                         |
|  Outcome: ALLOWED  Side: BUY        Policy: v1.11.3  [PLACE PAPER]               |
|  Ver: v1.11.3      Notional:        Reason: all    Status: ENABLED                |
|                    USD 2,000.00     checks pass                         Saved: no  |
|                    Account:                                                         |
|                    brokerage.demo_ops                                               |
|                                                                                  |
|  > _                                                                              |
+==================================================================================+
```

This is one screen. Everything needed to make a decision is here. Nothing decorative. Every line has a purpose. The operator can:
- See their thesis (top band)
- See what was accepted and rejected (middle)
- See what changes (guidance strip)
- See the decision and action affordance (bottom)
- Type a command (command bar)

Switch to POLICY (F2) for the deep policy check table. Switch to IMPACT (F3) for before/after exposure. Switch to PROOF (F4) for the audit black box. Switch to SYSTEM (F5) for availability.

---

## 10. Summary of Recommendations

### Must-Do (Phase 0)

1. **Add guidance strip to CASE view.** Translates data into structured recommendations. Bloomberg-equivalent of "what to think about."
2. **Split CASE into two tiers.** Default: thesis + basket + rejected. Toggle: account + ticket + policy + exposure + action. Reduces cognitive load.
3. **Add thesis health status.** HEALTHY/DRIFT/BREACH indicator on the THESIS band. Continuous evaluation, not static snapshot.
4. **Add case count to status bar.** /case N navigation. Multi-case support at minimum.
5. **Guided default state.** "Type a thesis to begin" message for empty state. Replaced by actual content once thesis is entered.

### Should-Do (Phase 0 if time permits)

6. **Multi-case sidebar.** Collapsible case list. Not full multi-window — just a way to switch cases without losing context.
7. **Hash expand/collapse.** Truncated hashes with click-to-expand. Terminal-appropriate density.
8. **Empty/unavailable states.** What does each panel look like when data is unavailable? "UNAVAILABLE — evidence required" not "blank."

### Don't Do (Phase 0)

- Charts (line, candlestick, area, bar) — this is a terminal, not a dashboard
- Heatmaps — decorative, not decision-critical
- Portfolio optimization suggestions — autonomous or semi-autonomous
- Live market data feeds — Phase 0 is fixture-based
- News/research panels — out of scope
- Multi-window full screen — keep it single-window, five panels
- Animations beyond focus transitions — no celebratory motion, no loading spinners (use status indicators instead)

---

## 11. The "Screams Terminal" Test

When an operator looks at the Phase 0 terminal, the question is: does this feel like Bloomberg, or does it feel like a web dashboard wearing dark mode?

The difference:
- **Bloomberg:** Every pixel is information. No padding for aesthetics. Commands, not clicks. Dense. Cold. Precise.
- **Web dashboard:** Cards with shadows. Rounded corners. Gradient backgrounds. Charts. Hover tooltips. Click to see more.

Tickoni Phase 0 hits the Bloomberg side when:
- The operator navigates with F-keys and the command bar (not clicking)
- Values are monospaced and tab-aligned (not left-aligned cards)
- Status uses color as a signal, not decoration (green rule, not green badge)
- Denials are explicit and unambiguous (red text, red rule, reason text)
- The audit trail is visible (not buried in a menu)
- There are no charts unless explicitly requested
- The interface feels cold, precise, and slightly intimidating

It fails the test when:
- Panels look like Bootstrap cards
- Hover reveals hidden information (tooltips, popovers)
- Colors signal "status" but also "brand"
- The operator needs to click to find what to do next
- Charts dominate the view

Phase 0's current design (per the roadmap docs) is ~85% there. The guidance strip, thesis health, and two-tier CASE view push it over the threshold.

---

## 12. Ticket Blinking — The "Terminal Alive" Signal

The TICKETS section on the CASE workbench MUST blink. This is non-negotiable. It is the single most important visual signal that the terminal is alive and updating. Without blinking, the terminal looks like a static dashboard or a web app — the Bloomberg test fails immediately.

### What Blinks

Every ticket line item in the BASKET column blinks on update:

```
  BASKET (4 eligible)
  ──────────────────
  NVDA    30.0%  $600.00  [BLINK]
  AAPL    25.0%  $500.00
  MSFT    25.0%  $500.00
  AVGO    20.0%  $400.00
```

The blink is a brief highlight of the row (background shift from dark surface to slightly lighter dark, e.g. from `#0a0a0a` to `#1a1a1a`). It is NOT a color change — no green, no red. It is a transient luminance pulse that lasts ~200ms, then fades back. This is how Bloomberg terminals indicate "this row just updated."

### Blink Trigger

The blink fires when the model backend returns a new response. This happens regardless of whether the data is real or stubbed:

- **FixtureBackend**: Every call to `.call()` returns the deterministic fixture response. The UI layer receives the response, diff's it against the previous state, and blinks any rows that changed (all of them on first load, only changed rows on subsequent updates).
- **FixtureBackend.initFromDir**: Loads from `fixture_model_response_gemma4.json`. The response contains `thesis_summary`, `recommended_tickers` (NVDA, AMD, AVGO, MSFT, AMZN, BOTZ, SOXX), token usage, and latency.
- **HttpBackend**: Calls an OpenAI-compatible llama.cpp server. When the server is unavailable, the fixture backend is the fallback.

### Model Update Loop

The terminal MUST implement a model update loop even in fixture mode. This serves two purposes:

1. **Visual**: Makes the terminal look alive (blinking tickets).
2. **Stress test**: Verifies the UI rendering pipeline can handle the update frequency that production data would impose.

```
Model Update Loop (Fixture Mode):
─────────────────────────────────
1. Load fixture data from fixture_model_response_gemma4.json
2. Parse recommended_tickers → build Basket from schema
3. Render tickets on CASE panel
4. Blink all ticket rows for ~200ms
5. Wait {N}ms (configurable, default 1000ms for demo)
6. Re-call fixture backend → get same deterministic response
7. Diff against previous state → identify changed rows
8. Re-render changed rows → blink them for ~200ms
9. GOTO step 5

Production Mode:
────────────────
Same loop, but:
- Model backend is HttpBackend (real llama.cpp / OpenAI-compatible API)
- Update interval adapts to data freshness: ~500ms-2000ms based on BUS status
- BUS DEGRADED → increase interval to ~5000ms
- BUS OK → use default interval
```

### Update Frequency Stress Parameters

The update loop is the primary mechanism for stress-testing the UI rendering pipeline in Phase 0. Here are the test configurations:

| Mode | Interval | Duration | Purpose |
|------|----------|----------|---------|
| Normal | 1000ms | 5 min | Baseline — one update per second, verify no visual artifacts |
| Elevated | 250ms | 2 min | Stress — 4 updates/sec, verify rendering doesn't drop frames |
| Peak | 100ms | 30 sec | Extreme — 10 updates/sec, verify UI doesn't freeze or lag |
| Sustained | 500ms | 10 min | Endurance — verify no memory leaks in QML rendering |

### Blink Configuration

```
Blink Settings:
  Duration:      200ms
  Fade:          ease-out (not linear)
  Color shift:   background #0a0a0a → #1a1a1a (200ms), back to #0a0a0a (200ms)
  Scope:         Changed rows only (not entire table)
  Coalesce:      Yes — if two updates arrive within 100ms, blink once
  Suppress:      No blinking when user is actively editing a row
```

### Stubbed Data Wiring

The wiring for stubbed data is explicit — no "if real data then blink" branching. The terminal treats stubbed and live data identically from the rendering pipeline's perspective:

```
ModelBackend.call() → ModelResponse
    ↓
TicketBuilder.build(response.recommended_tickers)
    ↓
StateDiff.diff(previous, current) → changed_rows[]
    ↓
UIRenderer.render(changed_rows) → blink(changed_rows, duration=200ms)
    ↓
Wait {interval}ms
    ↓
Loop
```

The fixture backend (`FixtureBackend` in `model/backend.zig`) returns deterministic responses with `recommended_tickers: ["NVDA", "AMD", "AVGO", "MSFT", "AMZN", "BOTZ", "SOXX"]`. The terminal converts this to ticket line items using `TradeTicket` from `schema/consumer_money/trade_ticket.zig`. Each row in the basket table blinks on every update cycle.

### Verification Criteria

The blinking requirement is verified when:

1. **Terminal starts** — all ticket rows blink once within 500ms of initial render
2. **After 3 update cycles** — rows that haven't changed (data stable) do NOT blink on cycles 2-3
3. **During rapid updates** (stress mode) — no dropped frames, no visual tearing, UI remains responsive
4. **User interaction** — when the user is editing a row or typing a command, blinking is suppressed for that row
5. **BUS DEGRADED** — blinking interval increases proportionally to data freshness degradation

This is the minimum viable "alive" signal. Without it, the terminal is a static screenshot — not a terminal.

---

## 13. High-Refresh-Rate Wiring — Qt Frame Budget and Update Architecture

ADR-03 and ADR-04 define how the Qt terminal connects to the Tickoni runtime at the systems level. The UX plan must align its visual design with these architectural constraints. The key insight: **runtime event rate is NOT UI render rate**.

### Frame Budget

ADR-04 states explicitly (line 126-129):
> At 60 frames per second, the GUI has approximately 16.7 ms per frame; at 120 frames per second, approximately 8.3 ms.

Every incoming update must share that budget with input handling, binding evaluation, model notifications, layout, scene-graph preparation, rendering, accessibility, and window management.

### Update Amplification — The Real Risk

ADR-04 (line 147):
> Thousands of independently delivered cell updates can therefore consume much more CPU than their payload size suggests. The primary UI risk is update amplification, not only wire latency.

The amplification chain (ADR-04, lines 132-144):
```
wire or bus message
  -> decode and validation
  -> projection-store mutation
  -> model patch
  -> dataChanged/row notification
  -> QML role reads
  -> binding re-evaluation
  -> delegate changes
  -> layout and render work
```

### Preferred vs Rejected Update Shape

ADR-04 (lines 1405-1422) defines the two update shapes:

**Preferred:**
```
many runtime updates
  -> keyed latest-value coalescing
  -> compact sorted ModelPatch batch
  -> minimal dataChanged ranges and roles
  -> one bounded GUI drain
```

**Rejected:**
```
one runtime tick
  -> one queued Qt event
  -> one property write
  -> one binding cascade
  -> one delegate update
```

### The Architecture Must Not Hard-Code One Global Refresh Interval

ADR-04 (line 1429):
> The architecture must not hard-code one global refresh interval. A quote watchlist, order book, audit timeline, policy state, and health metric have different semantics.

Correctness state is event-driven and ordered. Latest-value presentation is coalesced and cadence-controlled.

### Data Flow Architecture (ADR-04, lines 177-211)

```
local native terminal:

tk_ui
  -> shared-memory command channel
  -> tk_api
  -> runtime tiles

runtime state
  -> tk_api
  -> shared-memory event/value channels
  -> tk_ui
```

The bus thread (shared-memory polling) → workers (parsing, projection, patch construction) → GUI model-patch queue → GUI thread (bounded drain) → QML render.

Key constraint (ADR-04, line 157-159):
> The runtime may process and retain every required event. The GUI receives lossless correctness events and coalesced latest-value projections at a bounded, human-useful cadence.

### Channel Types (ADR-04, lines 1355-1362)

| Channel | Delivery Semantics |
|---|---|
| `ui_cmd` | ordered, preserve, no coalescing |
| `ui_rsp` | ordered, preserve, reconcile on failure |
| `ui_evt` | ordered, preserve, resync on gap |
| `ui_lval` | coalesce by key, overwrite-capable |
| `ui_bulk` | bound outstanding payload ownership |
| `ui_diag` | may sample or replace older diagnostics |
| GUI patch queue | coalesce latest-value patches; preserve correctness |

### Performance Gates (ADR-04, lines 1975-1982, 2043, 2064)

ADR-04 requires these as minimum evidence before acceptance:

- A 10,000-row table remains interactive under representative batched updates
- Delegate reuse does not leak row-local state
- One-cell updates do not reset the table
- Correctness events remain ordered during burst load
- Latest-value updates coalesce by key and do not starve correctness events
- Saturating each channel produces its documented fail-closed or coalescing behavior
- **A market-data burst does not produce one queued Qt event or one QML update per runtime tick**
- The internal bus has materially lower CPU, allocation, and latency cost than the localhost HTTP/WebSocket baseline

### GUI Drain Budget

ADR-04 (lines 1282-1290):
```
Properties:
- one drain operation has a count and time budget;
- applied only on the GUI thread;
- patch size is limited;
- remaining work is deferred to a later event-loop turn;
- patches retain source revision and process generation;
- an obsolete-generation patch is discarded before model mutation.
```

### Hybrid Poll/Park Bus Strategy (ADR-04, lines 1498-1508)

ADR-04 rejects busy-poll for `tk_ui` (line 1499-1502):
> A conventional Firedancer tile may own a CPU core and busy-poll continuously. The desktop `tk_ui` tile must coexist with a window-system event loop, Qt rendering, laptop power management, and ordinary workstation workloads.

Default strategy:
1. Poll aggressively for a bounded period after recent activity
2. Drain a bounded batch
3. Park when idle
4. Wake through a platform primitive when producers publish
5. Return to polling during bursts

### What This Means for the UX Plan

1. **Blinking tickets are architecturally required, not cosmetic.** They are the visual manifestation of the bounded GUI drain cycle. Without the model update loop (Section 12), the terminal has no GUI drain activity and cannot validate the frame budget. The blink is the observable signal that the drain is happening.

2. **The 200ms blink pulse in Section 12 must fit within the frame budget.** A 200ms animation spans ~12 frames at 60fps. Each frame has 16.7ms. The background color shift from `#0a0a0a` to `#1a1a1a` is a QML property change evaluated on the GUI thread — it must complete within that budget. Qt Quick handles this natively via its property animation system, which batches into the scene-graph update cycle.

3. **Stress test modes (100ms, 250ms, 1000ms) map to different GUI drain cadences.** At 100ms intervals (10 updates/sec), the drain budget must accommodate 10 bounded batch applications per second. The ADR requires: "one drain operation has a count and time budget; remaining work is deferred to a later event-loop turn." If the drain cannot keep up, work is deferred — the terminal remains responsive but updates may lag. This is documented behavior, not a failure.

4. **No hard-coded global refresh.** The blink cadence for fixture mode (Section 12) is a development/testing cadence, not a production cadence. In production, the update rate follows the channel-specific semantics in the table above — `ui_lval` coalesces by key, `ui_evt` preserves and resyncs, `ui_cmd` preserves and orders. The UX design must not assume a uniform update rate across all data.

5. **The "BUS OK / BUS DEGRADED" indicator in Section 9 (status bar) maps directly to the bus strategy.** When BUS is DEGRADED, the hybrid poll strategy switches to longer park periods, reducing update frequency. The 5000ms interval for degraded state (Section 12) is a UX consequence of this architecture — not a hard-coded value, but a reflection of reduced bus activity.

6. **QML must remain declarative and presentation-only.** Per ADR-04 (lines 1742-1747), QML signal handlers may only: update local visual state, call one typed view-model method, or move focus. The model update loop in Section 12 must be implemented in C++ (`tk_ui` presentation models), not in QML bindings or delegates.

7. **Coalescing is mandatory.** ADR-04 (line 2064): "A market-data burst does not produce one queued Qt event or one QML update per runtime tick." The terminal's blinking behavior must reflect this: if 100 runtime events arrive for the same basket in one burst, only ONE GUI drain happens, and the blink fires once — not 100 times.

---

*End of Phase 0 UX Plan.*
