# Contributing to Tickoni

Tickoni is a financial event runtime first and an AI harness second. The
repository combines Tickoni-owned Zig product and runtime code, a retained
Firedancer-derived C substrate, and a separately licensed Qt desktop terminal.

The runtime, CLI, APIs, SDKs, and retained C substrate are generally licensed
under Apache-2.0. The official Qt desktop terminal is licensed under
GPL-3.0-only. Tickoni creative content is governed separately by
CONTENT-LICENSE.md.

This file is the repository entry point.  Detailed rules live in:

- the [Tickoni contributor guide](doc/execution/contribution/tickoni.md) for
  Tickoni-owned Zig, schemas, codecs, tiles, supervisors, connectors, audit,
  replay, and product behavior;
- the [Firedancer contributor guide](doc/execution/contribution/firedancer.md)
  for retained C substrate, topology, Tango, workspaces, sandboxing, C style,
  portability, fuzzing, and C-specific testing.
- the [Qt terminal architecture decision](doc/knowledge/rant/qt-for-terminal-ui.md)
  for the GPL-3.0-only desktop terminal, Qt/QML/C++ boundaries, CMake,
  packaging, and Qt-specific licensing requirements;
- [LICENSING.md](LICENSING.md) for the repository-wide license map;
- [CONTENT-LICENSE.md](CONTENT-LICENSE.md) for Tickoni lore, characters,
  narratives, illustrations, and release artwork.

A change that spans both runtimes must satisfy both guides.

## Choose The Contribution Path

### Tickoni-owned code

Use the Tickoni guide for `src/app/tickoni`, `src/tickoni/**`, Tickoni tests and
fixtures, Tickoni documentation, and `justfile` recipes.

| Change | Destination |
| --- | --- |
| Supervisor, lifecycle, topology, channels, metrics, replay hooks, sandbox configuration | `src/tickoni/runtime/` |
| Narrow Zig declarations and wrappers around retained C substrate | `src/tickoni/c_abi/` |
| Canonical cross-tile financial, policy, audit, case, and capability contracts | `src/tickoni/schema/` |
| Binary, JSONL, protobuf, and hash codecs for canonical contracts | `src/tickoni/codec/` |
| Tile-owned state, messages, validation, backends, and orchestration | `src/tickoni/tiles/<tile>/` |
| Signed adapter manifests and external integration code | `src/tickoni/connectors/` |
| Deterministic demo orchestration | `src/tickoni/test/demo/` |
| Test-only mocks and servers | `src/tickoni/test/mocks/` |
| Financial fixtures and scenarios | `src/tickoni/test/fixtures/` |
| Qt desktop terminal, QML, C++ UI models, terminal transport, terminal CMake, UI tests | `src/tickoni/ui/` |

### Qt desktop terminal

Use the Qt terminal ADR and terminal-specific contributor documentation for:

- `src/tickoni/ui/**`;
- terminal-specific C++ and QML source;
- terminal-specific CMake files;
- terminal tests, resources, packaging, and deployment files;
- files otherwise expressly marked `GPL-3.0-only`.

The official Qt desktop terminal is licensed under GPL-3.0-only.

Keep the GPL terminal separate from the Apache-2.0 runtime, CLI, APIs, schemas,
and non-UI SDKs. Shared protocol definitions and generated clients should live
in their Apache-2.0 component rather than being implemented only inside the
terminal.

Do not copy GPL-covered terminal implementation code into an Apache-2.0
component. Apache-2.0 code may be used by the GPL terminal when its original
copyright, license, attribution, and modification notices are preserved.

### Firedancer-derived C substrate

Use the Firedancer guide for retained low-level C code, including `src/tango`,
`src/util`, `src/waltz`, `src/disco`, `src/discof`, `src/flamenco`, `src/funk`,
and `src/app/firedancer`.

Tickoni product requirements do not by themselves justify modifying this
substrate.  Prefer a Tickoni-owned module or a narrow boundary under
`src/tickoni/c_abi`.  A substrate change should be genuinely generic and must
follow the Firedancer ownership, memory, isolation, performance, C style, and
testing rules.

### Cross-boundary changes

A Zig-to-C dependency crosses a Tickoni-owned boundary:

1. Add or use a narrow `tk_*` C shim under `src/tickoni/c_abi/shim/**`.
2. Add a typed wrapper under `src/tickoni/c_abi/*.zig` when Zig needs it.
3. Pass primitive configuration, pointers, footprints, handles, and status.
4. Keep Tickoni product structs and financial semantics out of the C substrate.
5. Preserve the C object's ownership and lifecycle, including
   `align`, `footprint`, `new`, `join`, `leave`, and `delete` where applicable.

Do not call retained `fd_*` APIs directly from Tickoni product code, invent
linkage stubs to hide an unhealthy boundary, or place business-adjacent C code
in the ABI directory merely because Zig calls it through `extern`.

# Contribution Licensing

Tickoni is a mixed-license repository. Contributions are licensed according to the component they modify:

* Apache-2.0 for the runtime, CLI, retained C substrate, APIs, schemas, non-UI SDKs, and other Apache-2.0-designated files;
* GPL-3.0-only for `src/tickoni/ui/**` and other GPL-3.0-only-designated files.

Existing third-party code remains under its existing license. Contributors must have the legal right to submit their contributions and must preserve applicable copyright, license, attribution, NOTICE, SPDX, and modification notices.

Changes that move or copy material across Apache-2.0, GPL-3.0-only, or creative-content boundaries require explicit licensing review.

## Creative Content Contributions

Tickoni lore, characters, narrative releases, illustrations, comics, and related creative assets are maintained in the separate `tickoni-content` repository.

Do not submit fictional lore, character designs, character biographies,
narrative material, dialogue, illustrations, comic or manga material, or
release artwork through ordinary pull requests.

Creative-content contributions require a separate written agreement confirming:

- the contributor's authorship or authority to submit the material;
- ownership of the relevant rights;
- any third-party or generated-material inputs;
- the rights granted to Victor Genin, publishing under the name DeepRND;
- whether the material may be modified, commercially licensed, sublicensed,
  registered, or enforced by the Licensor.

Opening a pull request containing creative content does not by itself establish
that the contribution has been accepted or that the required rights have been
granted.

## Architectural Rules

The implementation order is:

```text
runtime first
cases second
agents third
privileged actions last
```

The deterministic financial event path must not require a model.  Events should
remain ingestible, normalizable, deduplicated, policy-checkable, auditable, and
replayable without agent or model execution.

For every non-trivial runtime change, make these facts explicit:

1. Which tile or module owns the state?
2. Which workspace or bounded allocation holds it?
3. Which process may access it, and in what mode?
4. Who writes each shared field?
5. What happens on malformed input, backpressure, overrun, restart, and
   shutdown?
6. Which metrics, diagnostics, audit records, or logs expose unhealthy
   behavior?

Preserve these defaults:

- explicit topology over runtime discovery;
- fixed capacity over unbounded growth;
- one writer for hot mutable state;
- bounded channels over generic event buses;
- process isolation over in-process trust;
- fail-closed validation for configuration and authority;
- audit and deterministic replay for material behavior;
- no hidden allocation, threads, registries, permissions, or external calls.

Agents are not the security boundary.  Model access belongs behind `tkmodl`,
tool access behind `tktool`, external integrations behind signed `tkadpt`
instances, and money-adjacent mutation behind `tkexec`.  Replay must not invoke
production mutation.

Before implementing a new tile, link, or meaningful runtime behavior, define
its runtime ID, owned state, links, queue depth, MTU, reliability, access modes,
fixed memory, process placement, restart behavior, overrun behavior, shutdown
behavior, metrics, diagnostics, audit, and replay impact.

Resolve ownership or source-tree ambiguity before coding.  Do not let a helper
quietly become an execution owner, storage authority, service locator, or
privileged boundary.

## Development Workflow

1. Read the relevant detailed contributor guide.
2. Identify the owning module, tile, process, and storage boundary.
3. Make the smallest coherent change that preserves those boundaries.
4. Add or update tests for the behavior being claimed.
5. Update architecture, schema, telemetry, testing, or operator documentation
   when the effective contract changes.
6. Run the narrowest relevant checks first, then broaden based on risk.
7. In the handoff or pull request, list the checks run and identify any
   relevant checks not run.

All Tickoni developer tooling belongs in the root `justfile` or in
Tickoni-specific scripts called by it.  Do not add Tickoni development targets
to retained Firedancer makefiles.  Use the existing recipe naming convention:
`tk` for Tickoni, `fd` for Firedancer-derived C, and `all` for composed checks.
Do not implement fake success paths when a check is unavailable.

## Testing

Treat the root `justfile` and the repository testing guide as the source of
truth for available test layers and commands.

Run the narrowest relevant command first:

- `just test-unit-tk` for Tickoni Zig supervisor, topology, queue, sandbox,
  C ABI wrapper, schema, codec, or tile behavior;
- `just test-unit-fd` for retained C substrate, Tango, Disco, Discof, Waltz,
  utilities, and C integration behavior;
- `just test-unit-all` for changes crossing the Zig/C boundary;
- `just test-e2e-fd` for topology, workspace setup, process startup, or the
  Firedancer development path;
- `just test-all` or `just tests-all` for broad local validation before a
  risky handoff.

Match the test layer to the risk:

- unit tests isolate a function, module, tile helper, wrapper, or supervisor;
- integration tests keep Tickoni internals real and substitute only the
  external boundary;
- end-to-end and system tests use the real local runtime path and avoid
  internal mocks.

Runtime and boundary changes should test successful behavior and important
fail-closed cases.  Depending on the change, cover malformed input, duplicate
handling, bounded queues, backpressure, overrun, workspace join modes, missing
shared-memory objects, sandbox failure, tile crash, audit chaining, replay
divergence, policy allow and deny outcomes, and configuration validation.

Do not silently fall back from a real integration backend to a mock.  If a real
service is unavailable, use the repository's explicit skip behavior.

## Compatibility And Documentation

Treat schemas, audit formats, replay inputs, topology, C ABI layouts,
configuration, metrics, diagnostics, and external routes as compatibility
surfaces.

When changing one of them:

- update the owning documentation in the same change;
- preserve explicit versions and bounded representations;
- add layout or constant checks at C ABI boundaries;
- report effective runtime behavior, not only configured intent;
- keep metric names and labels stable and low-cardinality;
- place high-cardinality identifiers in logs, audit records, evidence, or
  bounded trace attributes rather than metric labels;
- regenerate derived outputs using the applicable contributor guide.

Use consumer-money language in product-facing documentation, APIs, and demos.
Keep tile IDs, capability envelopes, audit records, replay capsules, adapter
manifests, and signed action envelopes as internal implementation terminology.

## Pull Request Checklist

Before requesting review, verify that the contribution:

- belongs in its chosen module or substrate path;
- gives every mutable object one clear owner;
- makes capacities, payload bounds, and allocation explicit;
- keeps process, sandbox, filesystem, network, model, tool, adapter, storage,
  and execution permissions narrow;
- defines malformed-input, overrun, restart, and shutdown behavior;
- makes material decisions, denials, and external results auditable;
- supports replay comparison without external mutation;
- exposes relevant lag, drops, backpressure, crashes, and divergence through
  metrics or diagnostics;
- includes tests matching the actual risk;
- documents which checks were and were not run.
- is submitted under the license applicable to every modified file;
- preserves existing copyright, SPDX, license, attribution, NOTICE, and
  modification notices;
- does not copy GPL-covered terminal code into an Apache-2.0 component;
- does not embed separately licensed lore or character assets into the GPL
  terminal without an explicit licensing review;
- identifies every new third-party dependency and its license;
- updates `LICENSING.md`, `NOTICE`, third-party notices, or the SBOM when the
  distributed dependency or licensing boundary changes.

Also verify that the change does not:

- add Tickoni product semantics to retained Firedancer paths;
- introduce a hidden mutable global registry or service locator;
- add an unbounded queue or steady-state allocation without a bounded design;
- let multiple tiles mutate state without a documented ownership protocol;
- bypass `tkmodl`, `tktool`, `tkadpt`, `tkexec`, storage, audit, or replay
  boundaries;
- suppress formatter, lint, sanitizer, seccomp, test, or static-analysis
  findings instead of fixing the underlying issue;
- claim durability before the owning durable store or append-only audit path
  has accepted the data.
- silently move code or assets across Apache-2.0, GPL-3.0-only, or
  creative-content boundaries;
- introduce a dependency whose license is incompatible with the destination
  component;
- remove an upstream copyright, license, attribution, or modification notice.

If a relevant check cannot be run, state that directly and explain the missing
environment, dependency, or scope.
