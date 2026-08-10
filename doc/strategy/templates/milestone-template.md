<!--
Tickoni milestone template.

Use this template for a GitHub issue labeled `milestone`.

A milestone is a grouped set of epics that delivers a complete, coherent
product or platform increment. A milestone is not a story (a single
implementable deliverable) or an epic (a huge new feature spanning related
stories); it is the highest-level roadmap container that the team ships
together and measures completion against.

In GitHub, connect `type/epic` issues as sub-issues of this milestone.

Milestone labels:
  Milestone: M{N}
  Epic: VX.Y
  Story: VX.Y.SN
  Task: VX.Y.SN.TN

Where:
  N  = milestone number
  X  = milestone number (mirrors N)
  Y  = epic number within that milestone
  SN = story number within that epic
  TN = task number within that story

Example:
  M4       = milestone 3
  V4.12    = epic 12 under milestone 3
  V4.12.S2 = story 2 under epic V4.12
  V4.12.S2.T3 = task 3 under story V4.12.S2

Required for every milestone:
  - Product or platform outcome in one sentence
  - A one-line code-block formula summarizing the transformation
  - Included epics
  - Why this is a milestone (not just another epic)
  - Completion signal (observable evidence the milestone is done)

Read before filling:
  - doc/strategy/templates/status-template.md for status definitions.
  - doc/strategy/README.md for product identity, supported workflows, and
    non-goals.
  - doc/knowledge/architecture.md for the runtime model, source-of-truth
    boundaries, and tile responsibilities.
  - doc/strategy/positioning.md for Tickoni's unique value proposition.
  - doc/execution/development.md for build/run commands.
  - doc/execution/testing-tickoni.md for test layer selection.
  - doc/execution/security.md for fail-closed behavior.
  - doc/execution/observability.md and doc/execution/telemetry.md for
    metrics, diagnostics, and operator-visible evidence.
-->

# M{N}: [Milestone Title]

## Description

<!--
One short paragraph describing what this milestone delivers and why it matters.
Lead with the user or operator outcome, then mention runtime or platform
consequences if applicable.

Followed by a one-line code-block formula summarizing the transformation,
e.g.:

```text
input action -> safety gate -> observable outcome
```

Keep the formula under 80 characters. Use it as a mental anchor.
-->

[Milestone deliverable description.]

## Included Epics

<!--
List the epics that roll up into this milestone. Each epic is a shippable
increment with its own user outcome, acceptance criteria, and evidence gate.

Scoping rules for epics:

  1. One epic = one user-valuable capability the operator or user can
     independently verify. Do not group "everything about crypto" into a
     single epic. Split by capability boundary (allowlist, risk scoring,
     policy enforcement, audit, demo) or by user outcome (check scope,
     submit proposal, view results, replay).
  2. If an epic has more than 3 story groups or more than 12 tasks, it is
     too big and must be split. V6.9 is the example to avoid: a single
     epic with 6 stories and 36 tasks. Split that into separate epics for
     intent/schema, snapshots, ticketing, policy, order lifecycle, and
     demo/replay.
  3. Epics that touch different Tickoni capability boundaries should be
     separate: guard/allowlist, risk scoring, policy enforcement, ticket
     generation, order lifecycle, and demo/replay each earn their own epic.
  4. Do not group by "product" vs "platform" unless the platform change
     produces a user-visible outcome on its own. Prefer capability-based
     or outcome-based grouping.

Each line should name the epic code, title, and the linked GitHub issue.

Example of good decomposition for M6 (what M6 should look like):

  Capability epics:

  - `V6.1`: Crypto allowlist and account fixtures — #[github-epic-issue]
  - `V6.2`: Chain-risk scoring and travel-rule checks — #[github-epic-issue]
  - `V6.3`: Policy enforcement for crypto transfers — #[github-epic-issue]
  - `V6.4`: Stablecoin cash-impact view — #[github-epic-issue]
  - `V6.31`: Intent, schema, and instrument catalog — #[github-epic-issue]
  - `V6.6`: Account and market snapshots — #[github-epic-issue]
  - `V6.7`: Fee-aware ticket generation — #[github-epic-issue]
  - `V6.8`: Order lifecycle and sandbox submission — #[github-epic-issue]
  - `V6.9`: Demo, audit, and replay — #[github-epic-issue]

Example of poor decomposition (what to avoid):

  - `V6.31`: Crypto And Stablecoin Guard — broad, mixes allowlist + policy
    + audit in one epic (7 tasks that belong in 3 epics)
  - `V6.9`: Crypto Thesis To Guarded Spot Trade — monolith with 6 stories
    and 36 tasks, should be 7+ separate epics

Group by capability boundary, not by theme.
-->

## Why This Is A Milestone

<!--
Explain why these epics together earn milestone status. A milestone is not a
convenience grouping; it is a moment where the product or platform crosses a
qualitative threshold.

Answer:
  - What property becomes true only when all these epics ship?
  - What prerequisite milestone established the foundation this one builds on?
  - What future milestone depends on this one being complete?
  - Why is this a milestone rather than a single epic?

Use concrete consequences, not abstractions. Examples:
  - a new capability loop closes end to end
  - a runtime property shifts from demo-credible to production-credible
  - a trust or proof surface becomes inspectable by a third party
  - a domain (payments, crypto, social) gets the same safety model as an
    existing one
-->

## Completion Signal

<!--
Describe the observable evidence that proves the milestone is complete. This
should be specific enough that a reviewer can verify it without reading every
epic's acceptance criteria.

Use deterministic, reproducible language. Examples:
  - a user can run [demo command or CaseOps flow] and get [observable result]
  - integration tests confirm [runtime property]
  - a partner can inspect [exported record] and verify [proof]
  - [domain] proposals are replayable from deterministic fixtures with
    [allowed, blocked, resized, approval-required] flows demonstrated
-->

## Summary

<!--
A market-facing synthesis (2–5 sentences, ~300–550 chars).
This is NOT a feature list or epic inventory. It is the WHY, the transformation,
the trust signal.

Pattern:
  1. Contrast / framing — what most people think vs what is actually happening
  2. Transformation — what changes, what becomes possible
  3. Trust signal — the counterintuitive insight that makes this a milestone

Example:
  "People don't trust systems — they trust proof. M0 is where Tickoni stops
  being code and starts being a system that can prove it works every time.
  It's not a feature — it's the first claim Tickoni makes on trust."

Rules:
  - No technical detail: "tiles move to supervisor processes" is HOW, not WHY
  - No defensive language: "A crashing tile leaves its siblings running"
  - No epic inventory: GH milestone page already lists epics as sub-issues
  - Single paragraph, ~300–550 chars (fits cleanly in GH milestone descriptions)
  - Written start with WHY and reframe constraints as trust signals

See `roadmap-authoring` skill for the full summary specification.
-->
