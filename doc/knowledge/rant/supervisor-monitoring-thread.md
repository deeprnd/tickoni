---
adr: "07"
title: "supervisor-monitoring-thread"
status: "proposed"
date: "2026-10-16"
authors:
  - "deeprnd"
tags:
  - "platform-supervisor"
  - "runtime-architecture"
supersedes: []
superseded_by: []
related:
  - "ADR-01: Firedancer orchestration reuse"
---

# ADR-02: Supervisor monitoring loop in a background thread

> Use a separate background thread for supervisor tile-health monitoring instead
> of blocking the main thread or requiring callers to poll manually.

## Decision Summary

In the context of Tickoni's process-mode supervisor, facing the gap between
having tile-crash detection primitives (`reapExitedChildrenNoHang`,
`refreshProcessHealth`, `hasCrashed`) and having no mechanism to exercise them
periodically, we decided to run a background monitoring thread that calls
reap + health check + sleep in a loop, and not to block the main thread or
require callers to poll manually, to achieve reliable crash detection without
caller-side boilerplate, accepting the minor complexity of thread lifecycle
management, because the supervisor needs to remain responsive to external events
(metrics queries, API requests, user input, signals) while tiles are running.

## Context and Problem Statement

The supervisor owns tile handles and can classify their state:

- `reapExitedChildrenNoHang()` calls `tryReapNoHang` on every child, updating
  handles to `.crashed`, `.stopped`, etc.
- `refreshProcessHealth()` reads CNC heartbeats and marks stale tiles.
- `hasCrashed()` reads the handle table and returns whether any handle is
  `.crashed`.

The problem is that no component calls these periodically. The supervisor is a
state machine, not an event loop. When a tile crashes (exits with non-zero,
receives a signal, or gets `FileNotFound`), the OS kernel knows, but the
supervisor's `TileState` stays `.running` until someone calls `reapExitedChildrenNoHang()`.

Current callers work around this:
- Tests call `reapExitedChildrenNoHang()` in their own `while` wait loops
  before checking `hasCrashed()`.
- Integration test runners have to remember this pattern or tests silently
  miss crashes and timeout.

This is fragile: every new caller must know to call the reap method. It also
means `hasCrashed()` is not a pure getter — it should just read state that
someone else already updated.

The supervisor's main thread should be able to:
- Poll metrics (`snapshotProcessMetrics`)
- Serve API requests (`tkapi` HTTP/WebSocket)
- Handle OS signals (SIGTERM, SIGINT)
- Wait for user input (CaseOps, interactive control)
- All while crash detection happens independently

**Decision question:** How should the supervisor periodically check tile health
and update handle state without blocking the main thread or requiring every
caller to poll manually?

This decision matters now because every new caller (tests, `tkapi` handlers,
future `tkdiag` endpoints, `tkexec` approval gates) must discover and implement
the same polling pattern, and the current workaround is test-specific boilerplate
that does not belong in production code.

## Scope

### In scope

- The supervisor's tile-crash detection and health monitoring mechanism
- Background thread lifecycle (start on pipeline start, stop on pipeline stop)
- Handle state updates produced by the monitor loop
- `hasCrashed()` as a pure getter (reads state updated by the monitor)

### Out of scope

- Tile respawn or restart logic (future work)
- CNC heartbeat configuration or stale-threshold tuning
- External metrics collection (Prometheus, external monitoring)
- Alarm/escalation on sustained crashes

## Decision Drivers

- Tile crashes must be detected automatically without caller-side polling
- The supervisor's main thread must remain responsive to external workloads
- `hasCrashed()` must be a pure getter — no side effects
- Thread lifecycle must be bounded: started with pipeline, stopped with pipeline
- The monitor loop must be observable and instrumentable

Quality attributes affected:

- Correctness: crashes detected reliably and promptly
- Maintainability: callers no longer need to know about reap
- Testability: tests can assert `hasCrashed()` directly without manual reap
- Observability: the monitor loop is a single instrumentable function
- Operability: main thread free to serve metrics, API, signals

## Constraints and Assumptions

- The supervisor must not spawn unbounded threads — exactly one monitor thread
  per pipeline instance
- Handle state is written only by the monitor thread and read by the main thread
- `std.thread` or `pthread` is available for the monitor (Linux target)
- Tile crash detection is the first monitoring capability; respawn comes later
- The monitor thread must exit cleanly when `process_state` is set to `null`

## Considered Options

1. **Main thread polling loop.** The main thread calls `reap` + `health` +
   sleep in a tight loop for the lifetime of the pipeline. Callers block until
   the pipeline stops.

2. **Background thread polling loop.** `startPaymentPipelineProcess` launches a
   dedicated monitor thread. The thread runs `reap` → `health` → sleep until
   `process_state` is nil. The main thread is free to do other work.

3. **Caller-driven polling (keep current).** Each caller (tests, API, metrics)
   must call `reapExitedChildrenNoHang()` and `refreshProcessHealth()` in its
   own loop. No supervisor-owned monitoring.

## Option Analysis

### Option 1: Main thread polling loop

The main thread calls `reapExitedChildrenNoHang()` + `refreshProcessHealth()`
every 5–10 ms until `stopProcess` is called.

Good, because:

- Simplest implementation — no threading, no shared-state concerns
- Fits the current synchronous model
- No thread lifecycle to manage

Bad, because:

- The main thread is now a dedicated monitor — it cannot poll metrics, serve
  API requests, handle signals, or process user input while tiles run
- Adding any external workload later means blocking or restructuring
- Industry standard is a dedicated monitoring thread (systemd, containerd,
  Kubernetes kubelet all do this)
- Tests that want to poll metrics while waiting for a crash still block

Neutral or conditional:

- Works for the current test-only usage but does not scale to production
  workloads (HTTP API, signal handling, metrics collection)

Validation needed:

- Confirm that tests or production code actually need the main thread for
  anything other than the polling loop

### Option 2: Background thread polling loop

`startPaymentPipelineProcess` creates one `std.Thread` (or `pthread`) that
runs `reap` → `health` → 5 ms sleep in a loop. The thread exits when
`process_state` is nil (set by `stopProcess`). The main thread is free.

Good, because:

- Clean separation of concerns: monitor thread owns crash detection, main
  thread owns orchestration
- Main thread can poll metrics, serve HTTP, handle signals, process input
  concurrently
- `hasCrashed()` is a pure getter — the background thread updates handles,
  the getter reads them
- Industry standard pattern: systemd, containerd, Kubernetes kubelet, Nomad
  all run monitoring in dedicated threads
- Future-proof: adding respawn logic, health endpoints, or event-driven
  reactions doesn't require changing the main thread
- Easy to instrument: one function to add metrics/tracing to

Bad, because:

- Requires thread lifecycle management (start on pipeline init, join on
  pipeline teardown)
- Minor complexity around shared state access (handles are read-only after
  init, so races are minimal — monitor writes state, main thread reads it)

Neutral or conditional:

- The monitor thread uses minimal CPU (5 ms sleep between checks)
- Thread creation overhead is one-time and negligible

Validation needed:

- Verify `std.thread` lifetime semantics on Linux
- Confirm handle writes are safe for monitor-to-main-thread access

### Option 3: Caller-driven polling (keep current)

No supervisor-owned monitoring. Every caller must call
`reapExitedChildrenNoHang()` and `refreshProcessHealth()` in its own wait
loop. `hasCrashed()` is a pure getter that just reads stale state.

Good, because:

- Zero new code in the supervisor
- No thread lifecycle

Bad, because:

- Every new caller must discover and implement the same pattern — tests,
  API handlers, metrics collectors, health gates
- Easy to forget: if a caller skips the reap call, `hasCrashed()` returns
  stale `.running` state and crashes go undetected
- Tests become the de facto monitor — they shouldn't own supervisor
  lifecycle logic
- `hasCrashed()` is semantically a getter but callers can't trust its result
  without manual reap first
- Production code will inevitably add its own poll loop, duplicating the test
  pattern and creating two independent monitors with no coordination

Neutral or conditional:

- Works for simple test cases but does not scale to production

Validation needed:

- N/A — this is the current state, not a proposed change

## Comparison

| Criterion | Weight | Option 1: Main thread | Option 2: Background thread | Option 3: Caller-driven |
| --- | ---: | --- | --- | --- |
| Automatic crash detection | High | Yes (blocks main) | Yes (background) | No (requires manual) |
| Main thread responsive | High | No — blocked 100% | Yes | Yes (if caller remembers) |
| Caller-side boilerplate | High | None | None | Required for every caller |
| `hasCrashed()` as pure getter | High | Yes (background updates) | Yes (background updates) | No — returns stale state |
| Thread lifecycle complexity | Med | None | Yes (one thread) | None |
| Future-proof (respawn, metrics) | Med | Hard — main blocked | Easy — main free | Hard — scattered monitors |
| Industry standard alignment | Low | Rare (embedded-only) | Common (systemd, kubelet) | No |

## Decision

**We will use a background thread for the supervisor monitoring loop.**

This is the standing choice for all process-mode supervisor instances.

The decisive factor is that the main thread must remain responsive to external
workloads while crash detection happens automatically in the background.
`hasCrashed()` must be a pure getter. Caller-side polling boilerplate does not
belong in production code.

Rejected alternatives:

- **Main thread polling loop:** rejected because it blocks the main thread
  entirely, preventing metrics queries, API requests, signal handling, and
  user input while tiles run.
- **Caller-driven polling:** rejected because it requires every caller to
  discover and implement the same reap pattern, making crashes silently
  undetectable when a caller forgets to poll.

## Consequences

### Positive consequences

- Crash detection is automatic — callers no longer need to know about reap
- `hasCrashed()` is a pure getter that returns accurate state
- Main thread is free to serve metrics, API, signals, and user input
- Single instrumentable monitor loop for health metrics
- Follows industry pattern used by systemd, containerd, and Kubernetes

### Negative consequences

- One additional thread per pipeline instance to manage
- Thread lifecycle must be bounded to pipeline lifetime
- Monitor thread writes handle state that main thread reads (minimal risk —
  handle state is the only shared data)

### Neutral consequences

- Monitor thread uses ~0% CPU between 5 ms polls
- Thread creation overhead is one-time and negligible

### Risks and mitigations

| Risk | Likelihood | Impact | Mitigation | Owner |
| --- | --- | --- | --- | --- |
| Monitor thread fails to start | Low | High | Fail closed in `startPaymentPipelineProcess` — pipeline does not run if monitor cannot start | supervisor |
| Monitor thread does not exit on stopProcess | Low | Medium | Monitor loop checks `process_state == null` each iteration; `stopProcess` sets it to null before joining | supervisor |
| Handle state race between monitor and main thread | Low | Medium | Monitor writes handles, main thread reads — no concurrent writes to same handle | supervisor |

## Implementation Plan

- Add `monitor_thread` field to `Supervisor` struct
- Add `monitor_loop` function that runs `reap` → `health` → sleep until
  `process_state` is nil
- Launch `monitor_thread` in `startPaymentPipelineProcess`
- Join and destroy `monitor_thread` in `stopProcess` before `process_state`
  is nulled
- Update `hasCrashed()` to read handle state (remove any side effects)
- Update tests to remove manual `reapExitedChildrenNoHang()` calls in wait
  loops

Migration/backward compatibility:

- Tests that currently call `reapExitedChildrenNoHang()` manually will still
  work — the monitor thread does not prevent additional calls
- The behavior is identical; only the source of state updates changes

Operational impact:

- One additional thread in process listings during pipeline lifetime
- Monitor loop is a single instrumentable function for health metrics

## Confirmation

Describe how compliance with the ADR will be checked after implementation.

- Tests: existing crash-detection tests assert `hasCrashed()` directly without
  manual reap; new test verifies monitor thread starts and stops correctly
- Review gates: design review for thread lifecycle, code owners for supervisor
- Build/CI checks: thread creation on all supported platforms (Linux, macOS,
  Windows)
- Observability: monitor loop iterations and handled reaps exposed via metrics

## Deviation Criteria

A future implementation may deviate from this decision only when at least one
of these conditions applies:

- The supervisor must run on a platform where `std.thread` or `pthread` is
  unavailable and no portable alternative exists
- The monitor thread's CPU or memory overhead becomes a demonstrated problem
  for the target deployment
- Respawn logic requires the main thread to directly control tile lifecycle
  in a way that conflicts with the monitor's ownership

Each deviation must record:

- why the default does not apply;
- which alternative is being used;
- who approved the deviation;
- how correctness and compatibility are verified;
- whether the deviation is temporary or permanent.

## Related Decisions and References

- ADR-01: Firedancer orchestration reuse (process-mode supervisor design)
- `src/app/tickoni/supervisor.zig` — supervisor implementation
- `src/disco/topo/fd_topo_run.c` — Firedancer tile lifecycle (no monitoring)
- systemd, containerd, Kubernetes kubelet — industry reference for monitoring
  loops

## Authoring Checklist

Before accepting the ADR, verify that:

- the decision question is explicit;
- all seriously considered options are named;
- the chosen option is stated as an actionable rule;
- rejected options are rejected for specific reasons;
- consequences include real costs, not just benefits;
- deviations are explicit when the default is not universal;
- validation/confirmation is concrete enough to test;
- links to superseded or related ADRs are included;
- instructional placeholder text has been removed.
