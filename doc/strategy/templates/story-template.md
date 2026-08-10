<!--
Tickoni story issue template.

Use this template for a GitHub issue labeled `story`.

A story is a single implementable deliverable that can be independently
verified. It should be small enough to complete without splitting across
multiple unrelated outcomes, but large enough to produce a user-visible or
operator-visible change. In GitHub, connect it as a sub-issue of one `type/epic`
issue and connect domain `task` issues as sub-issues of this story.

Copy this file into the GitHub issue body or into the relevant
doc/strategy/roadmap/epics/VX.Y.md section, replace placeholders, and remove
HTML comments before closing the issue.

Story labels:
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

Required for every story:
  - Product outcome
  - Actor/user story
  - Acceptance criteria
  - Evidence and quality gate tasks as child task issues after the story is
    Ready

GitHub label guidance for story creation:
  - Required issue-kind label: `type/story`.
  - Related issue-kind labels: parent issues use `type/epic`; child issues use
    `type/task`.
  - Add exactly one boundary/domain label for the story's primary ownership:
    `area/agents`, `area/audit`, `area/crypto`, `area/investing`, `area/operations`,
    `area/payments`, `area/platform`, `area/security`, `area/social`, `area/trust`,
    or `type/documentation`.
  - If a story needs several boundary/domain labels, split it into smaller
    stories under the same epic.
  - Add `enhancement` for a new product/runtime capability when useful.
  - Do not add resolution or triage labels during normal story creation, such
    as `duplicate`, `invalid`, `question`, or `wontfix`.

Conditional guidance:
  - Include topology/link acceptance only when the story changes Tickoni tile
    ownership, queues, workspaces, links, lifecycle, or Firedancer integration.
  - Include capability/policy acceptance only when the story changes financial
    authority, policy outcomes, approval rules, limits, or scope dimensions.
  - Include audit/replay acceptance only when the story changes material events,
    evidence, replay capsules, divergence checks, or append-only records.
  - Include model/tool/adapter acceptance only when the story touches tkmodl,
    tktool, tkadpt, model providers, local agent CLI routing, or financial
    adapter calls.
  - Include UI/API acceptance only when the story changes tkapi, CaseOps, HTTP,
    WebSocket, ingestion, review, approval, or external contract behavior.
  - Mark a conditional section `N/A - reason` when reviewers may otherwise
    expect it.

Read before filling:
  - doc/strategy/templates/status-template.md for status definitions and the
    rule that task sub-issues are created only after the story is Ready.
  - doc/strategy/README.md for product identity, supported workflows, and
    non-goals.
  - doc/knowledge/architecture.md for the runtime model, source-of-truth
    boundaries, tile responsibilities, and replay/audit constraints.
  - doc/execution/contribution/tickoni.md for Zig runtime style, Firedancer
    substrate reuse, C ABI boundaries, and separation rules.
  - doc/execution/build.md and doc/execution/development.md for repo-facing
    build/run commands and justfile command policy.
  - doc/execution/testing-tickoni.md and doc/execution/ci.md for test layer
    selection and CI gates.
  - doc/execution/security.md for fail-closed behavior, no-bypass expectations,
    and agent/tool capability boundaries.
  - doc/execution/observability.md and doc/execution/telemetry.md for metrics,
    diagnostics, labels, and operator-visible evidence.
-->

# VX.Y.SN: [Story Title]

**Labels:** `type/story`, [exactly one of: `area/agents` | `area/audit` | `area/crypto` | `type/documentation` | `area/investing` | `area/operations` | `area/payments` | `area/platform` | `area/security` | `area/social` | `area/trust`], [`type/feature` if applicable]
**GitHub Issue:** TBD

<!-- One sentence: the independently verifiable deliverable. -->

## Product Outcome

<!--
Describe the outcome in user/operator language. Avoid implementation-only
phrasing unless this is an infrastructure story. State what becomes possible or
safer after this story is done.
-->

## User Story

<!--
Use standard product format:
As a [actor], I want [capability], so that [benefit].

Tickoni actors are usually consumer-money user, CaseOps operator, reviewer,
agent operator, developer/operator, compliance/risk reviewer, or runtime owner.
-->

As a [actor], I want [capability], so that [benefit].

## Scope

<!--
List the exact deliverable boundaries. Keep this story self-contained. Move
unrelated work into separate stories under the same epic.
-->

- In scope: ...
- Out of scope: ...

## Preconditions And Assumptions

<!--
State dependencies, fixture assumptions, known policy decisions, and existing
runtime behavior this story relies on. If the story requires a policy,
capability, storage, tile ownership, or API contract decision that is not
already documented, stop and create/raise that decision before implementation.
-->

- ...

## Acceptance Criteria

<!--
Write testable acceptance criteria in Given/When/Then or concrete observable
form. Each criterion should be independently verifiable by a task, test, demo,
fixture, or artifact.

Use the project docs to make acceptance concrete:
  - Product behavior: doc/strategy/README.md.
  - Runtime/tile behavior: doc/knowledge/architecture.md and
    doc/execution/contribution/tickoni.md.
  - Build/run behavior: doc/execution/build.md and doc/execution/development.md.
  - Tests and CI impact: doc/execution/testing-tickoni.md and
    doc/execution/ci.md.
  - Security/fail-closed behavior: doc/execution/security.md.
  - Metrics/diagnostics evidence: doc/execution/observability.md and
    doc/execution/telemetry.md.
-->

- [ ] Given [context], when [action], then [observable result].
- [ ] Given [invalid or blocked condition], when [action], then [fail-closed result].

### Conditional Acceptance

<!--
Keep only the subsections that apply. Use `N/A - reason` for boundaries that
are commonly relevant to this story's domain but intentionally untouched.
-->

**Financial capability and policy**

<!-- Applies when changing tkpoly behavior, capability envelopes, limits,
approval state, denied-by-default behavior, or financial scope. -->

- [ ] [N/A - reason, or policy acceptance criterion]

**Audit and replay**

<!-- Applies when adding/changing material events, evidence, audit JSONL,
hash-chain behavior, replay capsules, divergence checks, or replay substitution. -->

- [ ] [N/A - reason, or audit/replay acceptance criterion]

**Runtime topology and tile ownership**

<!-- Applies when changing tile IDs, tile ownership, links, workspaces, queue
depths, reliability, overrun behavior, restart behavior, shutdown behavior, or
Firedancer infrastructure integration. -->

- [ ] [N/A - reason, or topology acceptance criterion]

**Model, tool, adapter, or execution boundary**

<!-- Applies when changing tkmodl, tktool, tkadpt, tkexec, agent daemon behavior,
provider config, adapter manifests, broker/payment/trading/crypto/risk/compliance
API access, or replay substitution for external calls. -->

- [ ] [N/A - reason, or boundary acceptance criterion]

**CaseOps API or UI**

<!-- Applies when changing tkapi, HTTP/WebSocket behavior, CaseOps screens,
operator review, approval flows, external ingestion, or partner review APIs. -->

- [ ] [N/A - reason, or API/UI acceptance criterion]

## Child Task Issues

<!--
Create one GitHub sub-issue per task and label each `task` only after this
story's Status is `Ready`.

Before `Ready`, use this section to describe the likely task split in prose
or leave placeholders. Do not create GitHub task sub-issues while the story is
still being shaped; otherwise task work can start before the story boundary,
acceptance criteria, and evidence gates are stable.

Task creation rules:
  - Create task sub-issues only after the story Status is `Ready`.
  - Each task must have:
      * A `Task Type` section (Runtime / tile / topology, Capability / policy,
        Audit / evidence, Replay / divergence, Model gateway, Tool broker /
        adapter, Approved execution, CaseOps API / UI, Fixtures / sample data,
        Tests / quality gate, Documentation / roadmap, or Other).
      * A `Story Acceptance Covered` section listing the exact parent story
        acceptance criteria the task helps close.
      * An `Implementation Notes` section naming the expected touch points,
        files, modules, fixtures, or docs, with important constraints stated.
      * A `Conditional Requirements` section keeping only the requirements
        that apply (Validation / fail-closed, Security / no-bypass, Audit /
        replay artifacts, Config / manifest handling, Docs / roadmap
        reconciliation); mark unused sections `N/A - reason`.
      * A `Verification` section listing exact checks (focused test commands,
        `just test-unit-tk`, `just test-integration-tk`, demo commands).
      * An `Evidence To Attach` section for test output, demo output, fixture
        paths, audit samples, replay samples, or linked artifacts.
      * A `Done Criteria` section confirming the scoped change is implemented,
        parent acceptance criteria are satisfied, verification commands pass or
        failures are documented with owner, evidence is attached, and no
        unrelated files/policy semantics/tile ownership/public contracts/
        financial authority changed.
  - Each task must link back to the parent story's acceptance criteria and
    to the relevant execution docs it must follow:
      * `doc/execution/contribution/tickoni.md` — Zig/runtime style, Firedancer
        reuse, C ABI rules, separation constraints.
      * `doc/execution/build.md` and `doc/execution/development.md` — build/run
        commands, justfile policy.
      * `doc/execution/testing-tickoni.md` and `doc/execution/ci.md` — test
        layer selection, CI gates.
      * `doc/execution/security.md` — fail-closed behavior, no-bypass
        expectations, static/preallocated-memory discipline, C/Zig memory and
        stack safety, agent capability boundaries.
      * `doc/execution/telemetry.md` — metric/diagnostic fields, label policy,
        alerting policy.
      * `doc/execution/observability.md` — per-tile visibility, smoke checks,
        failure visibility.
      * `doc/execution/quality.md` — evidence gate checklist, story closure
        checklist, conditional gates.
      * `doc/knowledge/architecture.md` — runtime/source-of-truth boundaries.
      * `doc/knowledge/tile-topology.md` — tile IDs, links, ownership.
  - Keep tasks implementable by one owner without requiring unrelated changes.

Task ordering and purpose (fixed across all stories):

VX.Y.SN.T1 — Architecture and planning. Define the architectural fit of this
story within the existing tile topology and Firedancer substrate. Identify risks,
known unknowns, and decisions that must be resolved before implementation. This
task must name the tiles, links, workspaces, and capability scope the story will
touch, flag any tile ownership, link shape, or Firedancer integration changes,
and record every open question. Do not start implementation until this task
blocks no remaining implementation task.

VX.Y.SN.T2 — Domain-Driven Design and scaffolding. Write out the types, structs,
tagged unions, enums, and comptime tables the story requires, following
`doc/execution/contribution/tickoni.md`. Define the input and output shapes for
every function the story will implement — these must be finalised objects/structs
that cross trust boundaries. Implement scaffold functions with `NotImplemented`
errors and `log.warn` calls only. No production logic yet. This task establishes
the compile-time surface the story will build on.

VX.Y.SN.T3 — Test-Driven Design: write tests, then stub implementation. Write
full unit and integration tests (following
`doc/execution/testing-tickoni.md`) against the scaffolding from T2. Then lightly
implement the scaffolding methods with correct hardcoded return values and a
`// TODO: implement` comment, plus a `log.warn` line. At this point every input
and output shape is finalised as concrete structs, so any dependency issues,
previously unknown risks, import/c_abi layout mismatches, `@sizeOf`/`@alignOf`/
`@offsetOf` verification failures, or missing C ABI wrapper concerns will surface
as failing tests or compile errors. Flag every issue, make a decision, and
re-architect the story if needed. By the end of this task all tests must be
present and passing. This is the gate before implementation — if tests do not
pass, implementation tasks must not start.

VX.Y.SN.T4 — Documentation and DevOps sweep. Update `doc/knowledge/`,
`doc/execution/`, and `doc/strategy/` docs to reflect any decisions made during
T1–T3, following `doc/execution/quality.md` section 5. Remove any supporting or
WIP docs that are no longer relevant. Finalise ADR documents and the repo
architecture. Complete any CI/devops changes (justfile targets, supporting
scripts, `contrib/` scripts) needed by the story.

VX.Y.SN.T5–T9 — Implementation (5 tasks). Implement the full logic for every
function that had `NotImplemented`, `// TODO`, and `log.warn` stubs from T2/T3.
Replace all hardcoded return values with production logic. Spread the work across
5 tasks by domain/ownership — one task per tile, policy, audit/replay,
model/tool/adapter boundary, and API/UI surface as applicable. Each task must
follow the task structure described above and point to the acceptance criteria
it closes.

VX.Y.SN.T10 — Security audit. Audit the story's code against
`doc/execution/security.md`. Check: input validation at every trust boundary,
output/error checking, fail-closed behavior, no-bypass paths, static and
preallocated memory discipline, C/Zig memory and stack safety, agent capability
boundaries, deny-by-default policy, and no-elevated-permissions rules. Run
`just security-check-all` and record results in the task's `Evidence To Attach`
section. Flag and remediate any findings.

VX.Y.SN.T11 — Telemetry and observability audit. Audit the story's operator
signals against `doc/execution/telemetry.md` (metric/diagnostic field definitions,
label policy, alerting policy, generated metrics) and
`doc/execution/observability.md` (per-tile visibility, smoke checks, failure
visibility). Ensure new metrics use low-cardinality labels only, new diagnostic
signals follow the Phase 0 snapshot pattern, and failure visibility is preserved.
Capture telemetry/observability evidence.

VX.Y.SN.T12 — Evidence and quality gate. Run the full closing gate per
`doc/execution/quality.md`. Complete the Story Closure Checklist:
demoability, tests at every applicable layer (unit, integration, system, E2E),
quality and security checks (fail-closed, forbidden-direct-access, malformed
config, quality-check-all, security-check-all), evidence artifacts (audit JSONL
samples, replay samples, approval/rejection samples, metrics/diagnostics output,
fixtures), and documentation/roadmap reconciliation. Mark each line
`N/A - reason` where the story does not touch that boundary. Do not move the
story status to `Done` until every line is checked off or explicitly waived.

## Evidence Plan

<!--
State how this story will prove completion. Evidence is not limited to tasks;
it may include tests, demo output, fixtures, audit samples, replay samples,
screenshots, API examples, generated artifacts, or docs.
-->

- Demo or command: `[just target or exact command]`
- Tests: `[focused test targets]`
- Fixtures or samples: `[paths or planned artifacts]`
- Audit/replay evidence: `[N/A - reason, or planned artifacts]`
- Blocked-flow evidence: `[N/A - reason, or planned fixture/test]`

## Quality Gate

<!--
Use the narrowest meaningful checks. Add broader gates when the story touches
shared runtime behavior, security boundaries, or public contracts.

Use doc/testing-tickoni.md for test selection. Use doc/ci.md to understand
which GitHub Actions lanes are expected to cover the changed paths. Use
doc/development.md for the rule that repo-facing commands belong in the
justfile, not upstream Firedancer Makefiles.
-->

- [ ] Focused tests for changed behavior pass.
- [ ] `just test-unit-tk` passes when Tickoni runtime code changes.
- [ ] `just test-integration-tk` passes when cross-tile, API, replay, adapter,
      or fixture behavior changes.
- [ ] `just test-demo-tk` or the story-specific demo command prints the required
      scenario when this story changes a demoable product flow.
- [ ] Documentation and roadmap status are updated when user-visible scope,
      non-goals, or evidence gates change.

## Notes And Open Questions

<!--
List unresolved decisions. Do not hide ambiguity in implementation tasks. Raise
architecture, policy, storage, execution authority, or API contract questions
before implementation starts.
-->

- ...
