---

> **Superseded by platform parity (2026-11-24).** Windows, macOS and Linux, on
> x86_64 and ARM64, now have the same functionality; see
> [`platform-tiers.md`](../platform-tiers.md). The Linux full-runtime / retail
> tier split, Linux-only paths and per-OS fallbacks described here no longer
> apply, and Linux-only features are postponed to a future server-only
> version. Kept as history.
author: deeprnd
date: 2026-07-03
---

# ADR-01: Firedancer orchestration reuse

**Q: Tickoni needs process-mode tile orchestration, shared-memory link
joining, sandbox setup, lifecycle checks, and metrics/heartbeat discipline.
Firedancer already has much of that machinery. Should Tickoni build a
parallel architecture, fully reuse Firedancer's validator harness, or use a
thin Tickoni-owned adapter over the reusable parts?**

There are three real options, and they are different enough that the decision
should be explicit.

**Option 1: build a parallel Tickoni orchestration architecture.** Tickoni
keeps its own supervisor, launch record, topology structs, tile registry, link
join logic, lifecycle loop, heartbeat handling, sandbox setup, metrics mapping,
and process management, while using only low-level Firedancer primitives such
as `mcache`, `dcache`, `fseq`, `cnc`, workspaces, and selected sandbox calls.

This maximizes Tickoni ownership and keeps every product concept in Zig-owned
files. It also avoids the awkward parts of Firedancer's validator topology
surface. The problem is that it recreates orchestration that Firedancer has
already battle-tested. Every copied concept becomes a second implementation
with its own edge cases: shutdown, stuck tiles, link cardinality, workspace
join order, metrics, heartbeat visibility, backpressure, process crash
handling, and sandbox sequencing. That is not where Tickoni should be spending
most of its complexity budget.

The finance value of Tickoni is capability-scoped money workflows, audit,
replay, bounded model/tool/adapter access, proposal-first agents, approval
gates, and evidence. Rebuilding orchestration machinery too eagerly pushes
work away from that finance layer and toward a second, less-proven Firedancer.
Option 1 is acceptable only as a fallback for a specific piece that cannot be
reused safely. It should not be the default architecture.

**Option 2: fully reuse Firedancer's validator harness as Tickoni's harness.**
At first glance this is attractive. Firedancer already has tile callbacks,
workspace joining, sandbox entry, shared-memory filling, lifecycle checks,
thread/process launch machinery, CPU placement, and metrics registration.
The orchestration code is much less Solana-specific than the validator tiles
that run on top of it.

But full reuse does not fit Tickoni as a product runtime.

First, V1.21 requires explicit cross-platform retail runtime support. Linux is
still the full high-throughput Firedancer runtime tier, but macOS and Windows
need supported retail paths for deterministic paper/sandbox demos, policy
decisions, audit output, and replay proofs. Firedancer's harness is a Linux
runtime built around Linux process, namespace, sandbox, affinity, and
shared-memory assumptions. It cannot simply become Tickoni's universal
runtime without either dropping the retail goal or pretending degraded tiers
have Linux-equivalent guarantees.

Second, the validator harness is not just a set of neutral callbacks. The
data structures and configuration path around it are Solana-shaped:

- `fd_topo_t` carries validator topology fields.
- `fd_topo_tile_t` carries validator tile fields.
- `fd_topob.c` is a validator topology builder with Solana/Agave pinning and
  kind assumptions.
- `fd_cfg_stage_*` config stages are validator-specific.

Trying to make all Tickoni runtime code speak these types directly would leak
validator concepts into the product boundary. It would also make V1.21
packaging harder, because consumer artifacts must exclude Solana validator
tiles, RPC schemas, account/runtime objects, GUI/plugin streams, and unrelated
Firedancer source.

Option 2 reuses the most code, but it gives the wrong code too much authority.
It is rejected as the product-level architecture.

**Option 3: use a Tickoni-owned runtime boundary with a Firedancer-backed
Linux implementation.** Tickoni owns the product-facing runtime abstraction:
tile ids, financial topology descriptors, link meaning, placement policy,
capability/audit/replay contracts, and support-tier reporting. Behind that
boundary, the Linux full-runtime implementation may adapt to Firedancer's
orchestration machinery instead of rebuilding it.

In its strongest form, this looks like:

```text
Tickoni topology view  ->  Linux adapter fills the minimal fd_topo_t surface
Tickoni tile view      ->  Linux adapter fills the minimal fd_topo_tile_t surface
Tickoni tile callback  ->  Linux adapter exposes fd_topo_run_tile_t callbacks

Linux full runtime     ->  calls Firedancer run/fill/sandbox/lifecycle paths
Retail runtimes        ->  use a different implementation under same boundary
```

This is not "full reuse". Product code does not get to depend on
`fd_topo_t`, `fd_topo_tile_t`, `fd_topob.c`, Firedancer config stages, Solana
tile kinds, validator metric names, or validator runtime assumptions. Those
types are adapter-private implementation details for the Linux full-runtime
tier. If a macOS or Windows retail tier needs a portable queue, process,
workspace, sandbox substitute, or simpler single-process deterministic demo
runtime, it implements the same Tickoni boundary without pretending to be
Firedancer.

This option has the best risk shape if it is kept honest:

- It avoids a parallel reimplementation of proven orchestration on Linux.
- It keeps Tickoni's product vocabulary and financial semantics out of
  upstream-hot Firedancer paths.
- It leaves room for V1.21 support tiers, because the public boundary is
  Tickoni-owned rather than `fd_topo_t`-owned.
- It focuses Tickoni engineering effort on finance-specific value while still
  using the real high-throughput engine where that engine exists.

The hard part is preventing the adapter from becoming a dishonest copy of
Firedancer's topology structs. If the Linux adapter has to fill dozens of
irrelevant Solana fields, run Firedancer config stages, or encode validator
tile assumptions just to satisfy the harness, then option 3 has failed and
should be narrowed. In that case, reuse should fall back to lower-level
substrate wrappers for the specific pieces that remain cleanly reusable.

**Decision.** Option 3 is the preferred architecture until proven otherwise:
a Tickoni-owned runtime boundary with a Firedancer-backed Linux full-runtime
adapter.

The decision is deliberately narrower than "use Firedancer's harness
directly" and deliberately stronger than "copy the primitives and rebuild the
rest." Tickoni should first attempt to reuse Firedancer's proven
orchestration machinery where it can be hidden behind a clean Tickoni
interface. Only the adapter may know about Firedancer topology/run types.
Finance-facing runtime code should continue to speak Tickoni tile ids,
Tickoni topology descriptors, Tickoni link contracts, and Tickoni support
tiers.

For the Linux full-runtime adapter, "reuse Firedancer orchestration" means
following the Firedancer harness semantics, not cherry-picking only the easy
parts. The adapter should preserve the relevant lifecycle hooks, ordering,
guards, and failure semantics from Firedancer's harness: workspace joining,
privileged and unprivileged init phases, sandbox entry, link filling,
metrics registration or equivalent visibility, run callback ownership,
shutdown allowance checks, process/thread launch expectations, CPU placement
behavior where used, and crash/exit handling. Any deliberate deviation from
those semantics needs an explicit reason and a test proving the Tickoni
substitute preserves the runtime guarantee being replaced.

Because this decision depends on Firedancer harness behavior staying
understood, Tickoni should add a `just engine-check-changes` gate and wire it
into `just tests-all`. The gate should detect changes to the Firedancer
harness file set relative to the previous commit and force a human review or
explicit acknowledgement before broad validation passes. The exact mechanism
is TBD, but the initial watched set should include:

- `src/disco/topo/fd_topo_run.c`
- `src/disco/topo/fd_topo.h`
- `src/disco/topo/fd_topo.c`
- `src/disco/stem/fd_stem.c`
- `src/app/shared/commands/run/run.c`
- `src/app/shared/commands/run/run1.c`
- `src/app/shared/boot/fd_boot.c`
- `src/util/sandbox/fd_sandbox.c`
- `src/util/sandbox/fd_sandbox.h`
- `src/util/sandbox/fd_sandbox_private.h`
- `src/disco/metrics/fd_metrics.c`
- `src/disco/metrics/fd_metrics.h`
- `src/disco/metrics/fd_metrics_base.h`

That file list is intentionally conservative and should be refined when the
Linux adapter identifies its exact dependency surface. The point is not to
freeze Firedancer, but to prevent silent drift in the orchestration contract
Tickoni has chosen to rely on.

The support-tier rule is part of the decision. Linux full-runtime mode may use
Firedancer orchestration. macOS and Windows retail modes must not inherit
Linux-only guarantees by implication. If a retail mode cannot provide process
isolation, namespace sandboxing, hugepage-backed workspaces, CPU pinning, or
equivalent shared-memory behavior, that gap must be visible in CLI, CaseOps,
audit, replay, metrics, diagnostics, and docs where it affects trust.

**What would disprove the decision?** Option 3 should be abandoned or narrowed
if any of these become true:

- The Linux adapter cannot call the Firedancer lifecycle/fill/sandbox paths
  without importing Solana validator config stages into Tickoni.
- Minimal adapter structs require persistent fake values for unrelated
  validator fields rather than a small, auditable compatibility surface.
- Product code outside the adapter needs to import or reason about
  `fd_topo_t`, `fd_topo_tile_t`, validator tile kinds, or validator metric
  schemas.
- The adapter blocks V1.21 support-tier separation by making the public
  Tickoni runtime contract Linux-only.
- Upstream synchronization cost becomes higher than maintaining a small
  Tickoni-owned lifecycle for the affected piece.

If that happens, the fallback is not option 1 wholesale. The fallback is
targeted: keep the Tickoni-owned boundary and reuse only the lower-level
Firedancer substrate that remains clean, such as `mcache`, `dcache`, `fseq`,
`cnc`, workspace primitives, sandbox calls, or metrics patterns.

**Deviations.** Some parts should remain Tickoni-owned even when option 3 is
working well:

- Financial tile identity and responsibility. `tkings`, `tknorm`, `tkdedu`,
  `tkcase`, `tkpoly`, `tkaudt`, `tkrepl`, `tkmetr`, `tkdiag`, `tkdisp`,
  `tkagnt`, `tkmodl`, `tktool`, `tkadpt`, `tkgate`, and future `tkexec` are
  Tickoni concepts, not validator tile aliases.
- Capability envelopes, policy outcomes, audit schemas, evidence records, and
  replay capsules. These are the product's financial correctness layer and do
  not belong in Firedancer topology structs.
- Cross-platform retail behavior. Retail modes may use substitutes or
  reduced-isolation implementations, but they must preserve deterministic
  policy/audit/replay claims for the demos they advertise and must fail
  closed for unsupported live effects.
- Packaging boundaries. Consumer artifacts should include only Tickoni-owned
  code and the Firedancer substrate actually reused by Tickoni, not the full
  validator application surface.

So the practical guidance is: do not build a second Firedancer unless the
adapter proves impossible, and do not turn Tickoni into a validator-shaped
application just to avoid writing an adapter. Put the boundary where the
product needs it: Tickoni owns finance semantics and support tiers;
Firedancer powers the Linux full-runtime implementation where its
orchestration can be reused cleanly.
