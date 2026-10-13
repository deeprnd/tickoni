# Metric Tile Observability — CNC Heartbeat vs CNC App-Region vs HTTP

## The Three Observability Channels

Firedancer's metric tile exposes three independent channels. They serve different purposes and have different owners.

| Channel | Who writes | Who reads | Firedancer owns | Tickoni owns |
|---------|-----------|-----------|-----------------|--------------|
| **HTTP `/metrics`** | `fd_metric_tile.c` line 133: `FD_MGAUGE_SET(METRIC, BOOT_TIMESTAMP_NANOS, (ulong)ctx->boot_ts)` | Prometheus client / test HTTP caller | ✅ Yes | — |
| **CNC heartbeat** | `stem_run` calls `fd_cnc_heartbeat(cnc, now)` every iteration | Supervisor `refreshProcessHealth()` → `heartbeatQuery()` | ✅ Yes | — |
| **CNC app-region [idx]** | Tickoni shim `tk_metric_tile.c` lines 107-108, 158: writes `boot_ts` to app[2] | Supervisor `snapshotProcessMetrics()` → `appCounterRead(cnc, 2)` | ❌ No | ✅ Tickoni-only |

## What Firedancer's Orchestrator Actually Reads

**The supervisor NEVER reads `ctx->boot_ts` from the metric tile's scratch memory.** It has zero access to tile scratch.

**The supervisor NEVER reads CNC app-region data from the metric tile in Firedancer's design.** Firedancer's orchestrator checks the metric tile via:

1. **HTTP** — hits `http://localhost:{port}/metrics` and parses `metric_boot_timestamp_nanos > 1e18`. This is the canonical liveness signal.
2. **CNC heartbeat** — calls `heartbeatQuery(cnc)` every poll cycle. If heartbeat stops advancing → tile is stale → supervisor marks it crashed.

**Tickoni's CNC app[2] boot_ts write is a Tickoni-specific diagnostic optimization.** It lets the supervisor check "tile booted" via shared memory without HTTP. But it has no equivalent in Firedancer's design.

## `ctx->boot_ts` — Two Purposes

```
fd_metric_tile.c line 180:  ctx->boot_ts = fd_log_wallclock();
```

Set once in `unprivileged_init()`. Then:

1. **HTTP metrics** (line 133): `FD_MGAUGE_SET(METRIC, BOOT_TIMESTAMP_NANOS, (ulong)ctx->boot_ts)` → renders in `/metrics` → Firedancer-native, always works.
2. **CNC app[2]** (Tickoni shim only): `((ulong*)fd_cnc_app_laddr(cnc))[2] = (ulong)ctx->boot_ts` → supervisor reads via `appCounterRead(cnc, 2)` → Tickoni-specific, may have bugs in CNC address resolution.

## How Crash Detection Actually Works (No CNC App-Region Needed)

The orchestrator detects a crashed metric tile through two mechanisms that work without any Tickoni-specific CNC app-region writes:

1. **CNC heartbeat staleness**: `stem_run` (every iteration) calls `fd_cnc_heartbeat(cnc, now)`. The supervisor calls `heartbeatQuery(cnc)` on every poll. If the tile crashes, heartbeats stop → age exceeds `stale_after_ns` → supervisor marks tile `.crashed`.

2. **Process exit**: If the process dies, `pollChild()` returns `.observation = .{ .exited = code }` → supervisor marks `.crashed`.

The CNC app[2] boot_ts check is a *diagnostic* signal, not a *liveness* signal. If it reads zero, it means the CNC write path is broken — not that the tile failed to boot. The HTTP check (test 5) is the real test of boot success.

## Pitfalls

- **Don't assume CNC app-region writes are universal.** Every Firedancer tile updates the CNC heartbeat (built into `stem_run`). Only Tickoni's shim adds app-region writes. A future session that sees CNC app[2] reads zero should check the CNC address resolution (correct workspace? correct laddr? sufficient `app_sz`?) — not assume the tile failed to boot.
- **Don't confuse CNC heartbeat with CNC app-region.** They are separate: the heartbeat is a `long` field in the CNC struct (`cnc->heartbeat`), updated by `stem_run`'s housekeeping loop. The app-region is a separate `app_sz` byte area at `cnc + 64`, populated by application code (Tickoni's shim in this case). The supervisor reads them differently: `heartbeatQuery()` vs `appCounterRead()`.
- **The CNC app-region write may silently fail if `app_sz` is too small.** `fd_cnc_footprint(app_sz)` allocates the CNC struct + app-region. If the topology builder uses a smaller `app_sz` than the number of app-region indices × 8 bytes, writes to higher indices land in unmapped or non-CNC memory. The supervisor's `appCounterRead()` may read stale/zero/garbage without crashing. Verify `app_sz >= (max_idx + 1) * 8`.
- **HTTP is the canonical signal.** If the CNC boot_ts check fails but HTTP test 5 passes, the tile booted correctly — the CNC diagnostic path has a bug. Fix the CNC path or remove the assertion. Don't weaken the HTTP check to compensate.

## Debugging CNC App-Region Reads

When the supervisor reads zero or stale values from CNC app-region index N:

1. **Verify `app_sz`**: Check the topology builder allocates `app_sz >= (N+1) * 8`.
2. **Verify CNC object identity**: The supervisor joins CNC at `topoObjLaddr(topo, cnc_obj_id[i])`. The tile process sets `ctx->cnc = cnc_laddr` where `cnc_laddr = fd_topo_obj_laddr(topo, cnc_obj_id)`. If `cnc_obj_id` differs between supervisor and tile (e.g., topology rebuild mismatch), they write/read different CNC objects.
3. **Verify write visibility**: The CNC app-region is shared memory. Writes from the tile process should be visible to the supervisor unless there's a cache coherency issue (unlikely on x86, possible on ARM without proper barriers).
4. **Check the supervisor's CNC join**: The supervisor's `cncs[i]` must resolve to the same CNC object the tile process wrote to. If `state.cncs[i]` is NULL or points to a different object, the read returns garbage.
5. **Use HTTP as the ground truth**: If HTTP `/metrics` returns a valid `metric_boot_timestamp_nanos > 1e18`, the tile booted correctly. The CNC app-region read failure is isolated to the Tickoni-specific diagnostic path.
