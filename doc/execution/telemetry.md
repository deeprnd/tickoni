# Telemetry

This document focuses on Tickoni runtime metrics, diagnostics, and telemetry
semantics.

The current Tickoni implementation exposes telemetry as in-memory snapshots and
supervisor output. It does not yet expose a Tickoni-specific scrape endpoint.
Firedancer's existing metrics substrate remains under `src/disco/metrics` and
should be reused where practical when `tkmetr` becomes a production metrics
tile.

## Current Endpoints

There are no Tickoni-specific Prometheus endpoints in the current Phase 0
supervisor.

## Retail Runtime Privacy Defaults

V2.21 retail runtime support is local-first:

- installer telemetry is disabled by default
- `tickoni --version`, `tickoni doctor`, and the deterministic demo flows do not
  require outbound telemetry
- evidence generation is local/offline by default
- a later story may add opt-in diagnostics or managed export, but V2.21 does
  not claim that remote telemetry is part of the retail support path

The retail trust surface is therefore inspectable without network-side
collection, background exporters, or hosted analytics dependencies.

Current manual telemetry output is available through:

```bash
zig build run -- start
```

The command prints a final metric line and diagnostic line after the Phase 0
pipeline completes.

## Implementation Locations

Tickoni telemetry lives in:

- `src/tickoni/tiles/payment_pipeline.zig`
- `src/app/tickoni/supervisor.zig`
- `src/app/tickoni/main.zig`

Firedancer metrics infrastructure lives in:

- `src/disco/metrics/`

Architecture and expected tile ownership are documented in:

- `doc/architecture.md`
- `doc/knowledge/tile-topology.md`
- `doc/execution/tile-delivery-status.md`

## Phase 0 Metrics

`PaymentPipelineState.snapshotMetrics()` returns:

| Field | Type | Meaning |
| --- | --- | --- |
| `produced` | counter | Synthetic payment events produced by `tkings` |
| `normalized` | counter | Events accepted by `tknorm` after framing validation |
| `invalid` | counter | Malformed or invalid payment events rejected by `tknorm` |
| `duplicates` | counter | Duplicate idempotency-key and event-hash pairs detected by `tkdedu` |
| `allowed` | counter | Policy allow decisions from `tkpoly` |
| `denied` | counter | Policy deny decisions from `tkpoly` |
| `audited` | counter | Audit records appended by `tkaudt` |
| `backpressure_waits` | counter | Total producer waits across bounded queues |
| `max_queue_depth` | gauge | Highest queue depth observed across Phase 0 links |
| `max_latency_hops` | gauge | Largest event hop count observed at audit append |

These are low-cardinality runtime signals. They are suitable for future
Prometheus counters and gauges.

## Phase 0 Diagnostics

`PaymentPipelineState.snapshotDiag()` returns:

| Field | Type | Meaning |
| --- | --- | --- |
| `crashed_tile` | gauge | Tile index marked crashed, or `-1` when no crash was recorded |
| `sandbox_failures` | counter | Simulated sandbox failures recorded by the runtime |
| `audit_records` | counter | Current audit record count |
| `replay_checked` | boolean gauge | Whether replay comparison completed |
| `replay_match` | boolean gauge | Whether replay matched recorded audit output |

The supervisor prints these diagnostics at the end of `zig build run -- start`.

## Alerting Policy

No Tickoni alert rules are committed yet.

Future alerting should use a bounded severity taxonomy:

| Severity | Meaning |
| --- | --- |
| `critical` | Active outage, audit failure, replay divergence, or data-path failure needing immediate action |
| `warning` | Degradation, sustained backpressure, repeated denials, or elevated failures needing operator action soon |
| `info` | Non-paging operational signal for awareness, correlation, or audit trails |

Phase 0 signals that should become alert sources once a metrics endpoint and
rule files exist:

- tile crash or sandbox failure
- replay mismatch
- audit append failure
- sustained backpressure waits
- sustained invalid-event rate
- unexpected policy deny rate
- queue depth saturation

## Retail Runtime Privacy Defaults (V2.21 / V2.22)

Both V2.21 (macOS) and V2.22 (Windows) retail runtime support share the same
privacy defaults:

- **Telemetry is disabled by default** on all retail tiers
- `tickoni --version`, `tickoni doctor`, and the deterministic demo flows do not
  require outbound telemetry
- Evidence generation is local/offline by default
- A later story may add opt-in diagnostics or managed export, but V2.21 and
  V2.22 do not claim that remote telemetry is part of the retail support path
- Installers do not request broker, payment, crypto, approved execution ledger,
  or live model-provider credentials
- The retail trust surface is inspectable without network-side collection,
  background exporters, or hosted analytics dependencies

## Label Policy

Telemetry in this repo must stay low-cardinality and alert-friendly.

Allowed future label shapes:

- `tile`
- `link`
- `decision`
- `failure_kind`
- `stage`
- `capability`
- `environment`

Do not put high-cardinality identifiers into metric labels. These belong in
audit records, logs, trace attributes, or evidence stores instead.

Forbidden examples:

- source event IDs
- payment IDs
- account IDs
- case IDs
- wallet or processor addresses
- prompt text
- raw model output
- raw error messages
- stack traces

## Generated Metrics

If Firedancer metrics definitions under `src/disco/metrics/metrics.xml` change,
regenerate metrics with:

```bash
make -C src/disco/metrics metrics
```

This regenerates files under:

- `src/disco/metrics/generated/`
- `book/api/metrics-generated.md`

Generated outputs are checked into the repository.

## Related Docs

- [Observability](observability.md)
- [Architecture](../knowledge/architecture.md)
- [Build System](../build-system.md)
