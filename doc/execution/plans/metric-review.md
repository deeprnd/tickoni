# Metric tile and process portability implementation review

**Status:** implementation required  
**Scope:** macOS/Windows metric HTTP support, metric topology identity and scratch layout, process shutdown/reaping, and native-platform regression coverage

## Verdict

The three reviewed plans are only partially implemented. The metric endpoint correctly reuses Firedancer’s C tile instead of introducing a Zig implementation, but macOS support is unsafe, Windows does not serve metrics, topology indices are not stable, and shutdown/reaping does not satisfy the required ownership and evidence rules.

The process-mode path is `src/app/tickoni/supervisor.zig` → `src/app/tickoni/tile_main.zig` → `src/tickoni/runtime/tile_process.zig` → `src/tickoni/c_abi/shim/tile_run.c`. I found no `orchestrator.zig` in this repository. On Linux and macOS, dispatch selects the thin `TK_METRIC_RUN` adapter in `tk_metric_tile.c`, which calls the existing C metric initialization and `stem_run` (`src/tickoni/c_abi/shim/tk_metric_tile.c:81-95,112-129`). That is the reuse you wanted—not a second metrics implementation. Windows currently takes the generic tile path instead.

### Highest-impact findings

1. **Critical — macOS metric scratch is undersized.** macOS dispatch selects `TK_METRIC_RUN` (`src/tickoni/c_abi/shim/tile_run.c:120-125`), but the footprint lookup is Linux-only and returns `1UL` on macOS (`src/tickoni/c_abi/shim/topob.c:387-397`). The C initializer places a metric context and HTTP server in that scratch (`src/disco/metrics/fd_metric_tile.c:145-159`). This is a potential out-of-bounds write. The topology test checks the object’s offset, not its required size (`src/tickoni/test/integration/test_metric_tile_integration.zig:225-240`).

   **Implementation contract:**

   1. Add one capability macro to `src/tickoni/c_abi/topo_run/tk_metric_tile.h`:
      ```c
      #if FD_HAS_HOSTED && (FD_HAS_LINUX || FD_HAS_MACOS || FD_HAS_WINDOWS)
      #define TK_HAS_METRIC_TILE 1
      #else
      #define TK_HAS_METRIC_TILE 0
      #endif
      ```
      Use `TK_HAS_METRIC_TILE`—and no separate OS guard—for the `TK_METRIC_RUN` declaration/definition, dispatch in `tile_run.c`, and scratch queries in `topob.c`. Windows must not set this macro to `1` until the real Windows HTTP transport from finding 2 is linked.
   2. Replace `tk_metric_scratch_footprint()` with one C-owned query:
      ```c
      void
      tk_metric_scratch_requirements( ulong * align,
                                      ulong * footprint );
      ```
      It returns `TK_METRIC_RUN.scratch_align()` and `TK_METRIC_RUN.scratch_footprint( NULL )`. Zig must not reproduce `fd_metric_ctx_t` or HTTP-server layout calculations.
   3. In `topob.c`, make both `tile_align()` and `tile_footprint()` read the per-object properties `tickoni.scratch_align` and `tickoni.scratch_footprint`. Generic Tickoni tiles keep alignment and footprint `1UL`; the metric tile receives the exact values from `tk_metric_scratch_requirements()`.
   4. In `topo_build.zig`, set both properties before `fd_topob_finish()` for the metric tile in both parent and child rebuilds. Add `tk_topo_validate_metric_scratch()` in `topob.c`; it must verify the metric tile owns the object, the finalized footprint is at least the required footprint, and the object offset satisfies the required alignment. Abort topology construction before spawning children when validation fails.
   5. Replace the offset-only test with assertions for exact required alignment, sufficient footprint, successful validation, and identical parent/child topology results. Run this test on Linux, macOS, and Windows once Windows transport support is enabled.

   **Done condition:** No platform can select `TK_METRIC_RUN` while receiving the generic one-byte tile object, and topology construction—not tile startup—detects every layout mismatch.

2. **High — Windows has no live metric endpoint.** Windows dispatches to generic `TK_TILE_RUN` (`tile_run.c:126-129`); `TK_METRIC_RUN` is not compiled there (`tk_metric_tile.c:36`). The Windows build selects `fd_http_server_windows_stub.c` (`src/waltz/http/Local.mk:12-16`), whose `listen()` returns unsupported and whose rendering is nonfunctional (`src/waltz/http/fd_http_server_windows_stub.c:90-96,125-135`). The requested Windows route back through Tickoni-specific HTTP shims has **not** been implemented.

   **Implementation contract:**

   The final call path is fixed:
   ```text
   supervisor.zig / tile_process.zig
     → TK_METRIC_RUN in tk_metric_tile.c
     → fd_metric_tile.c / fd_stem.c / fd_prometheus.c
     → shared fd_http_server.c protocol engine
     → Tickoni tk_http_socket_* transport shim
   ```

   1. Create `src/tickoni/c_abi/shim/tk_http_socket.h` and three backends: `tk_http_socket_linux.c`, `tk_http_socket_macos.c`, and `tk_http_socket_windows.c`. Compile exactly one backend per hosted target. All native socket headers, constants, handles, error values, and readiness APIs stay in these files.
   2. Define `tk_http_socket_t` as `ulong` with `ULONG_MAX` as invalid. Define a portable poll entry containing `tk_http_socket_t`, requested events, and returned events. Define transport results with a project-owned status plus an unmodified native error code. Required statuses are `ok`, `would_block`, `interrupted`, `peer_closed`, `peer_reset`, `address_in_use`, `resource_exhausted`, `access_denied`, `invalid_argument`, and `system_error`.
   3. Expose one transport table with fixed operations: runtime init/fini, poll scratch alignment/footprint, listen, accept, poll, receive, send, vectored send, close, and local-port lookup. `fd_http_server.c` calls only this table; it must no longer call `socket`, `accept4`, `poll`, `read`, `send`, `sendmsg`, or `close` directly.
   4. Change `fd_http_server_private` to store full-width `tk_http_socket_t` handles, portable poll entries, transport poll scratch, and the selected transport table. Include these allocations in `fd_http_server_footprint()`. The layout and footprint must be identical in purpose on all three hosts; Windows must not use the stub’s smaller private object.
   5. Add width-safe `fd_http_server_socket()` returning `ulong`. Keep `fd_http_server_fd()` only under Linux/macOS guards for existing allowed-FD/seccomp callers. Change the public `open` callback socket argument from `int` to the width-safe type and update all callers.
   6. Implement Windows exclusively with `WSAStartup(MAKEWORD(2,2))`, `WSASocketW(..., WSA_FLAG_NO_HANDLE_INHERIT)`, checked `SetHandleInformation`, `ioctlsocket(FIONBIO)`, `SO_EXCLUSIVEADDRUSE`, `bind`, `listen`, `accept`, `WSAPoll`, `recv`, `WSASend`, and `closesocket`. Preserve `WSAGetLastError()`. Never cast `SOCKET` through `int`, and never use the unsupported global `fd_syscall_poll()`.
   7. Balance every successful `WSAStartup` with exactly one `WSACleanup` when the HTTP server is deleted. Delete/close the listener and every accepted connection on all error and shutdown paths.
   8. Keep request parsing, response staging, ring buffers, counters, WebSocket framing, Prometheus rendering, and the stem loop in the existing Firedancer C sources. There is no Zig renderer, Windows metric tile, Windows HTTP parser, or second event loop.
   9. Make the shared engine preserve write offsets across partial sends; treat `would_block` and `interrupted` as nonfatal; close only the affected connection for reset/EOF; end the current accept pass on resource exhaustion; return `-1` from `fd_http_server_poll()` on unrecoverable listener/poll failure. Bound each accept pass by `max_connection_cnt`.
   10. Update `src/waltz/http/Local.mk` and the Zig build manifests so hosted Linux, macOS, and Windows all link `fd_http_server.c` plus exactly one Tickoni transport backend. Windows links `ws2_32`. Remove `fd_http_server_windows_stub.c` after the Windows transport test is active.
   11. After the backend passes, enable Windows in `TK_HAS_METRIC_TILE`, select `TK_METRIC_RUN`, and apply the real scratch requirements in the same change.

   **Required tests:** Add deterministic shared-engine tests with an injected fake transport for would-block, interruption, partial send, reset, accept failure, poll failure, cleanup, and balanced runtime ownership. Add native backend tests for nonblocking accept, poll readiness, exact send/receive, peer close/reset, busy port, handle cleanup, and non-inheritance. Run both tests natively on Linux, macOS x86_64/arm64, and Windows x86_64/arm64.

   **Done condition:** Windows serves the same `/metrics` implementation as Linux/macOS, no exercised Windows stub remains, and no Winsock handle or error escapes the Tickoni transport shim.

3. **High — Windows “no-hang” reap can hang shutdown.** `tryReapNoHang()` passes option `0` on Windows (`src/tickoni/util/process_api.zig:56-62`), which the C shim maps to `WaitForSingleObject(..., INFINITE)` (`src/tickoni/c_abi/shim/os.c:472-484`). A live child can block the supervisor *before* it sends HALT or reaches its timeout.

   **Implementation contract:**

   1. Delete the `options` parameter from the public process-reap path. Add this sole polling ABI to a new shared header `src/tickoni/c_abi/shim/os.h`:
      ```c
      void
      tk_process_reap_nohang( ulong                      process_token,
                              tk_process_reap_result_t * out );
      ```
      `process_token` is the PID on POSIX and the original `std.process.Child.Id` process handle on Windows. Windows process operations must not convert the handle to a PID and reopen it.
   2. Define result kinds `RUNNING`, `EXITED`, `SIGNALED`, `STOPPED`, `NO_CHILD`, and `FAILED`. The result carries `uint exit_code`, `uint signal`, `uint native_status`, a portable error category, and `uint native_error`.
   3. POSIX calls `waitpid(pid, &status, WNOHANG)`, retries only `EINTR`, maps `ECHILD` to `NO_CHILD`, and decodes all `WIF*` states inside `os.c`.
   4. Windows calls `WaitForSingleObject(handle, 0U)`. `WAIT_TIMEOUT` is `RUNNING`; `WAIT_OBJECT_0` followed by successful `GetExitCodeProcess` is `EXITED`; every API failure is `FAILED`. Preserve the full `DWORD` exit code. `INFINITE` is forbidden in this function.
   5. Remove `builtin` OS selection, numeric reap options, `eChildErrno()`, and wait-status decoding from `process_api.zig`, `os.zig`, and `os_api.zig`. Zig consumes only the semantic result.

   **Required test:** Spawn a child that remains alive for at least 30 seconds, call `tryReapNoHang()` exactly once, and assert `.running` within 250 ms while ownership remains intact. Run this natively on all supported operating systems with a two-second outer test deadline.

   **Done condition:** One no-hang poll has identical semantics on every platform and cannot block.

4. **High — shutdown can report an unconfirmed stop and lose a child.** `termProcess()` returns success even when `killProcess()` fails (`process_api.zig:30-36`). The supervisor then may set its forced flag (`src/app/tickoni/supervisor.zig:1103-1114`). It also clears a child after a failed force-phase reap (`supervisor.zig:1135-1142`), and its final wait can classify a still-running or failed reap as forced termination before clearing the child (`supervisor.zig:729-765`). `ProcessState.deinit()` clears any remaining children after its bounded loop (`supervisor.zig:165-186`). None of those outcomes proves the process was reaped.

   **Implementation contract:**

   1. Replace each nullable child slot with a descriptor-indexed `ChildRecord` containing: the child handle, ownership (`vacant`, `owned`, `reaped`, or `detached`), numeric PID for diagnostics, HALT timestamp, successful force action and timestamp, terminal observation, last portable/native reap error, and reap-error count.
   2. A record leaves `owned` only after `EXITED`, `SIGNALED`, or `NO_CHILD`. `RUNNING`, `STOPPED`, `FAILED`, HALT, timeout, and a successful termination request all retain ownership.
   3. Replace `termProcess() -> bool` with `forceTerminate() -> TerminateResult`, where the only success variant contains the exact accepted action. A failed native call returns a failure variant and stores no force action.
   4. Implement shutdown as one fixed state machine:
      - poll every owned child once, then send CNC HALT only to children still owned;
      - poll all owned children every 5 ms until one shared grace deadline;
      - poll each survivor once immediately before force; if still nonterminal, issue one force request and store only a successful action;
      - poll all survivors until one shared five-second reap deadline;
      - classify only terminal observations; never synthesize one from timeout or request success.
   5. Add `TileState.unresolved`. If any child remains owned at the final deadline, set that tile to `unresolved`, retain `ProcessState` and all child/CNC/workspace/topology resources, emit one bounded diagnostic containing tile ID, PID, HALT time, force action, last errors, and retry count, and return `error.UnresolvedChild`. A later `stopProcess()` call retries cleanup.
   6. Change `stopProcess()` to return `!void`. All callers must handle `error.UnresolvedChild`; deferred cleanup must not call `Supervisor.deinit()` while `process_state` still owns a child.
   7. Remove process signaling, waiting, and unconditional child clearing from `ProcessState.deinit()`. It becomes resource teardown only and asserts that no child is `owned`.
   8. In `refreshProcessHealth()`, switch directly on the semantic reap kind. Mark nonzero exits and unmatched signals as crashes before any CNC read. Skip CNC reads after `STOPPED` or `FAILED`; resume only after a later `RUNNING` observation. Remove the current `exit_code == 0` sentinel logic.

   **Required deterministic tests:** Use an injected process-operations seam to cover nonzero exit before force, exit between poll and force, failed force request, transient reap failure followed by success, accepted force without reap, final timeout, pre-existing crash, CNC-read suppression after failed/signaled poll, and a global rather than per-child deadline. Every test must assert both ownership and public tile state.

   **Done condition:** No code path clears a child or tears down shared memory without a terminal reap or confirmed no-child result.

5. **High — exit classification remains platform-incorrect.** Any signal after a kill request is forgiven, even if it is not the requested POSIX `SIGKILL` (`process_api.zig:43-52`; `os.c:165-168`). Windows `TerminateProcess` uses exit code `255` (`os.c:397-405`), but the same classification treats that nonzero exit as a crash. A Windows `GetExitCodeProcess()` failure instead becomes a purported exit code of `-1`, which Zig casts to `u8` (`os.c:486-492`; `process_api.zig:76-82`).

   **Implementation contract:**

   1. Define one lossless C ABI in `os.h`. `tk_process_reap_result_t` contains `kind`, full-width `uint exit_code`, `uint signal`, `uint native_status`, portable error category, and native error. `GetExitCodeProcess` failure returns `FAILED`; it never produces exit code `-1`.
   2. Add `tk_process_force_terminate(process_token, out)`. On POSIX it requests `SIGKILL` and returns action `{ signal, SIGKILL }` only after successful `kill()`. On Windows it calls `TerminateProcess` with fixed exit code `0x544B494CU` and returns action `{ exit_code, 0x544B494C }` only after success. Preserve native failures separately.
   3. Replace `std.process.Child.Term` and the `force_terminated` boolean in `process_api.zig` with project-owned `Observation`, `TerminationAction`, `PollResult`, and `ProcessOutcome` unions. Change `TileHandle.exit_code` from `u8` to `u32` and retain raw observation, successful termination action, and last process error independently of derived state.
   4. Apply exactly this classification table:

      | Observation | Matching successful action | Outcome |
      |---|---|---|
      | exit `0` | any or none | clean stop |
      | exit nonzero | same requested exit code | intentional termination |
      | exit nonzero | absent or different action | crash by exit code |
      | signal | same requested signal | intentional termination |
      | signal | absent or different signal | crash by signal |
      | stopped | any | nonterminal; ownership retained |

      HALT state, stale heartbeat, shutdown phase, and timeout never modify this table. Remove the stale-tile exception that converts a signal crash into a clean stop.
   5. Close/release Windows child process and thread handles only after a terminal observation or confirmed detach, then clear `child.id`. Do not clear handles on running, stopped, failed, timeout, or force-request success.

   **Required tests:** Cover the complete table, including mismatched POSIX signals, failed termination request, matching Windows force exit code with and without a recorded successful request, and a wide Windows exit code such as `0x12345678`.

   **Done condition:** Intentional termination requires an exact successful action recorded for that child; no native status or exit code is narrowed or fabricated.

### Portability and test boundary

- **`os.c` does keep its actual POSIX signals and `errno` handling inside the POSIX branch and Win32 process calls inside the Windows branch.** Its POSIX reap now retries `EINTR` and exposes errors (`os.c:252-283`), which is real progress.

  **Implementation contract:**

  1. Create `src/tickoni/c_abi/shim/os.h` as the single definition of process result enums, structs, and prototypes. Include it from `os.c`; delete the three duplicate `tk_process_reap_result` declarations.
  2. Keep `signal.h`, `sys/wait.h`, `errno`, `WNOHANG`, `ECHILD`, `EINTR`, `SIGKILL`, `windows.h`, `HANDLE`, `DWORD`, wait constants, and `GetLastError()` inside the guarded C implementation. None may appear in supervisor or process-domain Zig code.
  3. Map native errors in C to this fixed portable set: `none`, `access_denied`, `invalid_process`, `invalid_argument`, `resource_exhausted`, `unsupported`, and `system`. Preserve the native code only for diagnostics; Zig must not branch on it.
  4. Mirror every C struct exactly in `src/tickoni/c_abi/os.zig` and add compile-time size/alignment assertions. `src/tickoni/util/os_api.zig` re-exports semantic wrappers only.
  5. Apply project C conventions to every new shim function: Firedancer integer types, `int` booleans, return type and arguments formatted per repository style, `FD_UNLIKELY` on error paths, checked close/cleanup on every acquired resource, no `stdio` streaming, and 72-column comments.

  **Done condition:** A repository search over `process_api.zig`, `supervisor.zig`, and process integration tests finds no OS signal, wait, errno, or Win32 constants.
- **The abstraction is not complete above C.** `src/tickoni/c_abi/os.zig:163-170` hard-codes platform `ECHILD` values and gives macOS `77`; Darwin `ECHILD` is `10`. `process_api.zig` also chooses reap-option numbers by OS (`:59-62`). The supervisor does not directly invoke OS signal APIs, but it still embeds signal-based outcome policy. Its health poll misses signaled exits because `exit_code` stays zero, and it does not mark failed reaps unsafe before reading CNCs (`supervisor.zig:785-827`).

  **Implementation contract:**

  1. Delete `eChildErrno()`, `usesWaitpidReap()`, `killProcessSignal()`, all numeric signal construction, and all OS-tag branches from `process_api.zig` and `os_api.zig`.
  2. `process_api.zig` exposes exactly three process-domain operations: `tryReapNoHang(child)`, `forceTerminate(child)`, and `classify(observation, successful_action)`. It imports no `builtin` and no `std.posix`.
  3. `supervisor.zig` consumes only `PollResult`, `TerminationAction`, `ProcessError`, and `ProcessOutcome`. It never interprets native codes, signal numbers, Windows force codes, or raw status words.
  4. Health polling applies the terminal observation before touching CNC memory. `FAILED` and `STOPPED` suppress the CNC read for that pass. `RUNNING` explicitly restores permission to read CNC. `NO_CHILD` marks the public state `detached`; it is not a clean stop.
  5. Preserve raw observation, action, and error on the tile handle until the next run initializes that handle. Shutdown state updates may derive a new public state but may not erase those fields.

  **Done condition:** All platform policy is testable through semantic values without compiling an OS-specific branch in the supervisor.
- **Integration coverage does not establish cross-platform correctness.** The three metric HTTP tests now have no platform guard, so they will attempt an endpoint on Windows despite the stub. They make a single request after payment progress rather than polling HTTP readiness; the content test does not assert status 200, and the shutdown test does not assert a clean metric-child exit *after* `stopProcess()` (`test_metric_tile_integration.zig:306-363,370-411,474-512`). The process-topology test expects a `.signal` crash after a shim kill (`src/tickoni/test/integration/test_process_topology.zig:121-161`), which does not match Windows’ exit-code termination. `test_process_api.zig:97-100` explicitly excludes Windows, and its purported `EINTR` test only asserts `true` (`:328-330`).

  **Implementation contract:**

  **Process unit tests (`src/tickoni/util/test_process_api.zig`):**
  1. Replace the placeholder EINTR test with a `TK_PROCESS_TEST` C seam that returns `EINTR`, `EINTR`, then exit `7`; assert one public call returns exit `7` after three native calls.
  2. Test live-child no-hang, exit `0`, exit `42`, POSIX signal, `NO_CHILD`, non-EINTR failure, failed force request, wide Windows exit code, and the complete classification table from finding 5.
  3. Remove the file-wide Windows compile error. Mark only genuinely POSIX signal/ECHILD cases POSIX-only.

  **Supervisor unit tests:**
  1. Extract the child lifecycle state machine behind injected poll, terminate, clock, and sleep callbacks.
  2. Script and assert: nonzero exit before force; exit between poll and force; force failure; transient reap failure; accepted force without reap; matching force result; mismatched signal/result; detached child; pre-existing crash preservation; CNC-read suppression; collective deadline; and teardown blocked by one owned child.

  **Process integration tests:**
  1. Keep real-process cases for clean CNC HALT, a stuck child that is forcibly requested and then confirmed reaped, and a self-exiting child whose crash survives sibling shutdown.
  2. Remove tests that claim to simulate kill/reap failures without controlling those operations; those cases belong in the injected unit suite.
  3. Assert semantic terminal observations and tile identity, not `.signal`, in cross-platform tests.

  **Metric integration tests (`test_metric_tile_integration.zig`):**
  1. Add `waitForMetricEndpoint()` with an absolute five-second deadline. Between attempts, refresh supervisor health. On failure report port, last request error, metric tile state, raw process observation, and exit code. Connection failure is never converted to a skip.
  2. On every supported OS assert: endpoint readiness, status 200, `# HELP`, `# TYPE`, `metric_boot_timestamp_nanos > 1e18`, `metric_bytes_read > 0`, three sequential requests, one request after 100 ms idle, exact 404 for `/foo`, recovery after a client disconnects before reading, busy-port startup failure attributed to `metric`, and clean CNC HALT with no force action.
  3. Keep a Windows-only skip only until the real transport and `TK_METRIC_RUN` are enabled. Delete that skip in the same implementation change.

  **CI gate:** Run the focused C HTTP engine test, native transport test, Zig unit suite, and integration suite on native Linux x86_64/arm64, macOS x86_64/arm64, and Windows x86_64/arm64 runners. Cross-compilation is not acceptance evidence.
- **macOS HTTP socket hardening is incomplete.** Accepted-socket `fcntl()` and `SO_NOSIGPIPE` failures are unchecked (`src/waltz/http/fd_http_server.c:51-69`); a blocking socket or broken-peer `SIGPIPE` remains possible. The C metric initializer also ignores the listener return value (`src/disco/metrics/fd_metric_tile.c:155-159`), so a bind failure is not reliably surfaced as endpoint failure.

  **Implementation contract:**

  1. Remove the `__APPLE__` compatibility block and `accept4_compat()` from `fd_http_server.c`. Implement all macOS native socket behavior in `tk_http_socket_macos.c` from finding 2.
  2. Listener and accepted-socket creation are transactional. Before returning a socket, the backend must successfully complete `F_GETFL`, `F_SETFL(O_NONBLOCK)`, `F_GETFD`, `F_SETFD(FD_CLOEXEC)`, and `setsockopt(SO_NOSIGPIPE)`. On any failure, preserve `errno`, close the socket, and return a failed transport result.
  3. macOS uses `accept()`, `poll()`, `recv()`, `send()`/vectored send with flags `0`, and `close()`. It never installs a process-wide `SIGPIPE` handler. Linux continues using `SOCK_NONBLOCK`, `SOCK_CLOEXEC`, `accept4`, and `MSG_NOSIGNAL` in `tk_http_socket_linux.c`.
  4. In `fd_metric_tile.c::privileged_init()`, check `fd_http_server_new()`, `fd_http_server_join()`, and `fd_http_server_listen()` in order. Any failure terminates tile initialization with address and port in the diagnostic. A bind/listen failure must produce a nonzero child exit, never a heartbeat from an unreachable metric tile.
  5. In `before_credit()`, treat a negative `fd_http_server_poll()` result as fatal transport failure and set `charge_busy` only when the result is positive.
  6. On normal HALT, close/delete the HTTP server before the metric child exits so every listener, accepted socket, and platform runtime reference is released.

  **Required native macOS tests:** Verify listener and accepted sockets have `O_NONBLOCK`, `FD_CLOEXEC`, and `SO_NOSIGPIPE`; verify idle poll and second accept do not block; disconnect during response does not terminate the process; busy port fails initialization; and the next request succeeds after a peer reset.

One further monitoring risk is that the descriptor orders `metric` before `tkdiag` (`src/app/tickoni/topologies.zig:27-35`), while topology construction appends `metric` last (`src/tickoni/runtime/topo_build.zig:170-180`). The supervisor indexes CNC objects and child handles as though those orders match (`supervisor.zig:480-483,544-588`); metric-specific health or shutdown observations can therefore be attributed to the wrong tile.

**Implementation contract:**

1. In `topo_build.zig`, register every tile in descriptor order. Select the workspace per tile during registration: `metric` uses the metric workspace; all other tiles use the application workspace. Do not postpone metric registration until the end.
2. Replace ambiguous index arrays with descriptor-indexed records:
   ```zig
   pub const BuiltTile = struct {
       topo_tile_idx: usize,
       tile_obj_id: usize,
       cnc_obj_id: usize,
   };
   ```
   Store `BuiltTopo.tiles: []BuiltTile`, indexed only by `Topology.tiles` descriptor index. Capture the returned Firedancer tile index at registration and use it for every C topology operation.
3. Build CPU placement in Firedancer topology order. Call `topobTileUses()` with `BuiltTile.topo_tile_idx`, never the loop’s descriptor index. Resolve parent-side CNC addresses through `BuiltTile.cnc_obj_id`. Rename/remove fields such as `metric_tile_idx` whose index domain is ambiguous; use `metric_desc_idx` and `BuiltTile.topo_tile_idx` explicitly.
4. In `tile_process.zig`, treat `LaunchSpec.tile_idx` as a descriptor index, resolve the child’s tile by ID, and require that the resolved Firedancer index equals `built.tiles[spec.tile_idx].topo_tile_idx` before joining CNC or running the tile. Identity mismatch is a startup error.
5. Delete the `topobTileIn()` loop that attaches the metric tile as a reliable consumer of every application channel. The metric tile is a zero-link observer: `in_cnt == 0` and `out_cnt == 0`. Place every tile’s metrics object in `metric_in`; `fd_prometheus_render_all()` reads those objects directly.
6. In `supervisor.zig`, keep handles, child records, CNCs, health, logs, and shutdown state descriptor-indexed. Access Firedancer topology objects only through `BuiltTopo.tiles[descriptor_idx]`. No supervisor expression may index a Firedancer topology array directly with a descriptor index.

**Required tests:** Build a topology with `metric` between two generic tiles and distinct CPU placements. Assert ID mapping, CPU assignment, CNC ownership, zero metric links, unchanged application-link consumer counts, and metric scratch requirements. Start it, terminate `tkdiag`, and assert only `tkdiag` receives the PID/observation/crash/log identity while `/metrics` remains available; then stop and assert the metric child receives its own CNC HALT.

**Done condition:** Descriptor identity remains correct regardless of registration/workspace ordering, and the metric tile cannot participate in application flow control.

## Mandatory implementation order

Implement and merge the work in this order; do not enable a later stage before its preceding gate passes:

1. **Process ABI:** add `os.h`, semantic no-hang reap, exact termination-action results, portable error mapping, and C/Zig ABI size assertions. Replace the placeholder process unit tests.
2. **Process lifecycle:** add `ChildRecord`, exact classification, unresolved ownership, guarded teardown, and deterministic supervisor state-machine tests. Then update real-process integration tests.
3. **Topology identity:** introduce descriptor-indexed `BuiltTile` records, register tiles in descriptor order, remove metric application-link inputs, and add mapping/CNC/CPU/zero-link tests.
4. **Metric layout:** add `TK_HAS_METRIC_TILE`, shared alignment/footprint requirements, topology properties, and finalized-layout validation. Linux and macOS must pass the exact-layout tests before continuing.
5. **HTTP transport boundary:** add the portable `tk_http_socket` interface, convert `fd_http_server.c` to it, preserve full-width socket handles, and pass fake-transport shared-engine tests.
6. **Native transports:** implement and pass Linux and macOS backend tests, then implement and pass Windows Winsock tests. Complete macOS transactional socket setup and metric listener failure handling in this stage.
7. **Windows activation:** remove the Windows stub, link `ws2_32`, enable Windows in `TK_HAS_METRIC_TILE`, dispatch Windows metric children through `TK_METRIC_RUN`, and apply the real scratch requirements in the same change.
8. **Integration acceptance:** run endpoint readiness, content, 404, repeated/idle request, disconnect, port collision, topology identity, clean HALT, and process ownership tests on every native CI architecture.

A stage is incomplete if its tests compile but are skipped on the target platform.

## Final acceptance criteria

The remediation is complete only when all conditions below hold:

1. Linux, macOS, and Windows execute the same Firedancer C metric tile, stem loop, Prometheus renderer, and shared HTTP protocol engine.
2. Native socket/readiness/error behavior exists only in the Tickoni C transport shims; no socket handle is narrowed and no native error constant is interpreted in Zig.
3. Every metric tile receives validated scratch alignment and footprint before child startup.
4. The metric tile has zero application links and cannot add flow-control consumers to the payment pipeline.
5. Descriptor tile ID, Firedancer tile index, CNC, child process, health, logs, and shutdown result remain correctly associated for every topology order.
6. One process no-hang poll returns promptly on every OS; no Windows wait uses `INFINITE` in the polling path.
7. Child ownership is released only by terminal reap or confirmed no-child; timeout and force-request success never fabricate an exit.
8. Intentional termination requires an exact successful action recorded for that child. Nonzero ordinary exits and unmatched signals remain crashes.
9. Shared memory and topology resources are not destroyed while any child remains owned or unresolved.
10. Native Linux x86_64/arm64, macOS x86_64/arm64, and Windows x86_64/arm64 runners execute all focused C tests, Zig unit tests, and integration tests with no metric-platform skips.

## Assessment by plan

- `metric-tile-macos-support.md`: **partially wired but unsafe**.
- `metric-tile-windows-support.md`: **not implemented**.
- `process-shutdown-reap-correctness.md`: **partially implemented**.

These conclusions are source-review findings. Native macOS and Windows runtime validation has not yet been performed.
