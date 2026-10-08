# Metric tile HTTP support on Windows

**Status:** planned  
**Scope:** Windows `fd_http_server` implementation, Tickoni's metric-tile wiring, and Windows integration coverage. Keep Linux and macOS behavior intact; the macOS port is tracked in `metric-tile-macos-support.md`.

## Goal

The Windows `metric` child must run the same `fd_stem`/Prometheus metric tile as other supported hosts: serve live `/metrics` over HTTP, return 404 on an unknown path, and stop cleanly on CNC HALT. A child process that starts and heartbeats but does not serve metrics is **not** a successful port.

## Current behavior and dependencies

- `src/waltz/http/Local.mk` selects `fd_http_server_windows_stub.c`. Its `fd_http_server_listen()` reports unsupported, `fd_http_server_poll()` does nothing, and `fd_http_server_printf()` does not render data. The Windows `fd_syscall_poll()` in `src/util/fd_util_hosted_windows.c` also returns `ENOTSUP`; linking the POSIX HTTP server unchanged will not fix this.
- `src/waltz/http/fd_http_server.c` assumes POSIX `int` descriptors, `struct pollfd`, `accept4()`, `read()`/`sendmsg()`/`close()`, and `errno`. Winsock uses `SOCKET`, `WSAPoll` (or another socket readiness mechanism), `recv()`/`send()`/`closesocket()`, and `WSAGetLastError()`. A `SOCKET` must not be truncated into the existing `int fd_http_server_fd()` API.
- `src/disco/metrics/fd_metric_tile.c` reads HTTP-server counters through `fd_http_server_private.h`, allocates server scratch using `fd_http_server_footprint()`, and renders via `fd_prometheus.c`. The Windows stub's private struct and scratch behavior differ from the real server; a listener-only implementation is insufficient. `src/disco/metrics/Local.mk` already lists the metric and Prometheus objects for hosted builds; check the actual Windows archives and link manifest when enabling their use.
- `src/tickoni/c_abi/shim/tile_run.c` sends the Windows `metric` tile to generic `TK_TILE_RUN`. `tk_metric_tile.c` defines `TK_METRIC_RUN` only on Linux, while `topob.c` reserves the metric HTTP scratch footprint only on Linux. The three HTTP tests in `test_metric_tile_integration.zig` skip non-Linux targets. Windows already has a `tk_topo_run_tile()` launcher and a `ws2_32` link in `build-lib/lib/firedancer.zig`.

## Implementation plan

### 1. Implement real Windows HTTP transport without a second protocol engine

- Decide and document an internal socket abstraction that preserves the existing `fd_http_server.h` semantics, ring-buffer staging, parsing, counters, and response behavior. Prefer reusing the shared HTTP logic in `fd_http_server.c` with a narrow Windows socket/readiness backend rather than maintaining a separate partial HTTP implementation. Do not replace an unsupported stub with another stub that reports success. If WebSocket/compression paths need additional Windows support, either port and test them as part of this API or explicitly identify and fail unsupported operations; do not silently change their behavior for other HTTP-server consumers.
- Make Winsock initialization and cleanup have explicit process ownership and balanced success/error paths (the supervisor and its tile children are separate processes). Implement nonblocking listener/accepted sockets, bind/listen, bounded readiness polling, accept, reads, writes, and close with correct `SOCKET` types and Winsock error translation. Handle `WSAEWOULDBLOCK`, interruption, EOF/reset, partial writes, and resource exhaustion without spinning, blocking the tile indefinitely, or claiming a successful response. Use socket-only polling inside the HTTP backend if appropriate; do not turn the global `fd_syscall_poll()` stub into an incorrect generic file-descriptor implementation merely for HTTP.
- Address public `fd_http_server_fd()` and callback/allow-FD users before changing handle types: use an explicit portable socket-handle API or platform-specific access where required, without casting a 64-bit Windows socket to `int`. Keep Linux/macOS callers and the Windows `sandbox=none` launcher compatible. Ensure the HTTP-server private layout, footprint, scratch alignment, staging/printf, and counters used by `fd_metric_tile.c` are real and consistent on Windows; the stub's smaller object must not masquerade as the real one.
- Update `src/waltz/http/Local.mk` to select the implementation instead of `fd_http_server_windows_stub.c` only once it has tests. Verify Windows CRT/WinSock header ordering, `ws2_32` and optional compression dependencies, and the existing Windows Firedancer link manifest. Add focused Windows HTTP-server tests for repeated GETs, 404, large/staged responses, idle polling, partial/closed connections, bind failure, and clean socket teardown; retain POSIX server tests and run the new tests on both Windows architectures.

### 2. Wire Windows into the real metric tile

- Once the HTTP backend is functional, compile and link `TK_METRIC_RUN` on Windows (`src/tickoni/c_abi/shim/tk_metric_tile.c`) and select it for the `metric` tile in `tile_run.c`. Continue to use Windows `tk_topo_run_tile()`; do not depend on Linux-only upstream `fd_topo_run_tile()` or seccomp. Keep the process-mode registry, topology, and non-metric tile dispatch unchanged.
- Enable the metric scratch-footprint lookup in `src/tickoni/c_abi/shim/topob.c` for Windows at the same time. Verify the parent and child rebuild identical layouts for `fd_metric_ctx_t` plus the real HTTP server (`src/tickoni/runtime/topo_build.zig`), and check any Windows-specific compile/link dependencies of `fd_metric_tile.c`, `fd_prometheus.c`, `fd_stem.c`, the Zig supervisor shim library, and the process integration binaries (`build-lib/lib/codec.zig`, `build-lib/lib/topo_run.zig`, `build-lib/lanes/integration.zig`). Resolve missing symbols in the build path; do not revert to generic metric-tile execution.
- Check that `privileged_init()` actually binds the configured loopback listener and reports initialization/bind failures as child failures with actionable diagnostics; it currently ignores the return from `fd_http_server_listen()`. Verify its metric context is initialized, rendering has working `fd_http_server_printf()` and counters, and `tk_metric_run()` joins CNC and exits via HALT with `allow_shutdown` under the Windows launcher. An HTTP port conflict must never produce a healthy-but-unreachable tile.

### 3. Replace skips with endpoint assertions on Windows

- In `src/tickoni/test/integration/test_metric_tile_integration.zig`, run the three existing HTTP 200/content, 404, and boot-timestamp tests on Windows as well as Linux (and macOS after its separate port). Remove only platform guards for environments whose real endpoint has passed verification; no catch-to-skip for connection failure. Keep the test helper's `py` invocation and Python availability explicit in Windows CI.
- Poll for **endpoint readiness** with a bounded deadline; payment-pipeline completion alone does not imply that the metric child has bound its socket. On timeout, report the port, request error, and metric tile health/exit status. Test repeated requests, idle operation, a disconnected client, port collision, and HALT during startup and after a request. Check a clean child exit without forced termination; retain the other process topology/start tests on Windows.

## Validation and acceptance criteria

1. On Windows x86_64 and ARM64 CI runners, run the Make-backed Firedancer/HTTP build and focused C HTTP tests, build `tickoni-supervisor`, then run `just test-integration-tk-windows-x86` and `just test-integration-tk-windows-arm` respectively. Confirm the metric HTTP tests **execute** (not merely compile or skip), pass, and the full integration lane is green.
2. `/metrics` returns HTTP 200 with `# HELP`/`# TYPE`, `metric_boot_timestamp_nanos`, and a nonzero `metric_bytes_read`; an unknown path returns 404. Multiple requests and idle polling cannot hang the metric tile. Listener failure or premature child exit is observable and makes the test fail, not skip.
3. CNC HALT stops the *real* Windows metric tile cleanly; parent and child agree on the HTTP scratch footprint; no socket-handle truncation, leaked sockets, or unsupported stubs appear on the exercised path. Exercise error paths including busy port and client reset.
4. Re-run the Linux and macOS HTTP/metric tests on their native runners to guard shared-server and dispatch behavior. No Windows-only metric protocol fork, fabricated successful `poll()`, or blanket Linux-only integration guard remains.

**Out of scope:** Linux sandbox/seccomp policy, changing the Tickoni process topology, and treating a generic heartbeating `metric` process or supervisor-side console snapshots as a substitute for the HTTP metric tile.
