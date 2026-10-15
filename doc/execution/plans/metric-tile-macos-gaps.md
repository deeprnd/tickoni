# macOS metric tile — gap analysis

**Assessed:** 2026-10-15  
**Source plan:** `doc/execution/plans/metric-tile-macos-support-done.md`  
**Status:** **not enabled** — infrastructure built, gates still Linux-only

## Summary

The portable HTTP transport layer (`tk_http_socket`, transport table, real `fd_http_server.c`) is complete and already compiles on macOS. However, every `TK_METRIC_RUN` definition, include, and dispatch path remains gated behind `#if FD_HAS_LINUX`. macOS still takes the generic `TK_TILE_RUN` path (Zig callbacks, no HTTP server) and would receive a 1-byte scratch allocation if it attempted the metric tile — a potential out-of-bounds write.

## What's already done

### 1. `fd_http_server.c` is real on macOS

`fd_http_server_windows_stub.c` no longer exists. `fd_http_server.c` uses the portable `tk_http_socket` transport table for all socket operations. The transport table has fixed operations: runtime init/fini, poll scratch, listen, accept, poll, receive, send, sendv, close, and local-port lookup. `fd_http_server.c` no longer calls `socket`, `accept4`, `poll`, `read`, `send`, `sendmsg`, or `close` directly — it goes through the transport table.

### 2. macOS HTTP socket behavior is handled

macOS native socket behavior (nonblocking via `fcntl()`, `FD_CLOEXEC`, `SO_NOSIGPIPE`) lives in the transport layer. The Linux `accept4()` fast path is preserved. macOS uses `accept()`, `poll()`, `recv()`, `send()`/sendv with flags `0`, and `close()`. No process-wide `SIGPIPE` handler.

### 3. `fd_metric_tile.c` already builds on macOS

Firedancer's `fd_metric_tile.c` is included in the hosted build. Its seccomp filter body is disabled. macOS launches tiles with `sandbox=none`.

## What's still blocking macOS

### Gate 1: `tk_metric_tile.c` is Linux-only (line 36)

```c
#if FD_HAS_LINUX   // entire file
```

`TK_METRIC_RUN` definition — all callbacks, scratch footprint, `privileged_init`, `stem_run` — does not exist on macOS.

### Gate 2: `tile_run.c` include guard (line 50)

```c
#if FD_HAS_LINUX
#include "../topo_run/tk_metric_tile.h"
#endif
```

macOS never sees the `TK_METRIC_RUN` extern declaration.

### Gate 3: metric dispatch in `tile_run.c` (lines 128-139)

```c
#if FD_HAS_LINUX
  if( tile_is_metric( tile_c ) ) {
    run_tile = &TK_METRIC_RUN;
  } else {
    run_tile = &TK_TILE_RUN;
  }
#else
  (void)tile_is_metric;
  run_tile = &TK_TILE_RUN;   // ← macOS: metric tile goes here
#endif
```

Every tile on macOS — including `metric` — takes the generic `TK_TILE_RUN` path.

### Gate 4: `topob.c` header include (line 387)

```c
#if FD_HAS_LINUX
#include "../topo_run/tk_metric_tile.h"
#endif
```

Same problem — topology builder can't reference `TK_METRIC_RUN` on macOS.

### Gate 5: scratch footprint lookup (lines 393-398)

```c
#if FD_HAS_LINUX
  if( strcmp( tile_name, "metric" ) == 0 )
    return tk_metric_scratch_footprint();
#endif
return 1UL;   // ← macOS returns 1 byte for a ~32MB metric tile
```

macOS topology queries return 1 byte for metric tile scratch. If dispatch were enabled without this fix, the C initializer would write an `fd_metric_ctx_t` plus HTTP server into a 1-byte allocation — out-of-bounds write.

### Gate 6: scratch requirements (lines 404-414)

```c
#if FD_HAS_LINUX
  if( strcmp( tile_name, "metric" ) == 0 ) {
    ulong footprint = tk_metric_scratch_footprint();
    *alignment_out  = fd_scratch_smem_align();
    *footprint_out  = fd_scratch_smem_footprint( footprint );
    return;
  }
#endif
*alignment_out = 1UL;
*footprint_out = 1UL;   // ← macOS: generic alignment/footprint
```

## What needs to change

1. **Expand `#if FD_HAS_LINUX` → `#if FD_HAS_LINUX || FD_HAS_MACOS`** in all five gates above.
2. **Enable `TK_METRIC_RUN` compilation** on macOS in `tk_metric_tile.c:36` — the file already includes `fd_metric_tile.h` which builds on macOS.
3. **Enable metric dispatch** in `tile_run.c:128` — macOS uses `tk_topo_run_tile()` (the existing path for non-Linux targets), which already accepts `TK_METRIC_RUN`.
4. **Enable scratch footprint lookup** in `topob.c:393` and `topob.c:404` — same `#if` expansion, `tk_metric_scratch_footprint()` exists once `TK_METRIC_RUN` compiles.
5. **Enable `tk_metric_tile.h` include** in `tile_run.c:50` and `topob.c:387` — same expansion.

## Test gaps

### 3. Integration tests still skip macOS

`test_metric_tile_integration.zig` gates HTTP tests behind `FD_HAS_LINUX`. After enabling macOS dispatch, these tests must:
- Run on macOS x86_64 and arm64 with no skips.
- Assert endpoint readiness with bounded deadline (not just pipeline completion).
- Assert HTTP 200 with `# HELP`/`# TYPE`, `metric_boot_timestamp_nanos > 1e18`, `metric_bytes_read > 0`.
- Assert HTTP 404 for unknown paths.
- Assert clean child exit after CNC HALT (no force action).
- Assert repeated requests and idle polling complete.

### 4. macOS-specific socket tests

The plan requires tests for:
- Listener and accepted sockets have `O_NONBLOCK`, `FD_CLOEXEC`, `SO_NOSIGPIPE`.
- Idle poll and second accept do not block.
- Disconnect during response does not terminate the process.
- Busy port fails initialization.
- Next request succeeds after peer reset.

## Verification

After changes:
- `zig build test` passes on macOS.
- `just test-integration-tk-macos-x86` and `just test-integration-tk-macos-arm` run all HTTP tests (zero skips).
- `curl localhost:<port>/metrics` returns Prometheus format with expected fields.
- `curl localhost:<port>/foo` returns HTTP 404.
- Supervisor observes clean metric-tile shutdown on CNC HALT.

## Risk

Enabling `TK_METRIC_RUN` on macOS without fixing the scratch footprint gates first will cause an out-of-bounds write on the metric child's scratch allocation. The `TK_METRIC_RUN` definition, header include, and dispatch must all be expanded in a single change to prevent intermediate states where dispatch is enabled but scratch is undersized.
