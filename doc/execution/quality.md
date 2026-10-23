# Quality Gate And Story Closure

This document defines Tickoni's Definition of Done: the checklist a story's
final "Evidence and quality gate" task uses to prove the story is demoable,
tested at every applicable layer, documented, and safe to mark `Done`.

It is the single source of truth for what
[`story-template.md`](../strategy/templates/story-template.md) calls "Evidence
and quality gate tasks". Those templates say a gate task is
required; this document says what the gate task must actually check. Do not
duplicate this checklist into a story or task issue body — link here and mark
each line applicable or `N/A - reason`.

## Why A Closing Gate

Implementation being "code complete" is not the same as a story being closeable.
Industry practice (Definition of Done, release-readiness review, exit
criteria) separates "I wrote the code" from "this is provably done": a
reviewer, a future replay, or a compliance auditor must be able to verify the
claim without re-deriving it from source. In Tickoni specifically, this matters
because [`security.md`](security.md) treats replay divergence and unaudited
state as serious events — a story is not done if its evidence cannot later
reconstruct what shipped.

[`status-template.md`](../strategy/templates/status-template.md) already
encodes the lifecycle boundary: a story or task only reaches `Done` once
"verification is complete or explicitly waived" and "evidence is linked." This
document is what fills in "verification" and "evidence" for that status
transition.

## When This Applies

Every story requires a closing gate task, even when the story is
documentation-only or infrastructure-only — an implementation-free story still
needs its docs/roadmap reconciliation validated. The gate task itself should
run last, after all domain implementation tasks in the story pass locally.

Use conditional gates: only require topology, policy, tool-broker, adapter,
audit, or replay evidence when the story actually touches that boundary,
matching the "Conditional Acceptance" sections in `story-template.md`. Mark a
line `N/A - reason` rather than deleting it, so a reviewer sees the boundary
was considered and intentionally not exercised, not skipped.

## 1. Demoable

A story is demoable when an operator or reviewer can observe the claimed
behavior end to end without reading source.

- [ ] A demo command, script, or fixture-backed scenario exists and exercises
      the story's product-visible behavior (`just test-unit-cli` and
      `just test-integration-cli` for CLI-level changes, a story-specific
      `just` target, or a documented fixture invocation).
- [ ] The demo output answers the applicable subset of the
      [Increment Gate Checklist](../strategy/roadmap/epics/README.md#increment-gate-checklist):
      what the user can now do, the demo moment, which
      account/venue/instrument/amount/frequency checks are enforced, what
      happens on an out-of-scope or over-limit request, and whether execution
      is paper-only, draft-only, sandboxed, live, or disabled.
- [ ] A blocked-flow or intentional-divergence example is captured when the
      story changes policy, capability, or replay behavior — a passing-only
      demo does not prove fail-closed behavior.
- [ ] Demo/fixture output is deterministic and reproducible on a clean
      checkout — no reliance on wall-clock time, network state, or
      operator-local data that a reviewer cannot reproduce.

## 2. Tests Exist At Every Applicable Layer

Use [`testing-tickoni.md`](testing-tickoni.md) to choose the narrowest correct
layer, then broaden only where the story's blast radius requires it. A gate
task should name which layers apply and which are genuinely out of scope, not
silently skip a layer.

- [ ] **Unit** — `just test-unit-tk` (Tickoni Zig) and/or `just test-unit-fd`
      (Firedancer-derived C) cover the new/changed unit of behavior in
      isolation, including malformed-input and boundary cases, not only the
      happy path.
- [ ] **Integration** — `just test-integration-tk` covers cross-tile,
      transport, replay, or adapter-boundary wiring whenever the story
      changes behavior that only shows up when real Tickoni internals talk to
      each other, per the layer boundaries in `testing-tickoni.md`.
- [ ] **System** — `just test-system-tk` (or another test root under
      `src/tickoni/test/system/`) covers live-tool compatibility when the
      story touches `tkmodl`, a local model server, or another real external
      tool surface. Mark `N/A - reason` when the story does not touch that
      boundary.
- [ ] **E2E** — `just test-e2e-fd` (or the current `test-e2e-tk` placeholder,
      once real) covers full local-topology/runtime-startup behavior when the
      story changes topology, workspace, sandboxing, or process lifecycle
      behavior.
- [ ] Every new test is wired into the correct `just` recipe and the relevant
      `*-all` aggregate (`test-unit-all`, `test-integration-all`,
      `test-e2e-all`) so `just tests-all` actually exercises it — a test that
      only runs when invoked by hand is not evidence.
- [ ] Tests were added before or alongside the implementation they verify,
      per Test-Driven Development in `testing-tickoni.md`, not retrofitted
      only to satisfy this checklist.

## 3. Quality And Security Checks

These restate the mandatory checks from [`security.md`](security.md) and the
Secure Coding Guidelines in `CLAUDE.md` as gate items, so a closing task can
check them off rather than re-derive them.

- [ ] Fail-closed validation: missing, malformed, or out-of-range input at
      every changed trust boundary is explicitly tested, not assumed safe by
      construction.
- [ ] Forbidden-direct-access checks: if the story touches a hard boundary
      (`tkmodl`, `tktool`/`tkadpt`, `tkexec`, the approved execution ledger, the C ABI membrane),
      a test or static check confirms nothing outside the owning module
      reaches it directly.
- [ ] Malformed envelope/config/manifest handling: capability envelopes,
      provider configs, and adapter manifests reject invalid shapes at
      startup or request time instead of defaulting or truncating silently.
- [ ] `just quality-check-all` (format + lint, both lanes) passes for changed
      paths.
- [ ] `just security-check-all` passes for changed paths, or a skipped
      component is named explicitly (e.g. a currently no-op CodeQL/seccomp
      variant documented in `security.md`).
- [ ] No new allocation, unbounded growth, or unchecked error union was
      introduced on a hot/event path, per the Static, Preallocated Memory and
      Output And Error Checking rules in `security.md`.

## 4. Evidence Artifacts

Capture proof, not just passing exit codes — a reviewer or future replay
should be able to inspect what happened without re-running the story's full
implementation.

- [ ] Audit JSONL samples are captured when the story adds or changes a
      material event, policy decision, model/tool/adapter call, proposal, or
      approval — confirming append-only and hash-chain behavior is intact.
- [ ] Replay samples/output are captured when the story touches replay
      capsule shape or replay-substituted behavior, confirming replay runs
      with external effects disabled per `security.md` and `CLAUDE.md`.
- [ ] Approval/rejection samples are captured when the story changes policy
      outcomes or approval-gated actions.
- [ ] Metrics/diagnostics evidence (`tkmetr`/`tkdiag` output, or current
      Phase 0 metric/diagnostic lines per [`observability.md`](observability.md)
      and [`telemetry.md`](telemetry.md)) is captured when the story adds or
      changes operator-visible runtime signals.
- [ ] Fixtures, sample configs, or generated artifacts referenced by the
      story's tests or demo are committed at a stable path, not left as
      local-only scratch output.
- [ ] Long logs are linked as artifacts rather than pasted in full into the
      story or task issue.

Mark any line above `N/A - reason` when the story does not touch that
boundary — a policy-only or infra-only story will not have approval samples,
and a docs-only story will not have audit samples.

## 5. Documentation And Roadmap Reconciliation

- [ ] Any doc under `doc/knowledge/`, `doc/execution/`, or `doc/strategy/`
      that describes the changed behavior is updated in the same change,
      per Source Of Truth in `CLAUDE.md` — do not leave docs describing
      pre-change behavior as though they still apply.
- [ ] If the story's implementation diverged from what a doc described going
      in, that divergence is flagged explicitly in the story/task notes, not
      silently resolved by quietly rewriting the doc to match the code.
- [ ] `tile-topology.md`, `tile-delivery-status.md`, or the contribution guide
      are updated when the story changes tile IDs, links, ownership, or the
      Tickoni/Firedancer boundary.
- [ ] Roadmap status for the story (and its parent epic, if this closes it)
      is updated only after every applicable line in this checklist passes —
      per `story-template.md`, do not move status to `Done` first and true it
      up after.

## Conditional Gates

Include only the sections that apply; mark the rest `N/A - reason`. These
mirror the Conditional Acceptance sections in `story-template.md` so the
closing gate checks exactly what the story's acceptance criteria promised.

**Financial capability and policy** — `tkpoly` outcomes, capability envelope
shape, limits, and approval state are covered by tests and an audit sample
showing the decision.

**Audit and replay** — new/changed material events, evidence, hash-chain
behavior, and replay capsules are covered by an integration test and a
captured replay sample.

**Runtime topology and tile ownership** — tile IDs, links, workspaces, queue
depth/MTU/reliability, restart/shutdown behavior are covered by
`test-unit-tk`/`test-integration-tk` and, where startup or process lifecycle
changed, `test-e2e-fd`.

**Model, tool, adapter, or execution boundary** — `tkmodl`/`tktool`/`tkadpt`/
`tkexec` request shape, allowlists, budgets, and replay substitution are
covered by tests and, where a live tool is involved, `test-system-tk`.

**CaseOps API or UI** — `tkapi` HTTP/WebSocket contracts, CaseOps screens, and
approval flows are covered by integration tests and, where practical, a
captured request/response sample.

## Story Closure Checklist

Copy this condensed form into the story's final gate task and check off (or
mark `N/A - reason`) each line before moving status to `Done`:

- [ ] Demo exists and its output answers the applicable Increment Gate
      Checklist questions.
- [ ] Unit tests exist and pass for changed behavior.
- [ ] Integration tests exist and pass for changed cross-tile/boundary
      behavior, or are marked `N/A - reason`.
- [ ] System tests exist and pass for changed live-tool behavior, or are
      marked `N/A - reason`.
- [ ] E2E tests exist and pass for changed topology/runtime-lifecycle
      behavior, or are marked `N/A - reason`.
- [ ] `just quality-check-all` and `just security-check-all` pass, or a
      skipped component is named explicitly.
- [ ] Evidence (audit/replay/approval/metrics samples, fixtures) is captured
      and linked for every boundary this story touched.
- [ ] Docs and roadmap status are updated and reconciled with the actual
      implementation.
- [ ] All items above are true before status moves to `Done` — not before,
      not "mostly."

## Related Docs

- [Tickoni Testing](testing-tickoni.md)
- [Security](security.md)
- [Observability](observability.md)
- [Telemetry](telemetry.md)
- [CI](ci.md)
- [Story Template](../strategy/templates/story-template.md)
- [Status Template](../strategy/templates/status-template.md)
- [Roadmap Stories README](../strategy/roadmap/epics/README.md)
