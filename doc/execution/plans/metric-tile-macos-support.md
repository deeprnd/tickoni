# Metric tile HTTP support on macOS

**Status:** planned  
**Scope:** macOS `fd_http_server` socket behavior, Tickoni metric-tile dispatch and scratch layout, and integration coverage. Windows is a separate port.

## Goal

Run the real `metric` tile on macOS: serve Prometheus `/metrics` from `fd_stem`/`fd_http_server`, report HTTP 404 for unknown paths, and exit cleanly when the supervisor signals CNC HALT. Do not change the process topology or substitute a different implementation of the metrics endpoint. Preserve Linux behavior and keep the Windows fallback until Windows has a working HTTP server.

## Current behavior and blockers

- `src/tickoni/c_abi/shim/tile_run.c` selects `TK_METRIC_RUN` only under `FD_HAS_LINUX`. On macOS, the `metric` tile runs generic `TK_TILE_RUN`, whose Zig pipeline callback does no metric-tile work (`src/app/tickoni/tile_main.zig`). A successful process-start or shutdown test therefore does **not** demonstrate that `/metrics` is served.
- `src/tickoni/c_abi/shim/tk_metric_tile.c` compiles `TK_METRIC_RUN` only on Linux, and `src/tickoni/c_abi/shim/topob.c` gives the metric tile its HTTP/stem scratch footprint only on Linux. Enabling dispatch without enabling the same layout risks a scratch overflow.
- `src/waltz/http/Local.mk` already builds the real `fd_http_server.c` on macOS, and `src/util/fd_util_hosted_posix.c` uses `poll()` there. But `fd_http_server.c` defines missing `SOCK_NONBLOCK` and `SOCK_CLOEXEC` as zero. Its `accept4_compat()` tests the passed flags before calling `fcntl()`, and `fd_http_server_listen()` never sets the listening socket nonblocking explicitly. On macOS targets lacking those flags, accepted and listening sockets can remain blocking; `accept_conns()` loops until `EAGAIN` and can stall the tile. Its `send()`/`sendmsg()` paths also assume `MSG_NOSIGNAL`; ensure broken clients cannot deliver SIGPIPE to the process.
- The three HTTP tests in `src/tickoni/test/integration/test_metric_tile_integration.zig` skip every non-Linux target. `src/disco/metrics/fd_metric_tile.c` is already included in the hosted `fd_disco` build; its seccomp filter body is disabled, and macOS launches tiles with `sandbox=none`. There is no requirement to add Linux seccomp to make the macOS endpoint work.

## Implementation steps

### 1. Make the existing HTTP transport safe on macOS

- In `src/waltz/http/fd_http_server.c`, make socket setup explicit: create the listening socket and set `O_NONBLOCK` and `FD_CLOEXEC` with checked `fcntl()` calls on macOS. After `accept()`, set both flags on each accepted socket; close it and report/handle errors if setup fails. Do not rely on zero-valued `SOCK_*` compatibility macros to request these properties. Preserve the Linux `socket()`/`accept4()` fast path and its nonblocking semantics.
- Handle SIGPIPE on macOS with a socket-local mechanism such as `SO_NOSIGPIPE` on sockets that send, and use supported send flags there. Do not globally ignore SIGPIPE. Preserve `MSG_NOSIGNAL` on Linux. Verify `EAGAIN`/`EWOULDBLOCK`, interrupted calls, client disconnects, and error/close paths against the existing poll loop; do not replace the bounded poll loop with blocking I/O.
- Extend the existing `src/waltz/http/test_http_server.c` coverage, or add a focused test in that lane, for multiple sequential connections, a peer disconnect during a response, and idle polling without a request. On macOS the test must complete without blocking or terminating the process; retain Linux coverage.

### 2. Enable the *real* metric tile on macOS

- Extend the `TK_METRIC_RUN` compilation and metric-name dispatch in `src/tickoni/c_abi/shim/tk_metric_tile.c` and `src/tickoni/c_abi/shim/tile_run.c` to `FD_HAS_LINUX || FD_HAS_MACOS`. macOS must continue to use the existing `tk_topo_run_tile()` launcher; Linux must continue to use upstream `fd_topo_run_tile()`. Do not send the metric tile through `TK_TILE_RUN` on macOS.
- Extend the metric scratch-footprint lookup in `src/tickoni/c_abi/shim/topob.c` to macOS **at the same time** as dispatch. Check that the finalized metric tile object can hold `fd_metric_ctx_t` plus the server and that parent and child rebuild the same topology/layout (`src/tickoni/runtime/topo_build.zig`). Keep non-metric tile footprints unchanged.
- Check the macOS build/link of `fd_metric_tile.c`, `fd_prometheus.c`, `tk_metric_tile.c`, and their `fd_stem` symbols through the existing `build-lib/lib/topo_run.zig` and `build-lib/lib/helpers.zig` paths. Resolve platform-specific header or symbol issues at their boundary rather than falling back to generic tile execution. Confirm the metric callback reaches its listener and preserves CNC HALT/`allow_shutdown` behavior under the macOS launcher.
- Make listener initialization fail visibly if it cannot bind/listen instead of letting the tile appear healthy without an endpoint. Preserve the existing fail-closed process-health reporting; verify behavior for a port already in use.

### 3. Make macOS HTTP coverage non-optional

- Change the three HTTP test guards in `src/tickoni/test/integration/test_metric_tile_integration.zig` to skip **Windows only** until its HTTP backend is implemented. Assert HTTP 200, valid metric names and values, boot timestamp, and HTTP 404 on macOS as on Linux. Keep the portable topology/start/shutdown tests running on all targets.
- Use bounded readiness polling for the actual endpoint rather than assuming the server is ready when the pipeline reaches its audited count. Distinguish an endpoint that never starts from a transient connection refusal; fail within a deadline and include tile exit/health and request errors. Avoid fixed sleeps, infinite retries, or turning an unavailable endpoint into a skip. Confirm a repeated request and an idle-period request complete, then request CNC HALT and assert the metric child exits cleanly without a forced kill.
- If the HTTP test helper is changed, keep its macOS/Linux Python invocation and bounded timeout working. Remove stale comments claiming these tests use a POSIX-socket client; they currently use `metric_http_get.py`.

## Verification and acceptance

1. On **both macOS x86_64 and arm64**, run the platform build and `just test-integration-tk-macos-x86` / `just test-integration-tk-macos-arm` on their respective CI runners. Confirm the three HTTP tests **ran** (zero skips for macOS), the existing metric lifecycle tests passed, and the whole integration lane passed. Run the C HTTP-server tests through the project's Make-backed test lane on macOS as well.
2. Exercise an idle listener, sequential `/metrics` requests, an unknown path, early client disconnect, port collision, and HALT during or shortly after startup. The tile must neither block on a second `accept()` nor die from SIGPIPE; a failed listener must not be reported as a healthy metrics endpoint. The supervisor must observe a clean metric-tile shutdown, not just a completed payment pipeline.
3. Run the Linux HTTP-server and metric integration tests to catch socket and dispatch regressions. Keep Windows build/integration green without claiming `/metrics` support: its `fd_http_server_windows_stub.c` currently cannot listen or poll, so Windows HTTP assertions remain skipped until that separate port lands.
4. Completion requires live `/metrics` on macOS, equivalent response content and status codes to Linux, correctly sized metric scratch, no indefinite blocking or SIGPIPE on disconnect, and no macOS `SkipZigTest` for metric HTTP. Compilation or process-start success alone is insufficient.

**Portability boundary:** Keep OS differences in the HTTP socket implementation and the launcher; metric rendering, tile identity, scratch sizing, and HTTP integration expectations should be shared. Do not broaden this work into a Windows Winsock implementation or change Linux sandbox policy.
