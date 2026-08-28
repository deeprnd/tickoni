# Tickoni Security

This document summarizes Tickoni's security model and the repo security
checks exposed through the `justfile`.

Tickoni retains a Firedancer-derived runtime foundation. Agent harness code
should live above that foundation instead of being mixed into low-level
networking, shared-memory channel, tile runtime, or kernel-interface code.

The rule is:

```text
keep agent harness code above the engine boundary unless a reviewed runtime
change is necessary
```

## Security Model

Tickoni assumes agents are not inherently trustworthy.

Security posture:

- agents are untrusted by default
- tools are capability-scoped
- production actions require policy checks
- money-impacting actions require approval
- secrets are never exposed directly to agents
- audit records are immutable
- deleted history is not allowed
- policy decisions are logged
- denied actions are logged
- replay divergence is treated as a serious event

Phase 0 currently runs a synthetic payment pipeline in dev/test mode. It proves
bounded queues, stable event hashes, append-only audit records, replay checks,
observable backpressure, and crash diagnostics. It does not yet grant agents
tool authority or privileged external actions.

## Secure Coding Guidelines

These are financial-industry-baseline coding rules. They apply to every
change in this repository, not only to tile/agent boundary code. They restate
and expand the Security Posture constraints in `CLAUDE.md` into concrete
checks a contributor or reviewer can apply line by line.

### Input Validation

- Treat every value crossing a trust boundary as untrusted until validated:
  HTTP/WebSocket payloads, environment variables, config files, financial
  event payloads, CLI arguments, model/tool/adapter responses, and any
  `tango`-channel payload produced by a tile that does not fully trust its
  producer.
- Check every field for null/absent, for zero where zero is not a valid
  domain value (amounts, notional, quantities, timestamps, ids), and for
  out-of-range or out-of-bounds values before it is used in a computation,
  state transition, or persistence.
- Validate length and encoding of string/byte fields before use. Reject input
  that does not fit a declared fixed-size buffer or capacity; do not truncate
  silently.
- Do not assume a field is valid just because it decoded successfully. Decode
  success proves shape, not semantic correctness — range, cross-field
  consistency, and identifier consistency still need explicit checks.
- Reject partial, ambiguous, or malformed records explicitly and fail closed
  rather than substituting a default value or a best-effort guess.

### Output And Error Checking

- Check the return value or error union of every call that can fail —
  allocator calls, syscalls, C ABI wrapper calls, codec calls — before using
  the result. Do not discard a Zig error union with `catch unreachable`
  unless the unreachable state is actually provable, not merely assumed.
- Do not assume a callee's output is well-formed because the call returned
  without an error. Validate pointers, lengths, and footprints a C function
  actually returns before dereferencing or copying them, especially across
  the `src/tickoni/c_abi` boundary; a null or zero-value output where a
  positive value is expected is a failure, not a valid edge case.
- Never let an unchecked or ignored error keep propagating into persistence,
  audit, or an external adapter call. Follow the Error Handling rules in
  `doc/execution/contribution/tickoni.md`: log with useful identifiers, then
  rethrow or translate at the correct boundary instead of swallowing it.

### Don't Trust User Input

- User-supplied identifiers, amounts, addresses, venues, and free-text fields
  must never be interpolated directly into a query, shell command, log format
  string, or file path without validation.
- Model responses and tool/adapter responses are untrusted input, not trusted
  internal data. Validate their shape against the expected schema before
  using them for a policy or execution decision.
- Do not trust client-declared content length, content type, or protocol
  version; verify against what the codec/HTTP layer actually parsed.

### No Elevated Permissions

- Tile processes must run with the least privilege their one responsibility
  needs: dropped capabilities, a minimal seccomp syscall allowlist, and
  Landlock/filesystem restriction, following the existing `privileged_init`
  → capability drop → seccomp install → tile run loop ordering.
- Do not add a code path that requires running as root, disabling seccomp,
  widening a tile's syscall allowlist, or granting a tile filesystem/network
  access it does not need. Treat that as a runtime-foundation change that
  requires explicit review, per Ask Before You Change in `CLAUDE.md`.
- Dev/test convenience such as thread-mode tiles or relaxed sandboxing must
  never leak into a production code path; keep the two modes explicit and
  distinguishable in logs and metrics.

### Deny By Default

- Capability and policy checks must start from `deny` and enumerate exactly
  what is `allow`ed or `require_approval`. Do not build permission logic by
  exclusion — denying a list of bad things and allowing everything else.
- Missing configuration, missing required environment variables, and
  unrecognized capability or action names must resolve to `deny`, never to a
  default-allow fallback.
- New tile links, HTTP routes, and adapter/tool capabilities must be
  explicitly declared before they are reachable. Nothing should become
  callable purely because the underlying function exists.

### Static, Preallocated Memory (Critical-Systems Discipline)

Tickoni follows the same discipline Firedancer already applies to the
ultra-TPS event path, and the same discipline critical/industrial systems
(avionics, control systems) apply to memory: capacity is a build- or
config-time property, proven by construction. A memory or stack overflow must
be impossible by design, not merely unobserved so far in testing.

- Compute every buffer's size (`footprint`) from topology/config at startup —
  channel depth, MTU, replay cap, scratch size — and allocate it once, before
  a tile enters its run loop. No allocator call should occur in the
  steady-state hot path.
- Prefer static, workspace/scratch-backed layout (`FD_LAYOUT_*`,
  `scratch_align`/`scratch_footprint`, Zig comptime-sized arrays and
  fixed-capacity buffers) over runtime-growable containers (`ArrayList`,
  dynamic `HashMap`, `malloc`/`realloc` in a loop) for anything on the event,
  policy, audit, or replay path.
- Every loop, buffer, and recursion depth on the hot path must have a fixed,
  computable upper bound derived from configuration or a comptime constant —
  not an assumption inferred from what traffic happened to look like during
  testing. "It hasn't overflowed yet" is not an acceptable bound.
- When capacity is genuinely exceeded (queue full, buffer full, depth
  exceeded), the correct behavior is a bounded, observable failure —
  backpressure, explicit rejection, or a counted/audited drop — never a
  silent grow, an on-demand allocation to "make it fit," or silent
  truncation.
- If a config value determines a footprint, validate it against overflow and
  against the maximum representable/allowed size before it sizes an
  allocation; reject the config at startup instead of allocating an
  under- or oversized buffer.
- Allocation is acceptable only for genuinely one-time startup/init work
  (supervisor bring-up, topology construction, test harnesses) or explicitly
  out-of-band, non-hot-path tooling — never inside a tile's per-event or
  per-request run loop.

No-nos:

- Do not allocate per event, per request, or per message inside a tile's run
  loop, even for something that looks small or short-lived.
- Do not grow a queue, buffer, or cache at runtime because a consumer fell
  behind, traffic spiked, or a fixed limit felt inconvenient. Resize the
  configured capacity instead, deliberately, as a reviewed config change.
- Do not hide an allocation inside a helper (parse/hash/enqueue/format) whose
  caller assumes it is allocation-free — that hides the capacity limit a
  reviewer needs in order to reason about overflow risk.
- Do not size a stack array, heap buffer, or recursion bound from an
  unvalidated runtime value with no fixed upper bound. A value influenced by
  external input must be clamped or rejected against a compile-time or
  config-time maximum before it can affect a buffer's size or a loop's bound.

### C/Zig Memory And Stack Safety

Tickoni mixes Zig runtime code with retained Firedancer C substrate. Memory
and stack bugs at that boundary are security bugs, not just correctness bugs,
because they run in a process handling financial events. See
[Memory And Allocation](contribution/tickoni.md) and
[C ABI Rules](contribution/tickoni.md) for the general style rules this
section restates with a security lens.

Best practices:

- Size every stack-resident and fixed-capacity buffer from a comptime
  constant or a validated configured limit, and check the actual input
  length against that capacity before copying — never write past a fixed
  buffer or assume an input length matches a declared field.
- Use slices (`[]T`, `[]const u8`) with their bound length instead of raw
  pointers plus a separately-tracked length; let the slice carry its own
  bound so a copy/compare/index cannot silently drift out of sync with it.
- Keep one clear owner per allocation and free it through `defer`/`errdefer`
  at the scope that owns it, mirroring the C `new`/`join`/`leave`/`delete`
  lifecycle for C-owned objects instead of inventing a Zig-side lifetime for
  them.
- Validate `extern struct` size, alignment, and field offsets with a test
  (`@sizeOf`, `@alignOf`, `@offsetOf`) whenever the struct mirrors a C layout,
  so an ABI drift shows up as a failing test, not a corrupted read.
- Keep recursive parsing/decoding of externally-sourced or nested data
  explicitly depth-bounded; unbounded recursion on attacker-controlled nesting
  is a stack-exhaustion vector, not just a style issue.
- Run and keep passing `security-sanitize-check-fd` (Clang ASan+UBSan) and
  `security-sanitize-check-tk` (`zig build test -Doptimize=ReleaseSafe`) for
  any change that touches parsing, codecs, the C ABI membrane, or pointer
  arithmetic; treat a sanitizer or safety-check crash as a real bug to fix,
  never noise to route around.

No-nos:

- Do not use `@ptrCast`/`@alignCast` across the C ABI boundary without a
  proven, tested alignment/layout match; do not let `anyopaque` escape into
  product tile code when a narrower typed representation is possible.
- Do not use `catch unreachable` or `orelse unreachable` on a value derived
  from external/untrusted input; reserve `unreachable` for states the code
  actually proves cannot occur.
- Do not use `@intCast`/`@truncate` on a length, offset, or size field derived
  from external input without a prior explicit range check — a silent
  truncation there becomes an undersized allocation or an out-of-bounds copy.
- Do not leave a field `undefined` across a boundary where it may be read
  before it is written, and do not read a C-owned pointer/slice after the
  call that owns it reports `leave`/`delete`/free.
- Do not disable, weaken, or work around stack protection, ASan/UBSan, or
  Zig's runtime safety checks (bounds, overflow, alignment) to make code build
  or pass tests faster; fix the underlying bug instead, per the existing
  no-bypass rule in `contribution/tickoni.md`.
- Do not introduce hidden allocation inside parse/hash/enqueue helpers or
  unbounded growth (`ArrayList` growth, recursive buffers) in a steady-state
  or hot path — both hide the capacity limit a reviewer needs to reason about
  denial-of-service exposure.
- Do not mix ownership: never free memory with an allocator other than the
  one that produced it, and never store a pointer to stack-local memory
  beyond the function's return.

## Isolation Boundary

Tickoni follows Firedancer's process-oriented isolation principles. The Phase 0
implementation still runs tiles as in-process Zig threads for spike and test
simplicity, but the architecture remains tile-shaped:

```text
tkings -> tknorm -> tkdedu -> tkpoly -> tkaudt
                         \-> tkrepl / tkmetr / tkdiag
```

Each future process tile must have:

- one responsibility
- owned mutable state
- bounded resources
- explicit capabilities
- no shared mutable state outside designated channels
- crash-only failure behavior

Runtime-foundation changes require explicit review. They are not routine
agent-harness implementation work.

## Commands

Security check entrypoints:

- `just security-gitleaks-check-fd`
- `just security-gitleaks-check-tk`
- `just security-gitleaks-check-all`
- `just security-codeql-check-fd`
- `just security-codeql-check-tk`
- `just security-codeql-check-all`
- `just security-seccomp-check-fd`
- `just security-seccomp-check-tk`
- `just security-seccomp-check-all`
- `just security-proof-check-fd`
- `just security-proof-check-tk`
- `just security-proof-check-all`
- `just security-sanitize-check-fd`
- `just security-sanitize-check-tk`
- `just security-sanitize-check-all`
- `just security-check-all`

`security-check-all` currently runs the all-variants in this order:

1. `security-codeql-check-all`
2. `security-gitleaks-check-all`
3. `security-seccomp-check-all`
4. `security-proof-check-all`
5. `security-sanitize-check-all`

The aggregate command is badge-wrapped through
`contrib/tool/readme/run-badged-command.py` so README security status is updated by
the same command developers run locally.

## Scanner Scope

Gitleaks:

- `security-gitleaks-check-fd` scans `src/` with
  `contrib/security/gitleaks-fd.toml`
- `security-gitleaks-check-tk` scans `src/tickoni` and `src/app/tickoni`

CodeQL:

- the `just` CodeQL recipes are currently no-ops
- `security-codeql-check-fd` documents the blocked local path and points at the
  open Firedancer issue in the `justfile`
- the real implementation remains in `contrib/security/security.sh codeql-check-fd`
  for when that path is re-enabled

Seccomp:

- `security-seccomp-check-fd` is currently a no-op in the `justfile`
- the real script command is `contrib/security/security.sh seccomp-check-fd`
- Tickoni-owned Zig code has no active seccomp policy checker yet

Proof:

- `security-proof-check-fd` runs `./contrib/build/make-j proof`
- `security-proof-check-tk` is currently a no-op because there is no Zig proof
  harness yet

Sanitizers:

- `security-sanitize-check-fd` builds and checks the Firedancer-derived
  `tickoni` target with Clang ASan + UBSan in `build/clang-asan-ubsan`
- `security-sanitize-check-tk` runs `zig build test -Doptimize=ReleaseSafe`

## Local Expectations

Install developer Python tooling before running quality or security gates:

```bash
just python-dev-install
```

The optional wider Python surface is:

```bash
just python-dev-install-all
```

Security tools such as `gitleaks`, `codeql`, and CBMC-related proof tooling must
be installed by the developer or CI image when their corresponding non-no-op
commands are used. Scripts under `contrib/security/security.sh` intentionally run real
commands and fail if required tools are absent.

## Agent Capability Boundary

Every tool request must resolve to an agent identity, case scope, policy
version, and explicit capability. Model-native function calls and MCP-compatible
requests are untrusted input until the broker validates that envelope.

High-impact actions are proposals routed to a separate privileged executor.
Policy can constrain action type, resource scope, value, rate, environment, and
required approval before any downstream change is executed.

Example capability shape:

```yaml
agent: payment_exception_agent
environment: production

allowed:
  - read_payment_event
  - read_processor_log
  - read_case_history
  - draft_merchant_response
  - propose_retry_path
  - route_case

requires_approval:
  - send_merchant_response
  - retry_payment
  - change_payment_route

denied:
  - release_payout
  - post_ledger_adjustment
  - freeze_account
  - approve_refund
  - delete_audit_record
```

## Related Docs

- [Development](development.md)
- [Tickoni Testing](testing-tickoni.md)
- [Observability](observability.md)
- [Contribution Guide](contribution/tickoni.md)
