# Windows metric tile — gap analysis

**Assessed:** 2026-10-15  
**Source plan:** `doc/execution/plans/metric-tile-windows-support-done.md`  
**Status:** **not enabled** — Windows transport built, but not wired into HTTP server or metric tile

## Summary

The Windows HTTP transport implementation (`tk_http_socket_windows.c`) is complete and implements the full portable transport table. However, the transport is not compiled into the build, `fd_http_server.c` doesn't select it on Windows, `TK_METRIC_RUN` is Linux-only, and the `TK_HAS_METRIC_TILE` macro doesn't exist. Windows still uses no metric tile at all — it has no HTTP server, no metric dispatch, and no integration test coverage.

## What's already done

### 1. `tk_http_socket_windows.c` is complete (398 lines)

The file implements the full portable transport table with Winsock:
- `tk_windows_runtime_init()` — `WSAStartup(MAKEWORD(2,2))` with balanced cleanup
- `tk_windows_runtime_fini()` — Winsock kept initialized until process exit
- `tk_windows_listen()` — `WSASocketW(..., WSA_FLAG_NO_HANDLE_INHERIT)`, `ioctlsocket(FIONBIO)`, `SO_EXCLUSIVEADDRUSE`, `bind`, `listen`
- `tk_windows_accept()` — `accept()`, nonblocking config, error handling
- `tk_windows_poll()` — `WSAPoll()` with `WSAPOLLFD` entries, proper `revents` mapping
- `tk_windows_receive()` — `recv()` with `WSAGetLastError()`
- `tk_windows_send()` — `WSASend()` with `WSABUF`
- `tk_windows_sendv()` — `WSASend()` with `WSABUF` array for vectored writes
- `tk_windows_close()` — `closesocket()`
- `tk_windows_local_port()` — `getsockname()` with port extraction

The transport uses `tk_http_socket_t` as `ulong` (width-safe), preserves `SOCKET` without truncation through `int`, and maps all `WSAGetLastError()` values to portable statuses (`WOULD_BLOCK`, `INTERRUPTED`, `PEER_RESET`, `PEER_CLOSED`, `ADDRESS_IN_USE`, `RESOURCE_EXHAUSTED`, `ACCESS_DENIED`, `INVALID_ARGUMENT`, `SYSTEM_ERROR`).

### 2. `fd_http_server.c` is real (not stub)

`fd_http_server_windows_stub.c` no longer exists. `fd_http_server.c` uses the portable transport table for all socket operations. The HTTP protocol engine, request parsing, response staging, ring buffers, counters, WebSocket framing, and Prometheus rendering are all in the shared C source.

### 3. `fd_metric_tile.c` already builds on Windows

Firedancer's `fd_metric_tile.c` is included in the hosted build. Its seccomp filter body is disabled. Windows launches tiles with `sandbox=none`.

## What's still blocking Windows

### Gate 1: `tk_metric_tile.c` is Linux-only (line 36)

```c
#if FD_HAS_LINUX   // entire file
```

`TK_METRIC_RUN` definition — all callbacks, scratch footprint, `privileged_init`, `stem_run` — does not exist on Windows.

### Gate 2: `tile_run.c` include guard (line 50)

```c
#if FD_HAS_LINUX
#include "../topo_run/tk_metric_tile.h"
#endif
```

Windows never sees the `TK_METRIC_RUN` extern declaration.

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
  run_tile = &TK_TILE_RUN;   // ← Windows: metric tile goes here
#endif
```

Every tile on Windows — including `metric` — takes the generic `TK_TILE_RUN` path.

### Gate 4: `topob.c` header include (line 387)

```c
#if FD_HAS_LINUX
#include "../topo_run/tk_metric_tile.h"
#endif
```

Same problem — topology builder can't reference `TK_METRIC_RUN` on Windows.

### Gate 5: scratch footprint lookup (lines 393-398)

```c
#if FD_HAS_LINUX
  if( strcmp( tile_name, "metric" ) == 0 )
    return tk_metric_scratch_footprint();
#endif
return 1UL;   // ← Windows returns 1 byte for a ~32MB metric tile
```

Windows topology queries return 1 byte for metric tile scratch. If dispatch were enabled without this fix, the C initializer would write an `fd_metric_ctx_t` plus HTTP server into a 1-byte allocation — out-of-bounds write.

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
*footprint_out = 1UL;   // ← Windows: generic alignment/footprint
```

### Gate 7: `TK_HAS_METRIC_TILE` macro doesn't exist

The metric-review-done.md plan proposes:
```c
#if FD_HAS_HOSTED && (FD_HAS_LINUX || FD_HAS_MACOS || FD_HAS_WINDOWS)
#define TK_HAS_METRIC_TILE 1
#else
#define TK_HAS_METRIC_TILE 0
#endif
```

This macro doesn't exist in any source file. It's only mentioned in `metric-review-done.md` as a proposed contract. Windows must not set this to `1` until the real HTTP transport is linked.

### Gate 8: Windows transport not compiled into build

`tk_http_socket_windows.c` exists but is not added to any build manifest. The Zig build (`build-lib/lib/firedancer.zig`) has `ws2_32` link for Windows, but the transport file isn't wired into the C compilation units that feed `fd_http_server.c`.

## What needs to change

1. **Add `tk_http_socket_windows.c` to build** — wire it into the Zig build manifests and `Local.mk` for Windows hosted targets. Link `ws2_32`.

2. **Enable `fd_http_server.c` on Windows** — ensure it compiles and links with the transport table on Windows (currently it does, but verify the build path).

3. **Create `TK_HAS_METRIC_TILE` macro** — in `src/tickoni/c_abi/topo_run/tk_metric_tile.h` or a dedicated header. Set to `0` on Windows until steps 1-2 are verified.

4. **Expand `#if FD_HAS_LINUX` → `#if FD_HAS_LINUX || FD_HAS_MACOS || FD_HAS_WINDOWS`** in all five gates above (only after step 3 ensures Windows can't enable prematurely).

5. **Enable `TK_METRIC_RUN` compilation** on Windows in `tk_metric_tile.c:36` — the file already includes `fd_metric_tile.h` which builds on Windows.

6. **Enable metric dispatch** in `tile_run.c:128` — Windows uses `tk_topo_run_tile()` (the existing path for non-Linux targets), which already accepts `TK_METRIC_RUN`.

7. **Enable scratch footprint lookup** in `topob.c:393` and `topob.c:404` — same `#if` expansion.

8. **Enable `tk_metric_tile.h` include** in `tile_run.c:50` and `topob.c:387` — same expansion.

9. **After verification**: enable Windows in `TK_HAS_METRIC_TILE`, select `TK_METRIC_RUN`, and apply real scratch requirements in the same change.

## Test gaps

### 1. Integration tests skip Windows (will remain skipped)

`test_metric_tile_integration.zig` gates HTTP tests behind `FD_HAS_LINUX`. After enabling Windows:
- Remove Windows skip in the same change as enabling `TK_METRIC_RUN`.
- Add `waitForMetricEndpoint()` with bounded deadline (not just pipeline completion).
- Assert HTTP 200 with `# HELP`/`# TYPE`, `metric_boot_timestamp_nanos > 1e18`, `metric_bytes_read > 0`.
- Assert HTTP 404 for unknown paths.
- Assert clean child exit after CNC HALT (no force action).
- Assert repeated requests and idle polling complete.
- Assert connection failure is never converted to a skip.

### 2. Windows-specific socket tests

The plan requires tests for:
- Nonblocking accept
- Poll readiness
- Exact send/receive
- Peer close/reset
- Busy port (address in use)
- Handle cleanup
- Non-inheritance (`WSA_FLAG_NO_HANDLE_INHERIT` verified)
- Balanced `WSAStartup`/`WSACleanup`

### 3. Deterministic shared-engine tests

The plan requires tests with an injected fake transport for:
- Would-block
- Interruption
- Partial send
- Reset
- Accept failure
- Poll failure
- Cleanup
- Balanced runtime ownership

## Verification

After changes:
- `zig build test` passes on Windows.
- `just test-integration-tk-windows-x86` and `just test-integration-tk-windows-arm` run all HTTP tests (zero skips for Windows).
- `curl localhost:<port>/metrics` returns Prometheus format with expected fields.
- `curl localhost:<port>/foo` returns HTTP 404.
- Supervisor observes clean metric-tile shutdown on CNC HALT.
- No `WSAStartup` leak (exactly one per process, balanced at exit).
- No `SOCKET` truncated through `int`.
- No `INFINITE` in `WaitForSingleObject` (used only for `Sleep()` in poll timeout path, not for reap).

## Risk

1. **Out-of-bounds write**: Enabling `TK_METRIC_RUN` on Windows without fixing the scratch footprint gates first will cause an out-of-bounds write on the metric child's scratch allocation. All five `#if` expansions must be in a single change.

2. **Winsock handle narrowing**: `SOCKET` is a 64-bit handle on Windows. If any caller passes it through `int` or the old `fd_http_server_fd()` API, handles will be truncated. The transport table's `tk_http_socket_t` (ulong) prevents this, but the old API must not be called.

3. **Winsock runtime ownership**: `WSAStartup` is process-global. The transport's `runtime_init()` uses an atomic flag to ensure exactly one `WSAStartup`, and `runtime_fini()` does nothing (keeps Winsock alive until process exit). If this is broken, concurrent HTTP servers or other Winsock users will corrupt state.

4. **`Sleep(INFINITE)` in poll**: `tk_windows_poll()` calls `Sleep(INFINITE)` when `timeout_ms < 0` and no entries are valid (line 234). This is acceptable for idle waiting but must not be used for process reap or shutdown. The metric tile's `before_credit()` should always pass a bounded `timeout_ms`.

## Comparison: macOS vs Windows

| Aspect | macOS | Windows |
|---|---|---|
| `fd_http_server.c` | Real, uses transport | Real, uses transport |
| Transport backend | Not implemented | Complete (`tk_http_socket_windows.c`) |
| `TK_METRIC_RUN` | Linux-only gate | Linux-only gate |
| Scratch footprint | Linux-only lookup | Linux-only lookup |
| Test skips | Linux-only | Linux-only |
| Build wiring | Already wired | Not wired (needs `Local.mk` + Zig manifest) |
| Unique risks | `SO_NOSIGPIPE`, `fcntl()` | `WSAStartup` ownership, `SOCKET` width |

Windows has an additional gap: the transport backend exists but isn't compiled into the build. macOS has the transport wired (via POSIX `poll()` in `fd_util_hosted_posix.c`), so its remaining gates are purely the `#if` expansions.
