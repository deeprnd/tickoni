# UC-04: Trade Execution — Buy Confirmation

## Description

The user reviews the trade proposal from UC-03 and agrees. The event enters through the API tile and flows through:

1. **Re-validation** — the execution path re-validates the policy decision (can't rely solely on the earlier check; the policy window may have shifted).
2. **Execution call** — routed to a broker tile stub (always returns OK for dev/test).
3. **Portfolio update** — the trade is recorded, holdings and cash are updated.
4. **Audit** — the execution is recorded in the audit trail.
5. **Transaction history** — stored in a local ledger (execution ledger).

This is the first path where money would actually move (in production). In the current stubbed environment, the broker returns a synthetic filled order.

## Flow

```mermaid
sequence
    participant Term as Terminal (UI)
    participant API as tkapi (CaseOps API)
    participant Poly as tkpoly (Policy — re-validate)
    participant Exec as tkexec (Approved Execution)
    participant Brokr as tkbrok (Broker Bridge)
    participant Port as tkport (Portfolio — update)
    participant Audt as tkaudt (Audit)
    participant Ledg as tkledg (Execution Ledger)

    Term->>API: POST /trade/execute {ticket_id: "ticket_abc", proposal_hash: "hash_xyz"}
    API->>Poly: POLICY_CHECK re-validation (same proposal, refreshed data)
    Poly-->>API: allow (policy still in scope)
    API->>Exec: tkexec — approved_execution.execute (proposal_hash, signed envelope)
    Exec->>Brokr: broker.place_order (NVDA, buy, 100 shares)
    Brokr-->>Exec: order_filled (fill_id, fill_price, fill_time)
    Exec->>Port: portfolio.update (deduct cash, add NVDA holding)
    Port-->>Exec: portfolio updated
    Exec->>Ledg: ledger_entry (transfer: cash out, NVDA in)
    Ledg-->>Exec: ledger entry committed
    Exec->>Audt: AUDIT trade_execute (proposal_hash, fill details, ledger entry, timestamp)
    Audt-->>Exec: audit record committed
    Exec-->>API: execution result (filled, fill_price, ledger entry hash)
    API-->>Term: execution confirmation (filled at $198.50, new position, ledger entry)
```

## Tile Inventory

| Tile | Runtime ID | Responsibility | Status |
|------|-----------|----------------|--------|
| `tkapi` | `tkapi0` | Receives execution request, routes to `tkexec` | **MISSING** |
| `tkexec` | `tkexec0` | Approved execution tile — privileged mutation path, enforces signed action envelope, calls broker, updates portfolio, posts ledger entry | **MISSING** — declared in `tile_ids.zig` but NOT in registry, NOT in topology, NOT implemented |
| `tkbrok` | `tkbrok` | Broker bridge tile — routes broker requests (place, cancel, query) to per-account broker implementations. Each broker (IBKR, Schwab, SnapTrade, …) is a pluggable backend via vtable interface, same pattern as `tkmodl`. For dev/test the default backend always returns OK. Only brokers the user has accounts with are instantiated. | **MISSING** — tile ID registered in `tile_ids.zig` but not in registry, not in topology, not implemented |
| `tkport` | `tkport0` | Portfolio tile — update holdings and cash after execution | **MISSING** — see UC-03 |
| `tkledg` | `tkledg0` | Execution ledger tile — stores balances, transfers, fills, accounting entries | **MISSING** — TigerBeetle is the authoritative finance database per AGENTS.md; no tile ID registered yet |
| `tkpoly` | `tkpoly` | Re-validation policy check | **PARTIALLY** — needs execution-specific policy path |
| `tkaudt` | `tkaudt` | Audit tile — records `trade_execute` boundary event | **PARTIALLY** — needs `trade_execute` record type |
| `tkmetr` | `metric` | Metrics tile | **EXISTING** |
| `tkdiag` | `tkdiag` | Diagnostics | **EXISTING** |

### What exists today (supporting)

- **`mock_broker_market_server`** (`src/tickoni/test/mocks/mock_broker_market_server.zig`) — serves `/paper-orders` returning `paper_order_id` and status `filled`.
- **`mock_adapter`** — canned `paper_order` response.
- **`runInvestmentAgent`** — produces `PaperExecutionResult` when policy allows.
- **`trade_ticket.PaperExecutionResult`** — result type from paper execution.
- **`portfolio.BrokerageAccount`** — schema for holding/cash state.

### What's needed

1. Register `tkbrok` in tile registry — broker bridge tile. Follows the `tkmodl` pattern: a type-erased vtable interface (`BrokerBackend`) that dispatches to pluggable broker implementations (IBKR, Schwab, SnapTrade, etc.). Only the brokers the user has accounts with are instantiated per instance. For dev/test, the default backend always returns filled.
2. Implement `tkbrok` tile process: `broker.place_order` normalizes the request, looks up the broker implementation from the account's broker config, calls the broker's `call()` method, returns the result. Each broker kind is a separate instance (like `tkmodl` instances).
3. Implement the vtable interface for broker backends: `BrokerBackend` with `call()` accepting normalized broker requests (place_order, cancel_order, query_position, get_quotes) and returning results. Each broker (IBKR, Schwab, SnapTrade) implements `call()`.
4. Register `tkexec` in tile registry — approved execution tile with privileged mutation path.
5. Implement `tkexec` tile process: verifies signed action envelope, calls `tkbrok` via adapter, updates portfolio, posts ledger entry, records audit trail.
6. Register `tkledg` tile ID — execution ledger tile (stores transfers, fills, balances). TigerBeetle integration for production; local in-memory store for dev/test.
7. Implement portfolio mutation: deduct cash, add/update holding, update open-order count, update daily/monthly notional used.
8. Implement ledger entry: transfer record with before/after state for audit read-back reconciliation.
9. Add `trade_execute` record type to `tkaudt` — includes proposal hash, fill details, ledger entry hash, signed envelope verification.
10. Wire `tkexec`, `tkbrok`, `tkledg` into a new execution topology.
11. Implement `tkapi` handler for `/trade/execute` (see UC-01).

### System test approach

- Launch the execution topology with `tkapi`, `tkexec`, `tkbrok`, `tkledg`, `tkport`, `tkaudt`, `metric`, `tkdiag`.
- Use `mock_adapter` with portfolio snapshot and paper_order filled response.
- Use `tkbrok` default backend (always returns filled).
- Send `/trade/execute?ticket_id=ticket_abc&proposal_hash=hash_xyz` through `tkapi`.
- Verify: `tkexec` verified the signed envelope; `tkbrok` returned filled via default backend; `tkport` updated holdings and cash; `tkledg` posted the transfer entry; `tkaudt` recorded `trade_execute` with fill details and ledger hash.
- Verify replay: replace `tkbrok` and `tkledg` with capsule substitutes, verify identical execution result.
- Verify deny path: send execution with invalid/expired proposal hash — `tkexec` should deny before calling broker.
