# Unified Flow Diagram — All 11 Use Cases

## What tkdisp is

tkdisp is the **enterprise service bus (ESB)** — it sits between the deterministic event pipeline and the agent/data layer. It is the central routing hub.

**What it does (routing, not transformation):**
- Dispatch: routes pipeline events to PATH A (agent), PATH B (data read), or PATH C (sink)
- Collect: receives results back from whatever it dispatched to
- Validate: checks results match dispatched requests — request_id tracking, one-result-per-request invariant
- Store: passes validated results to the ring buffer for tk_api to retrieve

**What it does NOT do:**
- Does not enforce policy — that's tkpoly
- Does not transform/normalize data — that's tknorm (inbound) and tk_api (outbound)
- Does not format responses for the terminal — that's tk_api
- Does not store business state — ring buffer is transient; case/audit store holds persistent state

**Routing decision:** After tkcase passes an event to tkdisp, tkdisp decides where to route:
- If the use case needs an agent run → PATH A (dispatch to tkagnt)
- If the use case needs data reads → PATH B (route to tktool/tkadpt/tkport)
- If the use case is pure policy/audit → PATH C (sink, no external routing)

**Request-response validation:** tkdisp tracks outstanding requests. When it dispatches a request, it records the request ID. Results MUST include the request ID they're responding to. tkdisp validates:
1. "Did I dispatch this request?" — rejects unknown request IDs
2. "Has a result already been stored for this request?" — rejects duplicates
3. Only validated results are stored in the ring buffer

This is the ESB's validation role: it doesn't understand content, it validates that results match dispatched requests. A rogue or compromised tkagnt cannot inject arbitrary results — tkdisp enforces the one-request-one-result invariant. tk_api trusts the ring buffer because every result has been validated against a dispatched request.

## The Unified Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  OPERATOR UI (generic client terminal)                                      │
│                                                                             │
│  Sends commands via tk_api shared-memory channel.                           │
│  Receives responses back through the same channel.                          │
└──────────────────────────┬──────────────────────────────────────────────────┘
                           │ tk_api (shared-memory command channel)
                           │ All operator/agent commands enter here
                           v
┌─────────────────────────────────────────────────────────────────────────────┐
│  tk_api entry point                                                         │
│  Validates shape, routes to pipeline                                        │
└──────────────────────────┬──────────────────────────────────────────────────┘
                           │
                           v
┌─────────────────────────────────────────────────────────────────────────────┐
│  THE DETERMINISTIC EVENT PIPELINE (same for ALL use cases)                  │
│                                                                             │
│  ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐        │
│  │ tkings  │──>│ tknorm  │──>│ tkdedu  │──>│ tkcase  │──>│ tkpoly  │──>│    │
│  │ (ingest)│   │(normal) │   │ (dedup) │   │ (case)  │   │(policy) │   │    │
│  └─────────┘   └─────────┘   └─────────┘   └─────────┘   └─────────┘        │
│                                                                             │
│  tkings: validate framing, assign source offsets, backpressure              │
│  tknorm: canonicalize into canonical event schema                           │
│  tkdedu: remove duplicates by idempotency key + content hash                │
│  tkcase: create deterministic case record (shared scope)                    │
│  tkpoly: check capability envelope, return allow/deny/require_approval      │
│                                                                             │
│  All events also go to tkaudt (audit) — append-only, hash-chained           │
│  ┌─────────┐   ┌─────────┐                                                  │
│  │ tkpoly  │──>│ tkaudt  │                                                  │
│  └─────────┘   │ (audit) │                                                  │
│                └─────────┘                                                  │
└──────────────────────────┬──────────────────────────────────────────────────┘
                           │ tkcase output (pipeline events)
                           │
                           v
┌─────────────────────────────────────────────────────────────────────────────┐
│  tkdisp (enterprise service bus — central routing hub) — THREE PATHS, ONE TILE ID         │
│                                                                             │
│  tkcase ──> tkdisp ──┐                      │                               │
│                       │ tkdisp routing       │                               │
│                       │ decision:            │                               │
│                       │                      │                               │
│              ┌────────┴────────┐             │                               │
│              │                 │             │                               │
│              v                 v             v                               │
│   ┌──────────────────┐ ┌────────────┐ ┌──────────────┐                      │
│   │ PATH A: Agent Run│ │ PATH B:    │ │ PATH C:      │                      │
│   │ (UC-02 only)     │ │ Data Read  │ │ Pure Sink    │                      │
│   │                  │ │ (UC-06,    │ │ (UC-01,03-05,│                      │
│   │ tkdisp ──> tkagnt│ │  UC-07,    │ │  UC-08-11)   │                      │
│   │                  │ │  UC-09,    │ │              │                      │
│   │ If agent needs   │ │  UC-10)    │ │              │                      │
│   │ external access: │ │            │ │              │                      │
│   │ tkagnt ──> tkdisp│ │ tkdisp ──> │ │              │                      │
│   │    ──> tkpoly ──>│ │ tkpoly ──>│ │ tkdisp ──>   │                      │
│   │                  │ │ tktool     │ │ result ring  │                      │
│   │ tkmodl           │ │ tkadpt     │ │              │                      │
│   │ (model, fees,    │ │ tkport     │ │              │                      │
│   │  scope, budget)  │ │            │ │              │                      │
│   │                  │ │ (policy    │ │              │                      │
│   │ tktool           │ │  checks    │ │              │                      │
│   │ (broker, access, │ │  apply)    │ │              │                      │
│   │  permissions)    │ │            │ │              │                      │
│   │                  │ │            │ │              │                      │
│   │ tkadpt           │ │            │ │              │                      │
│   │ (adapter,        │ │            │ │              │                      │
│   │  signed/stub)    │ │            │ │              │                      │
│   │                  │ │            │ │              │                      │
│   │ tkport           │ │            │ │              │                      │
│   │ (portfolio,      │ │            │ │              │                      │
│   │  exposure)       │ │            │ │              │                      │
│   └────────┬─────────┘ └────────────┘ └──────────────┘                      │
│            │                                                                 │
│            └─────────────────────────────────────────────────────┐           │
│                                                                │           │
│                          tkdisp result ring                    │           │
│                          (PATH A results stored here)          │           │
│                          [validated against dispatched request] │           │
│                          [one request → one result]            │           │
│                          [rogue results rejected]              │           │
└────────────────────────────────────────────────────────────────┴───────────┘
                           │ tkdisp result ring
                           │ tk_api retrieves results, formats for terminal
                           v
┌─────────────────────────────────────────────────────────────────────────────┐
│  tk_api retrieves from result ring (or case/audit store) and formats        │
│  responses for the terminal                                                 │
│                                                                             │
│  (tknorm normalizes inbound events; tk_api formats outbound results)        │
│  This is symmetric: canonicalize in, format out.                            │
└──────────────────────────┬──────────────────────────────────────────────────┘
                           │
                           v
┌─────────────────────────────────────────────────────────────────────────────┐
│  OPERATOR UI (generic client terminal) receives formatted response          │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Use Case Mapping

```
┌────────────────────────────────────────────────────────────────────────────────┐
│ Use Case                          │ tkdisp path  │ Agents needed? │
├────────────────────────────────────────────────────────────────────────────────┤
│ UC-01: Terminal Dashboard         │ C (sink)     │ No             │
│     (read data, no model)         │              │                │
├────────────────────────────────────────────────────────────────────────────────┤
│ UC-02: Valuation Analysis         │ A (agent)    │ Yes (tkmodl)   │
│     (analyze ticker, get model)   │              │                │
├────────────────────────────────────────────────────────────────────────────────┤
│ UC-03: Trade Proposal Buy         │ C (sink)     │ No             │
│     (propose order, policy check) │              │                │
├────────────────────────────────────────────────────────────────────────────────┤
│ UC-04: Trade Execution Buy        │ C (sink)     │ No             │
│     (execute approved order)      │              │                │
├────────────────────────────────────────────────────────────────────────────────┤
│ UC-05: Trade Proposal Sell        │ C (sink)     │ No             │
│     (propose sell, policy check)  │              │                │
├────────────────────────────────────────────────────────────────────────────────┤
│ UC-06: Ticker Detailed Data       │ B (data read)│ No             │
│     (deep market data read)       │              │                │
├────────────────────────────────────────────────────────────────────────────────┤
│ UC-07: Portfolio Exposure         │ B (data read)│ No             │
│     (portfolio risk snapshot)     │              │                │
├────────────────────────────────────────────────────────────────────────────────┤
│ UC-08: Portfolio Rebalancing      │ B (data read)│ No             │
│     (rebalance, no execution)     │              │                │
├────────────────────────────────────────────────────────────────────────────────┤
│ UC-09: Trade Retrospective        │ B (data read)│ No             │
│     (post-trade analysis read)    │              │                │
├────────────────────────────────────────────────────────────────────────────────┤
│ UC-10: Portfolio Simulator        │ B (data read)│ No             │
│     (scenario simulation)         │              │                │
├────────────────────────────────────────────────────────────────────────────────┤
│ UC-11: Agent Decision Audit       │ C (sink)     │ No             │
│     (audit trail read)            │              │                │
└────────────────────────────────────────────────────────────────────────────────┘
```

## The Three Paths

**PATH A — Agent Run (UC-02 only):**
```
Terminal → tk_api → tkings → tknorm → tkdedu → tkcase → tkpoly → tkdisp
                                                tkdisp records request_id
tkdisp → tkagnt (with request_id)
tkagnt → tkdisp (with result + request_id)
tkdisp validates: request_id exists + not already completed
    → tkpoly (if agent needs external access) → tkmodl/tktool/tkadpt
Result: validated → tkdisp result ring → tk_api retrieves, formats, sends to terminal
```
tkdisp routes to tkagnt. If tkagnt needs external access, it sends the request back to tkdisp, which routes to tkpoly for policy checks (model fees, tool permissions, adapter scopes), then forwards to the service. tkdisp validates each result against its outstanding-requests table before storing it.

**PATH B — Data Read (UC-06, UC-07, UC-08, UC-09, UC-10):**
```
tkdisp ──> tkpoly (policy check) ──> tktool/tkadpt/tkport (data read)
Result: stored in tkdisp result ring → tk_api retrieves, formats, sends to terminal
```
No agent run needed. tkdisp routes to tktool/tkadpt/tkport for data reads, all gated by tkpoly for policy checks. Results stored in ring buffer.

**PATH C — Pure Sink (UC-01, UC-03-05, UC-11):**
```
tkdisp ──> result ring (passive)
Result: tk_api retrieves from case/audit store, formats, sends to terminal
```
Policy decision and audit are sufficient. No external routing needed. tkdisp stores results passively.

## Result Flow Architecture

```
Inbound (request):
  Terminal → tk_api → tkings → tknorm → tkdedu → tkcase → tkpoly → tkaudt
                    (format)   (ingest) (normalize) (dedup) (case) (policy) (audit)

Outbound (response):
  tkdisp result ring / case-audit store → tk_api → Terminal
  (validated results)                  (format)  (formatted)

Request-response contract (PATH A only):
  tkdisp dispatches request → records request_id
  tkagnt returns result → tkdisp validates request_id → stores in ring
  [rogue results with unknown request_id are rejected]

Symmetry: tknorm normalizes inbound events; tk_api formats outbound results.
tkdisp dispatches and validates — it does not format or transform data.
```

## Why Only UC-02 Needs Agent Run

Most use cases are **read or propose-only** — they need data from the pipeline and policy decisions. The terminal sends a command, the pipeline processes it, policy checks it, audit records it, and tkdisp stores results. tk_api retrieves and formats. The terminal gets back the response.

**UC-02 (Valuation Analysis)** is the exception — it requires model analysis (base/bull/bear scenarios, graphs, verdict). So tkdisp dispatches an agent run. If the agent needs model access, tkdisp gates it through tkpoly (fees, token budget, scope) before forwarding to tkmodl.

## The 3 Layers

```
Layer 1: Command Entry (ALL use cases)
  Terminal ──tk_api──> tkings

Layer 2: Deterministic Pipeline (ALL use cases)
  tkings ──> tknorm ──> tkdedu ──> tkcase ──> tkpoly ──> tkaudt
  (ingest)  (normal)   (dedup)    (case)    (policy)  (audit)

Layer 3: tkdisp ESB routing + Result Retrieval (ALL use cases, different paths)
  tkdisp ──> PATH A: tkagnt ──> tkdisp ──> tkpoly ──> (tkmodl | tktool | tkadpt | tkport)
       or ──> PATH B: tkpoly ──> (tktool | tkadpt | tkport)
       or ──> PATH C: result ring (passive)
  tkdisp ring / case-audit store ──> tk_api ──> Terminal
```

## Key Takeaways

1. **tk_api** is the single entry point — all commands go through it, and it formats all responses
2. **The pipeline** (tkings → tknorm → tkdedu → tkcase → tkpoly → tkaudt) runs for ALL use cases
3. **tkdisp** is the ESB (enterprise service bus) — central routing hub that dispatches pipeline events to the right path, collects responses, validates results, and stores them in the ring buffer — does not enforce policy, transform data, or format responses
4. **PATH A** (agent run) only runs for UC-02 — agent logic with gated external access
5. **PATH B** (data read) runs for UC-06, 07, 08, 09, 10 — tkdisp routes to tktool/tkadpt/tkport, tkpoly enforces policy checks
6. **PATH C** (sink) runs for UC-01, 03-05, 11 — pure policy/audit, no external routing needed
7. **Agents are fully isolated** — tkagnt only communicates with tkdisp, which enforces policy (scope, fees, budgets, permissions) before granting access to tkmodl, tktool, or tkadpt
8. **tk_api handles result formatting** — it retrieves from tkdisp's result ring or the case/audit store and formats responses for the terminal, symmetric to tknorm which normalizes inbound events
9. **The terminal only sees tk_api** — it doesn't know or care which pipeline tiles processed its command
10. **Request-response contract**: tkdisp enforces one-request-one-result. Results must include a request_id that tkdisp validates against its outstanding-requests table. Rogue or compromised tkagnt cannot inject arbitrary results — tkdisp rejects unknown request IDs and duplicates
