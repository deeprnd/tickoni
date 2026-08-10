<!--
Tickoni backlog proposal template.

Use this template when an idea is not ready to become an epic or story yet.
A backlog proposal answers: why does this belong in Tickoni?

It should be product-fit first, implementation-light. Do not turn this into an
acceptance-criteria document. If the proposal is accepted, graduate it into an
epic or story using the relevant template.
-->

# Backlog Proposal: [Proposal Title]

**Status:** Backlog Proposal
**Candidate issue type if accepted:** [epic | story | documentation | decision]
**Candidate labels:** [`agents` | `audit` | `crypto` | `documentation` | `enhancement` | `investing` | `operations` | `payments` | `platform` | `security` | `social` | `trust`]
**Related docs / examples:** [links]

## Proposal Summary

[Describe the proposed product direction, workflow, screen, capability, or control in one short paragraph.]

## Product Fit Thesis

This fits Tickoni because [explain why the idea advances financial control, policy-gated proposals, auditability, replayability, bounded spend, high-throughput CaseOps, or safe money-adjacent action].

It is not just [generic automation / generic agent UX / trading performance / developer productivity / dashboard polish] because [explain the Tickoni-specific consequence, control surface, or operator trust outcome].

## Tickoni Fit Checklist

| Fit question                                                                                                                                            | Answer |
| ------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| What financial or money-adjacent consequence does this help control?                                                                                    | ...    |
| Which user/operator trust problem does it reduce?                                                                                                       | ...    |
| How does it support policy-gated proposals instead of uncontrolled execution?                                                                           | ...    |
| What audit, evidence, or replay value does it create?                                                                                                   | ...    |
| What finance-native scope matters: account, beneficiary, wallet, rail, currency, market, venue, instrument, amount, exposure, frequency, approval path? | ...    |
| How does it keep agents off the direct money path?                                                                                                      | ...    |
| How does it avoid becoming generic agent automation or trading-alpha UX?                                                                                | ...    |

## User / Operator Problem

[State the real workflow pain. Prefer consumer-money, CaseOps, reviewer, compliance/risk, runtime operator, or partner-control language.]

## Current Gap

[Explain what Tickoni cannot yet show, enforce, prove, or route. Keep this separate from implementation design.]

## Proposed Product Behavior

When [actor] is in [workflow/context], Tickoni should [visible behavior], so that [trust/control/replay outcome].

Expected behavior:

* ...
* ...
* ...

## Why Now

[Explain why this should enter the backlog now instead of later. Tie it to roadmap sequencing, demo value, product risk, partner clarity, or missing proof.]

## Example Scenario

```text
Given:  [financial event, intent, case, policy, or operator context]
When:   [the user, operator, or agent attempts the workflow]
Then:   [Tickoni-visible result: proposal, denial, approval-required state, evidence packet, replay proof, impact view, etc.]
```

## Product Boundaries

### In Scope

* ...
* ...
* ...

### Out Of Scope

* ...
* ...
* ...

### Authority Boundary

| Action class        | Proposed boundary                                                     |
| ------------------- | --------------------------------------------------------------------- |
| Observe             | [Allowed / scoped / N/A]                                              |
| Analyze             | [Allowed / scoped / N/A]                                              |
| Draft               | [Allowed / review required / N/A]                                     |
| Recommend           | [Allowed / evidence required / N/A]                                   |
| Propose             | [Policy check required / approval required / N/A]                     |
| Prepare             | [Signed envelope / sandbox only / N/A]                                |
| Execute             | [Denied / paper only / sandbox only / privileged executor only / N/A] |
| Override/Administer | [Denied / out of scope]                                               |

## Fit Against Product Principles

| Principle                                        | How this proposal fits | Concern / open question |
| ------------------------------------------------ | ---------------------- | ----------------------- |
| Financial consequence over generic tool access   | ...                    | ...                     |
| Proposal-first agent behavior                    | ...                    | ...                     |
| Policy gates and approval paths                  | ...                    | ...                     |
| Audit-grade evidence                             | ...                    | ...                     |
| Deterministic replay or replay-safe substitution | ...                    | ...                     |
| Bounded model/tool/adapter spend                 | ...                    | ...                     |
| Fail-closed behavior                             | ...                    | ...                     |
| No live side effects unless explicitly approved  | ...                    | ...                     |

## Evidence Needed To Promote

* [ ] A concrete workflow or demo moment exists.
* [ ] The controlled financial consequence is clear.
* [ ] The relevant policy/capability boundary is known or decision-needed.
* [ ] The proposal has an observable audit/replay/evidence value.
* [ ] Non-goals are explicit.
* [ ] The idea can be split into independently testable epic/story work.

## Risks And Anti-Fit Signals

This should not move forward if:

* it mainly improves generic agent productivity without a financial-control outcome
* it encourages autonomous money movement, ledger posting, payout approval, account freezing, or risk override
* it makes trading performance, alpha, PnL, rank, or gamification the dominant product object
* it cannot identify the relevant policy, approval, evidence, or replay boundary
* it requires live external side effects before Tickoni has a safe paper/sandbox path
* it duplicates an epic/story that already covers the same outcome

## Open Decisions

| Decision | Options | Owner / next step |
| -------- | ------- | ----------------- |
| ...      | ...     | ...               |

## Graduation Path

If accepted, this should become:

* [ ] Epic: [when it spans multiple stories and delivers a complete product increment]
* [ ] Story: [when it is independently implementable and verifiable]
* [ ] Documentation: [when it clarifies positioning, policy, capability, or operator behavior]
* [ ] Decision record: [when it primarily resolves a product/architecture/policy choice]

Suggested next artifact:

* [ ] Create epic using `epic-template.md`
* [ ] Create story using `story-template.md`
* [ ] Create/update product positioning doc
* [ ] Create capability/policy decision
* [ ] Keep in backlog with notes
* [ ] Reject with rationale
