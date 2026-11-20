# Broker Bridge Architecture (`tkbrokr`)

## Pattern

`tkbrokr` follows the same bridge pattern as `tkmodl`:

- **`tkmodl`** is the model access gateway. It accepts a `TkModlRequest`, validates it against allowlist/budget/context/retry policies, then dispatches to a `model.Backend` which can be any implementation:
  - `FixtureBackend` — canned responses for tests
  - `ReplayBackend` — captured response substitution for replay
  - `HttpBackend` — live HTTP calls to llama.cpp or cloud LLM servers

- **`tkbrokr`** is the broker access bridge. It accepts normalized broker requests (`place_order`, `cancel_order`, `query_position`, `get_quotes`), validates them against policy, then dispatches to a `BrokerBackend` which can be any implementation:
  - `DefaultBackend` — always returns filled/OK for dev/test
  - `ReplayBackend` — captured response substitution for replay
  - `IBKRBackend` — Interactive Brokers API adapter
  - `SchwabBackend` — Charles Schwab API adapter
  - `SnapTradeBackend` — SnapTrade aggregator adapter
  - ... any broker that needs to be supported

## Tile ID

| Tile | Runtime ID | Instance count |
|------|-----------|----------------|
| `tkbrokr` | `tkbrokr0` | 1 per broker kind (like `tkmodl` instances) |

Each broker kind (IBKR, Schwab, etc.) gets its own instance of `tkbrokr`, configured with the appropriate `BrokerBackend`. The user only has accounts for the brokers they've connected, so only those instances are instantiated.

## Vtable Interface (`BrokerBackend`)

Same type-erased vtable pattern as `model.Backend` in `src/tickoni/tiles/model/backend.zig`:

```zig
pub const BrokerBackend = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        call: *const fn (ptr: *anyopaque, req: BrokerRequest) anyerror!BrokerResult,
        callById: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, substitution_id: u64) anyerror!BrokerResult,
        effect_free: bool,
    };

    pub fn from(comptime T: type, comptime effect_free: bool, self: *T) BrokerBackend { ... }
    pub fn call(self: BrokerBackend, req: BrokerRequest) anyerror!BrokerResult { ... }
    pub fn callById(self: BrokerBackend, allocator: std.mem.Allocator, substitution_id: u64) anyerror!BrokerResult { ... }
    pub fn isEffectFree(self: BrokerBackend) bool { ... }
};
```

## Broker Request/Result Types

```zig
pub const BrokerOperation = enum {
    place_order,
    cancel_order,
    query_position,
    get_quotes,
    query_cash_balance,
    query_open_orders,
};

pub const BrokerRequest = struct {
    operation: BrokerOperation,
    account_id: u32,
    // Per-operation fields:
    /// place_order: ticker, side, quantity, limit_price, order_type
    /// cancel_order: order_id
    /// query_position: ticker
    /// get_quotes: [max_tickers]ticker_buf, ticker_count
    // ...
};

pub const BrokerResult = union(BrokerOperation) {
    place_order: FillResult,
    cancel_order: CancelResult,
    query_position: PositionSnapshot,
    get_quotes: QuoteSnapshot,
    query_cash_balance: CashBalance,
    query_open_orders: OpenOrderList,
};
```

## Broker Kind Configuration

Each `tkbrokr` instance is configured via a JSON config file alongside its topology spec (like `tkmodl.<kind_id>.config`):

```json
{
    "kind_id": 0,
    "broker": "ibkr",
    "backend": {
        "type": "http",
        "endpoint": "https://api.ibkr.com/v1",
        "auth_method": "oauth2",
        "timeout_ms": 30000,
        "retry_limit": 3
    }
}
```

For dev/test, the config specifies a `fixture` or `replay` backend:

```json
{
    "kind_id": 0,
    "broker": "mock",
    "backend": {
        "type": "fixture",
        "fixture_dir": "src/tickoni/test/fixtures/investment/scenarios"
    }
}
```

## Implementation Checklist

1. Define `BrokerOperation` enum, `BrokerRequest`, `BrokerResult` types in a new schema module.
2. Define `BrokerBackend` vtable interface in a new tile module `src/tickoni/tiles/brokr/mod.zig`.
3. Implement `DefaultBackend` (always returns filled) in the module.
4. Implement `FixtureBackend` and `ReplayBackend` (same pattern as `model` module).
5. Register `tkbrokr` in tile registry (process mode stub, fd_stem when ready).
6. Wire `tkbrokr` into the investment workflow topology (consumer of `tkadpt`, producer to `tkaudt`).
7. Add `tkbrokr` configuration schema to `tile_main_config.zig` (like `tkmodl`).
8. Implement broker adapter stubs: `IBKRBackend`, `SchwabBackend`, `SnapTradeBackend`.

## Relation to Existing Tiles

| Tile | Role | Relationship |
|------|------|-------------|
| `tkmodl` | Model bridge | Same vtable pattern, different domain |
| `tktool` | Tool normalizer | Normalizes agent tool requests → `tkadpt` requests |
| `tkadpt` | Adapter | Routes `tktool` requests → `tkbrokr` for broker calls |
| `tkbrokr` | Broker bridge | Dispatches normalized broker requests to per-broker backends |
| `tkexec` | Approved execution | Calls `tkbrokr` via `tkadpt` for actual order placement |

The call chain for execution:
`tkexec` → `tktool` → `tkadpt` → `tkbrokr` → `{IBKRBackend | SchwabBackend | MockBackend}`
