# Tickoni Observability

This document summarizes the current Tickoni observability surface and the
operator signals expected from the tile runtime.

The current repo does not ship a local Prometheus/Grafana/Loki/Tempo Compose
stack for Tickoni. Phase 0 exposes runtime metrics and diagnostics through the
Zig supervisor and in-memory tile snapshots. The intended production direction
is still Firedancer-style per-tile metrics through `tkmetr` and diagnostics
through `tkdiag`.

## Principle

No black boxes.

Every tile, every future agent, every tool call, and every policy decision
should expose runtime state. Observability is not log text added after the
fact; it is part of the tile ownership model.

For V2.21 and V2.22 retail runtime support, this observability surface remains local-first
and evidence-oriented: CLI host reports, deterministic demo output, local audit
artifacts, replay artifacts, and linked conformance evidence. CaseOps UI
surfacing and hosted observability stacks are explicitly deferred work, not
implied current behavior. Both macOS and Windows retail tiers share the same
privacy defaults (telemetry disabled by default, no outbound telemetry required)
and the same evidence-oriented trust surface.

## Current Runtime Commands

Build the Tickoni supervisor:

```bash
just build-tk
```

Print the Phase 0 topology:

```bash
zig build run -- status
```

Run the Phase 0 payment pipeline:

```bash
zig build run -- start
```

The `start` command prints:

- tile states for the Phase 0 topology
- payment pipeline metric counters
- diagnostic counters
- replay status

Example output shape:

```text
tickoni-supervisor: Phase 0 pipeline completed
tiles:
  [0] ingest_tile  state=stopped
  ...
metrics: produced=10000 audited=10000 duplicates=1 denied=1 backpressure_waits=...
diag: sandbox_failures=0 replay_checked=true replay_match=true
tickoni-supervisor: stopped
```

## What Is Exposed

| Signal | Current source | Meaning |
| --- | --- | --- |
| Produced events | `PaymentPipelineState.produced` | Synthetic payments accepted by `tkings` |
| Normalized events | `normalized` | Events with valid framing and stable hashes |
| Invalid events | `invalid` | Malformed payment frames rejected by `tknorm` |
| Duplicate events | `duplicates` | Idempotency-key and event-hash duplicates found by `tkdedu` |
| Policy allows | `allowed` | Events allowed by `tkpoly` |
| Policy denies | `denied` | Events denied by `tkpoly` |
| Audit records | `audited` | Hash-chained records appended by `tkaudt` |
| Backpressure waits | queue `pushWaits()` | Producer waits caused by bounded queue saturation |
| Max queue depth | queue `maxDepth()` | Highest observed depth across Phase 0 queues |
| Max latency hops | `max_latency_hops` | Largest stage-hop count seen at audit append |
| Sandbox failures | `sandbox_failures` | Simulated tile sandbox failures |
| Crashed tile | `crashed_tile` | Tile index marked crashed by the supervisor path |
| Replay checked | `replay_checked` | Replay comparison completed |
| Replay match | `replay_match` | Replay matched recorded audit output |

## Per-Tile Visibility

Observability follows the tile boundary.

Phase 0 tiles:

| Tile | Signal focus |
| --- | --- |
| `tkings` / `ingest_tile` | produced events, ingress backpressure, sandbox failure simulation |
| `tknorm` / `normalize_tile` | valid framing, invalid drops, stable event hashes |
| `tkdedu` / `dedupe_tile` | duplicate detection by idempotency key and event hash |
| `tkpoly` / `policy_tile` | allow, deny, and duplicate-drop decisions |
| `tkaudt` / `audit_tile` | append-only audit ordering and hash-chain records |
| `tkrepl` / `replay_tile` | deterministic replay comparison and divergence count |
| `tkmetr` / `metric_tile` | metric snapshots from runtime state |
| `tkdiag` / `diag_tile` | crash, sandbox, audit, and replay diagnostics |

Future agent and tool tiles should expose the same bounded categories:

- events or calls received
- events or calls completed
- failures by bounded kind
- policy allows, denies, and approval requirements
- queue depth and backpressure
- latency distributions
- crash or shutdown state

## Smoke Checks

Use the narrowest command that checks the surface you changed:

- `just test-unit-tk` for Zig runtime, topology, supervisor, queue, sandbox,
  and payment pipeline behavior
- `zig build run -- start` for a manual supervisor output check
- `just test-unit-fd` for Firedancer-derived C unit tests
- `just test-all` for the repo test aggregate
- `just tests-all` for build, quality, security, and tests

## Failure Visibility

Failures are not silent.

The target model is crash-only: if a tile process exits unexpectedly, the
supervisor tears down the topology instead of hiding partial degraded state.
Phase 0 simulates this with `sandbox_fail_at`, records the failed tile, stops
the topology, and reports diagnostics through `snapshotDiag()`.

Failure categories to preserve as the architecture hardens:

- tile exit or sandbox failure
- audited malformed event rejection
- policy evaluation failure
- audit append failure
- replay divergence
- queue saturation and backpressure
- future tool and model gateway failures

## Related Docs

- [Telemetry](./telemetry.md)
- [Architecture](../knowledge/architecture.md)
- [Tickoni Testing](../execution/testing-tickoni.md)
