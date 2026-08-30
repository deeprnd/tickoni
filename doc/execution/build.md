Build
=====

This page describes the Tickoni-owned build entry points, with emphasis on the
Zig build for Tickoni-owned components.

For the Firedancer / C build, see
[Build System](../build-system.md).

The repository currently has two underlying build systems plus one repo-facing
wrapper:

- `just ...` as the repo-facing wrapper for common build and test flows
- Firedancer-side builds and tests via `just build-fd`, `just build-fd-dev`,
  and `just test-e2e-fd`
- qualified `just build-tk-*` and `just test-unit-tk-*` recipes for Tickoni's
  Zig supervisor and harness unit tests; Zig is an implementation detail

Quick start
-----------

Before building, install platform-specific tooling:

```bash
just setup-env
```

This installs Zig, the system compiler, make, gitleaks, shellcheck, pre-commit, buf, Firedancer deps, and everything else a lane needs. See [contrib/setup/](../../contrib/setup/README.md) for lane details.

Setup
~~~~~

Platform-specific tooling is installed by `just setup-env`, which
auto-detects your platform and runs the appropriate script. Each lane has its
own script so developer and CI installs are provably identical:

| Command | Platform | Arch | Compiler |
|---|---|---|---|
| `just setup-linux-x86-gcc` | Linux | x86_64 | gcc-12 |
| `just setup-linux-x86-clang` | Linux | x86_64 | clang-18 |
| `just setup-linux-arm-gcc` | Linux | aarch64 | gcc-14 |
| `just setup-macos-x86` | macOS | x86_64 | clang (Xcode) |
| `just setup-macos-arm` | macOS | arm64 | clang (Xcode) |
| `just setup-windows-x86` | Windows | x86_64 | clang (LLVM) |
| `just setup-windows-arm` | Windows | arm64 | clang (LLVM) |

Every lane script installs Zig (from `contrib/setup/zig-version`), a system
compiler, build tools, Firedancer deps, and quality tooling. Scripts are
idempotent — re-running is a no-op.

See [contrib/setup/README.md](../../contrib/setup/README.md) for details.

Build the Tickoni-owned Zig supervisor:

```bash
just build-tk
```

Run the supervisor:

```bash
zig build run -- start
```

Run harness unit tests:

```bash
just test-unit-tk
```

Build the Firedancer-derived `tickoni` runtime binary:

```bash
just build-fd
```

Build the Firedancer dev binary:

```bash
just build-fd-dev
```

Run Firedancer-side e2e/system tests:

```bash
just test-e2e-fd
```

Build the combined default surface:

```bash
just build-all
```

For the Firedancer-side Make targets and their build model, see
[Build System](../build-system.md).

Build process
-------------

The Zig side is much smaller than the Firedancer Make build described in
[Build System](../build-system.md).

The figure below describes the current Tickoni Zig build graph.

```
┌───────────────────────┐
│ src/tickoni/runtime/* │
└───────────┬───────────┘
            │ addModule("runtime")
            │
┌─────────────────────┐ │
│ src/tickoni/tiles/* │ │
└───────────┬─────────┘ │
            │ addModule("tiles")
            │
            └───────────────┬─────────────────────────────┐
                            │                             │
                            │ imports                     │ imports
                            │                             │
                  ┌─────────▼──────────┐        ┌────────▼─────────┐
                  │ src/app/tickoni/   │        │ src/app/tickoni/ │
                  │ main.zig           │        │ supervisor.zig   │
                  └─────────┬──────────┘        └────────┬─────────┘
                            │ addExecutable               │ addTest
                            │                             │
                    ┌───────▼────────┐          ┌────────▼─────────┐
                    │ tickoni-       │          │ supervisor test  │
                    │ supervisor     │          │ binary           │
                    └───────┬────────┘          └──────────────────┘
                            │
                            │ install / run
                            │
                    ┌───────▼────────┐
                    │ zig-out/bin/   │
                    │ tickoni-       │
                    │ supervisor     │
                    └────────────────┘

Standalone Zig test roots:
  - src/tickoni/runtime/topology.zig
  - src/tickoni/runtime/tile.zig
  - src/tickoni/c_abi/queue.zig
  - src/tickoni/c_abi/sandbox.zig
  - src/tickoni/tiles/payment_pipeline.zig
```

Structure
---------

The current build graph in [build.zig](../../build.zig) has three main parts:

1. Shared modules:
   - `runtime` from `src/tickoni/runtime/runtime.zig`
   - `tiles` from `src/tickoni/tiles/payment_pipeline.zig`
2. Supervisor executable:
   - `src/app/tickoni/main.zig`
   - output binary: `tickoni-supervisor`
3. Zig tests:
   - standalone test roots under `src/tickoni/...`
   - one extra test binary for `src/app/tickoni/supervisor.zig`

The executable currently exposes:

- `zig build run -- start`
- `zig build run -- status`

Scope
-----

This Zig build is intentionally separate from the Firedancer-side build.
It does not replace:

- `just build-fd`
- `just build-fd-dev`
- `just test-e2e-fd`

Those repo-facing commands are covered by the Firedancer-side build described in
[Build System](../build-system.md). The reason the Firedancer Make
The `integration-test` target is surfaced as `just test-e2e-fd`, which is
documented in
[Testing](../testing.md).

Instead, it builds the Tickoni-owned supervisor layer around the
Firedancer-derived substrate. The `just` wrapper keeps that split
explicit: `just build-tk` drives the Zig supervisor build, `just build-fd`
and `just build-fd-dev` drive the Firedancer-side builds, and
`just build-all` composes the default combined build.

Output locations
----------------

By default, Zig installs artifacts under `zig-out/`.

The current executable path is:

```text
zig-out/bin/tickoni-supervisor
```

When to use which build
-----------------------

Use the Zig build when you are working on:

- `src/app/tickoni/`
- `src/tickoni/runtime/`
- `src/tickoni/tiles/`
- `src/tickoni/c_abi/`

Use the Firedancer-side build when you are working on:

- `src/disco/`
- `src/waltz/`
- `src/tango/`
- `src/util/`
- `src/ballet/`

Those trees are compiled via the `tickoni_fd` machine profile, which scopes
the Firedancer build to only the 5 libraries Tickoni reuses.

That workflow is documented in [Build Engine](../build-system.md).

Related docs
------------

- [Development](./development.md)
- [Testing](./testing-tickoni.md)
- [Security](./security.md)
- [Observability](./observability.md)
- [Telemetry](./telemetry.md)
