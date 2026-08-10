<!--
Tickoni epic issue template.

Use this template for a GitHub issue labeled `type/epic`.

An epic is a huge new feature or product increment: a group of related stories
that deliver a complete capability across domains. In GitHub, connect `story`
issues as sub-issues of this epic. Do not put implementation task checklists
directly in the epic unless they are epic-level coordination work.

Copy this file into the GitHub issue body or use it to create/update a
doc/strategy/roadmap/epics/VX.Y.md roadmap file. Replace placeholders and
remove HTML comments before closing the issue.

Epic labels:
  Epic:  VX.Y
  Story: VX.Y.SN
  Task:  VX.Y.SN.TN

Where:
  X  = milestone number
  Y  = epic number within that milestone
  SN = story number within that epic
  TN = task number within that story

Example:
  V1.6      = milestone 1, epic 6
  V1.6.S2   = story 2 under epic V1.6
  V1.6.S2.T3 = task 3 under story V1.6.S2

GitHub label guidance for epic creation:
  - Required issue-kind label: `type/epic`.
  - Add all relevant boundary/domain labels covered by the child stories, such
    as `area/agents`, `area/audit`, `area/crypto`, `area/investing`, `area/operations`,
    `area/payments`, `area/platform`, `area/security`, `area/social`, `area/trust`,
    `type/documentation`, or `type/feature`.
  - Epics may carry several boundary/domain labels because they comprise
    several stories across domains.
  - Do not add resolution or triage labels during normal epic creation, such as
    `duplicate`, `invalid`, `question`, or `wontfix`.

Epic quality standard:
  - Describes a complete user/operator outcome.
  - Defines measurable success and non-goals.
  - Breaks work into independently testable stories.
  - Identifies finance, runtime, audit, replay, model/tool/adapter, API/UI, and
    evidence boundaries only where they apply.

Read before filling:
  - doc/strategy/templates/status-template.md for epic, story, and task status
    definitions.
  - doc/strategy/README.md for product identity and what Tickoni is not.
  - doc/knowledge/architecture.md for runtime layers, tile ownership, event
    flow, and attached systems.
  - doc/strategy/capabilities.md for finance-native capability scope and
    policy outcomes.
  - doc/knowledge/tile-topology.md when the epic may affect tile ownership,
    topology, links, or Firedancer reuse.
  - doc/execution/security.md when the epic affects agent authority, tool access,
    secrets, replay divergence, or privileged action boundaries.
  - doc/execution/observability.md and doc/execution/telemetry.md when the epic
    adds or changes runtime/operator signals.
-->

# VX.Y: [Epic Title]

**Labels:** `type/epic`, [`area/agents` | `area/audit` | `area/crypto` | `type/documentation` | `type/feature` | `area/investing` | `area/operations` | `area/payments` | `area/platform` | `area/security` | `area/social` | `area/trust`]
**GitHub Issue:** TBD

<!-- One paragraph: what complete feature this epic delivers and why now.
     This is market-facing — (lead with WHY,
     reframe constraints as trust signals). Do NOT describe the tool or
     process; describe the transformation. Stories stay technical.-->

## Product Intent

<!--
Describe the product/customer problem and the outcome this epic closes. For
Tickoni, lead with consumer-money or operator trust outcomes, then mention
runtime/control-plane consequences.
-->

## Users And Jobs

<!--
List the primary actors and jobs-to-be-done. Keep each line tied to a real
workflow, not an internal component.
-->

- [Actor]: [job/outcome]

## Success Metrics

<!--
Use observable product and engineering measures. Examples: scenario completes
offline, policy denial visible, replay matches, audit chain valid, no external
side effects, bounded latency/queue health exposed.
-->

- ...

## Demo Moment

<!--
Describe the one concrete demo that proves the epic's value. Prefer a local,
offline command or deterministic CaseOps flow.
-->

- Command or flow: `[just target or exact steps]`
- Expected result: ...

## Scope

<!--
Define epic boundaries. This prevents related but separate product work from
landing in the same issue.
-->

### In Scope

- ...

### Out Of Scope

- ...

## Conditional Boundary Checklist

<!--
Mark each boundary as Applies, N/A, or Decision needed. Add links to story
issues or docs where the detail lives. Do not invent policy, storage,
execution, tile ownership, or API semantics inside the epic without a decision.
Use doc/architecture.md and doc/contribution/tickoni.md for runtime boundaries;
use doc/security.md for no-bypass and fail-closed expectations; use
doc/observability.md and doc/telemetry.md for metrics/diagnostics expectations.
-->

| Boundary | Status | Notes / linked story |
| --- | --- | --- |
| Financial capability and policy | [Applies | N/A | Decision needed] | ... |
| Audit records and evidence | [Applies | N/A | Decision needed] | ... |
| Replay and divergence behavior | [Applies | N/A | Decision needed] | ... |
| Runtime topology, tile ownership, or links | [Applies | N/A | Decision needed] | ... |
| Model gateway governance (`tkmodl`) | [Applies | N/A | Decision needed] | ... |
| Tool broker or adapter dispatch (`tktool` / `tkadpt`) | [Applies | N/A | Decision needed] | ... |
| Approved execution (`tkexec`) | [Applies | N/A | Decision needed] | ... |
| CaseOps API/UI (`tkapi`) | [Applies | N/A | Decision needed] | ... |
| Storage role: Memory, Analytics, Ledger | [Applies | N/A | Decision needed] | ... |
| Metrics, diagnostics, and operations | [Applies | N/A | Decision needed] | ... |
| Security and fail-closed behavior | [Applies | N/A | Decision needed] | ... |

## Story Breakdown

<!--
Create one GitHub sub-issue per story and label each `story`.
Use doc/strategy/templates/story-template.md for each child story issue.

### How Many Stories?

There is no fixed number. Write as many stories as the epic scope requires:

- Small scoped epics: 2-4 stories.
- Mid-range epics (e.g. a new tile + integration + UI): 4-7 stories.
- Large epics (e.g. full subsystem): 7-15+ stories.

The number is determined by decomposition quality, not by a template quota.
If the epic has 200+ lines of scope, it should have 7+ stories — not 2.

### Decomposition Rules

1. **Independent delivery**: each story must produce a user-visible or
   operator-visible outcome without waiting for every other story.
2. **One capability per story**: do not split CRUD from validation. If
   creating an entity requires validation (rejecting negative values, checking
   required fields, enforcing bounds), that validation belongs in the same
   story. Validation is part of the CRUD contract, not a separate story.
3. **Split by capability lifecycle**, not by layer:
   - S1: Core capability — the primary create/edit/delete or action flow
     with its validation, capability envelope, and audit trail.
   - S2: Read / query / visibility — the operator-facing surface (CaseOps,
     API, terminal) that surfaces the capability's state.
   - S3: State management — lifecycle transitions (activate, suspend, delete,
     migrate) that depend on S1 core being stable.
   - S4: Policy integration — capability-specific policy checks, approval
     paths, and scope enforcement via `tkpoly`.
   - S5: Replay and audit — deterministic replay support, replay capsules,
     hash-chained audit records for the capability's material events.
   - S6+: Domain-specific additions — model calls, adapter dispatch, storage,
     observability, or integration points the epic touches.
4. **Closure story**: the last story (or the last task in the final story, per
   the story template's T10 child task) handles evidence, demo, documentation,
   and quality gates. Do not duplicate this as a separate story line when the
   story template already covers it via child tasks.
5. **Domain boundaries**: if the epic touches multiple runtime boundaries
   (tile ownership, model gateway, adapter, UI), those are separate stories,
   not features within one story.

### Bad Splits (Avoid)

- CRUD + "validation" as two stories. Validation is part of the CRUD contract.
- "Backend" + "frontend" as two stories. Both should be independently testable
  outcomes, not layers of the same feature.
- "Database" + "API" as two stories. Same reason.
- Anything that requires ALL other stories to complete before one acceptance
  criterion can be tested. That is not independent delivery.

### Good Split Example (Portfolio Management Epic)

```
V5.1.S1: Portfolio CRUD — create/edit/delete portfolios and holdings with
         validation, capability envelopes, and audit trail.
V5.1.S2: Portfolio CaseOps surface — portfolio state and mutations visible
         through CaseOps with stable event IDs and hashes.
V5.1.S3: Portfolio replay — deterministic replay of portfolio mutations
         against the same event stream with stable hashes and reconstructed state.
V5.1.S4: Evidence, demo, and release closure — T10 expansion covering
         fixtures, quality gates, documentation, and roadmap updates.
```

Note: S4 is the closure, implemented as child tasks (T10) within that story
per the story template convention, not as a standalone epic-level story.

### Story Line Format

List stories in delivery sequence. Each line must have:
- Story ID (VX.Y.SN)
- Self-contained title describing the deliverable
- Link to the GitHub issue (TBD at epic creation)

<!--
List stories. Add or remove lines based on epic scope. Each story must follow
the decomposition rules above. The template shows 4 lines as a mid-range
example — adjust the count up or down.
-->

- [ ] VX.Y.S1: [Core capability — create/edit/delete with validation and audit] - #[github-story-issue]
- [ ] VX.Y.S2: [Read / query / operator visibility surface] - #[github-story-issue]
- [ ] VX.Y.S3: [State lifecycle — activate, suspend, delete, migrate] - #[github-story-issue]
- [ ] VX.Y.S4: [Policy integration — capability-specific checks, approvals, scope] - #[github-story-issue]
- [ ] VX.Y.S5: [Replay and audit — deterministic replay, capsules, hash chains] - #[github-story-issue]
- [ ] VX.Y.S6: [Domain-specific additions — model, adapter, storage, observability] - #[github-story-issue]
- [ ] VX.Y.S7+: [Any additional stories required by epic scope] - #[github-story-issue]

## Epic Acceptance

<!--
Define what must be true before the epic is accepted. These should roll up from
child story acceptance criteria and evidence gates.
-->

- [ ] All required story issues are done or explicitly deferred with rationale.
- [ ] The demo moment succeeds using deterministic local inputs.
- [ ] Relevant policy, audit, replay, adapter, API/UI, metrics, diagnostics,
      and documentation artifacts are linked from this epic.
- [ ] Non-goals and deferred work are visible in the roadmap.
- [ ] No live model, broker, payment, trading, crypto, approved execution ledger, or execution
      side effects occur unless this epic explicitly enables an approved
      sandbox/live execution path.

## Release / Evidence Gate

<!--
Answer only the questions that apply. Use `N/A - reason` instead of forcing
every epic through topology or tool-broker evidence.
Use doc/strategy/positioning.md to tie the answer back to Tickoni's unique
value proposition: high-throughput agentic finance, consequence isolation,
bounded spend, hard policy gates, and forensic replay.
-->

- What can the user or operator do now that they could not before this epic?
- What changed from the previous roadmap increment?
- What is this epic's wow-effect: the visible moment in this epic's demo or
  workflow that makes Tickoni feel unlike a generic agent harness?
- How does this epic progress Tickoni's unique value proposition from
  doc/strategy/positioning.md: speed, isolation/control, spend governance,
  policy-gated action, and forensic replay?
- Which demo command or CaseOps flow closes the epic?
- Which account, beneficiary, IBAN, wallet, rail, currency, market, venue,
  asset class, instrument, notional, amount, exposure, and frequency checks are
  enforced, if any?
- What happens when the requested action exceeds policy, scope, or evidence?
- Is execution paper-only, draft-only, sandbox, live, or disabled?
- Which fixtures, samples, audit records, replay capsules, screenshots, or API
  examples prove the behavior?
- Can replay run without external side effects when replay applies?
- What intentional blocked-flow or divergence example proves fail-closed behavior?

## Dependencies And Decisions

<!--
List prerequisite epics/stories and unresolved product, policy, architecture,
storage, adapter, execution, or public-contract decisions.
-->

- ...
