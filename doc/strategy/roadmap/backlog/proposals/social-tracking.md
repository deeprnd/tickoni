# Backlog Proposal: Social Tracking And Copy Feed

**Candidate issue type if accepted:** epic
**Candidate labels:** [`social` `investing` `trust` `enhancement`]
**Related docs / examples:** doc/strategy/roadmap/milestones/m11.md, doc/knowledge/architecture.md

## Proposal Summary

A social tracking layer on top of M12's thesis and money-decision feed: users can follow other users, view leaderboards of policy-compliant behavior, join guilds around shared investment themes, and copy-thought workflows where every copied template is re-evaluated against the copier's own capability envelope. The social signals (following, leaderboards, guild membership) are built on top of the same audit-replay infrastructure that M12 already requires — they surface what Tickoni has already recorded, they do not generate new financial consequences.

## Product Fit Thesis

This fits Tickoni because it extends M12's "browse -> inspect -> copy" surface with explicit trust primitives: follow (who am I trusting?), guilds (what shared policy envelope are we optimizing for?), and leaderboards (who has the most consistent policy-compliant proposal history?). The social layer is purely observational and informational — it never creates financial consequences, never executes anything, and always routes copies through `tkpoly` capability re-evaluation. The product risk is controlled because the social signals are derived from audit records, not from PnL or performance claims.

It is not just a generic social / copy-trading UX because the ranking and visibility signals are policy-compliance outcomes, not returns. Leaderboards rank by audit quality, policy pass rate, and proposal discipline — not by returns, alpha, or risk-taking. The "copy" action is always a re-evaluated proposal, never a direct execution.

## Tickoni Fit Checklist

| Fit question | Answer |
| --- | --- |
| What financial or money-adjacent consequence does this help control? | None. The social layer itself has no financial consequence. Every copied template still flows through `tkpoly` capability re-evaluation with the copier's own envelope. |
| Which user/operator trust problem does it reduce? | It reduces blind-copy risk by surfacing policy compliance signals alongside every published thesis or money-decision card, so the copier can see whether the original author operated within policy before deciding to copy. |
| How does it support policy-gated proposals instead of uncontrolled execution? | Copies become proposals. Leaderboard ranking is based on policy pass rate and audit quality, not returns. Guild membership is scoped to a shared capability envelope. No social action triggers execution. |
| What audit, evidence, or replay value does it create? | Every follow, guild join, copy, and leaderboard snapshot is recorded as an audit event. The social feed is reconstructable from audit records. Leaderboard data is deterministic from the audit log. |
| What finance-native scope matters: account, beneficiary, wallet, rail, currency, market, venue, instrument, amount, exposure, frequency, approval path? | Each copied card carries the copier's full capability envelope (account, instrument, amount, venue, sector, approval path). Guild scope is defined by the shared capability envelope (e.g., "US large-cap ETFs only, max $5k/mo, no crypto"). |
| How does it keep agents off the direct money path? | Agents are observers and drafters in this flow. They can surface social recommendations but cannot initiate copies or execute trades. All copies become proposals that require the user's acceptance and policy check. |
| How does it avoid becoming generic agent automation or trading-alpha UX? | Rankings are policy-compliance metrics, not PnL or performance metrics. No return data is displayed. No "top traders" — only "most policy-consistent proposers." No real-time signals, no alpha. |

## User / Operator Problem

The M12 feed lets users browse and copy thesis cards and money-decision cards. But browsing a single card in isolation doesn't answer two critical questions a copier needs:

1. "Can I trust the author's judgment, or did they just get lucky?"
2. "What kind of person (or organization) consistently operates within policy?"

Without social signals derived from audit records, the copy action is no safer than blindly trusting any single card. The user needs a way to see who has a history of policy-compliant behavior, who operates in the same investment scope they care about, and who has proven discipline.

## Current Gap

Tickoni can currently show a thesis card or money-decision card in isolation. It cannot show:

- Who published it and whether that publisher has a history of policy compliance.
- Whether a publisher operates within the same scope (assets, amounts, venues) as the copier.
- A ranked view of policy-compliant proposers.
- A way for users to find peers operating in the same investment domain.
- A structured way to express "I want to follow people who operate like me."

## Proposed Product Behavior

When a user browses the social thesis and money-decision feed, Tickoni should surface policy-derived social signals alongside each card, so that the copier can make an informed trust decision before copying.

Expected behavior:

* **Follow**: User can follow another user (or organization) whose thesis and money-decision cards they find useful. The follow is a user-level preference, not an auto-copy. Following a user adds their published cards to the copier's personal feed.
* **Card-level trust signal**: Each published card shows the author's policy compliance score (pass rate on their proposals), the policy version used, and whether the original proposal was within scope. This is derived from `tkaudt` records.
* **Leaderboard**: A deterministic, audit-derived ranking of publishers by policy compliance quality (pass rate, proposal discipline, evidence completeness). Rankings never include returns, PnL, or alpha metrics. A copier can browse the leaderboard to find publishers with a strong track record of policy-consistent behavior.
* **Guilds**: Users can create or join guilds around shared investment themes or policy scopes (e.g., "US Large-Cap Dividend ETFs, max $5k/mo, no leverage"). Guild membership is visible. Guild cards are authored by guild members and are tagged with the guild scope. A guild defines a shared capability envelope and a shared policy version — not a shared wallet or shared execution authority.
* **Copy with social context**: When copying a card, the copier sees not just the card content but the author's compliance history, the guild (if any), and a summary of whether the original scope is compatible with the copier's own envelope. The copy is always re-evaluated by `tkpoly`.
* **Replay**: The entire social feed — follows, guild joins, copies, leaderboard state — is replayable from audit records. Leaderboard rankings are computed deterministically from the audit log at any point in time.

## Why Now

M12 already establishes the core "browse -> inspect -> copy" mechanism and the re-evaluation boundary. Adding social tracking in the same milestone avoids creating a second trust boundary later. The audit infrastructure (`tkaudt`) and policy engine (`tkpoly`) are already in scope for M12, so the social signals are derived from existing infrastructure, not new trust surfaces. Delaying social features to a later milestone would mean rebuilding the feed UI twice or creating a separate trust model that conflicts with M12's re-evaluation discipline.

## Example Scenario

```text
Given:  User A has a history of 47 policy-compliant proposals across 6 months,
        all in scope for US large-cap ETFs, with a 94% policy pass rate.
        User B wants to copy a thesis card about dividend ETFs but does not
        know whether User A operates within their own policy limits.
When:   User B browses the social feed, sees User A's thesis card, and
        notices the policy compliance signal (94% pass rate, 6-month history,
        US large-cap scope). User B follows User A and views the leaderboard
        showing User A in the top 10 for "policy compliance quality."
Then:   User B clicks "copy" on the thesis card. The copy is re-evaluated
        against User B's capability envelope by tkpoly. If any dimension
        (amount, asset class, venue, sector) exceeds User B's limits, tkpoly
        returns require_approval or deny. The re-evaluated result is recorded
        in tkaudt with User B's capability envelope, policy version, and
        a reference to the original card and author.
```

## Product Boundaries

### In Scope

* Following (user-to-user or organization-to-user subscription, not auto-copy)
* Social signals derived from audit records (policy pass rate, proposal history, scope tags)
* Leaderboard ranking by policy compliance quality only
* Guilds as shared-scope communities (no shared execution, no shared wallets)
* Card-level trust signals (author compliance history, scope compatibility)
* Copy workflow with social context (the copy itself is unchanged from M12: re-evaluated by tkpoly)
* Replay of social events from audit records

### Out Of Scope

* PnL, returns, alpha, or performance ranking
* Real-time social signals or live trading signals
* Social chat, messaging, or comments
* Social login or identity federation (users are identity-authenticated already)
* Shared wallets, shared execution, or shared custody
* Social trading (auto-executing others' trades)
* Gamification (badges, streaks, XP, points)
* Anonymous or pseudonymous publishing
* Social sentiment analysis or mood indicators
* Automated follower discovery or recommendation

### Authority Boundary

| Action class | Proposed boundary |
| --- | --- |
| Observe | Allowed — anyone can browse the feed, leaderboards, and guild listings |
| Analyze | Allowed — any user can inspect the audit-derived signals behind any card |
| Draft | Allowed — any user can draft a thesis card or money-decision card |
| Recommend | Allowed — social signals (follows, guilds) are recommendations, not directives |
| Propose | Policy check required — copying a card creates a proposal that flows through tkpoly |
| Prepare | Denied — no social action prepares or pre-approves execution |
| Execute | Denied — social tracking has no execution path; execution (when enabled) goes through tkexec with policy and approval |
| Override/Administer | Denied — social features cannot override policy or approval |

## Fit Against Product Principles

| Principle | How this proposal fits | Concern / open question |
| --- | --- | --- |
| Financial consequence over generic tool access | Social signals have zero financial consequence; copies still flow through tkpoly | None |
| Proposal-first agent behavior | Agents can surface social recommendations but copies become proposals, not execution | Need to ensure agents don't auto-follow or auto-copy without user intent |
| Policy gates and approval paths | Leaderboard ranking is based on policy compliance, not returns | Define the exact ranking formula — pass rate? evidence quality? proposal discipline? |
| Audit-grade evidence | All social events are audit records; leaderboards are deterministic from audit log | Leaderboard recomputation cost at scale |
| Deterministic replay or replay-safe substitution | Social feed is reconstructable from audit records | Snapshot consistency for leaderboard at replay time |
| Bounded model/tool/adapter spend | Social signals are computed from audit data, no model calls needed | None |
| Fail-closed behavior | If audit data is missing, social signals default to "unknown" (no ranking) | How to handle missing audit data gracefully |
| No live side effects unless explicitly approved | Social actions (follow, guild join, copy) have no side effects beyond feed ordering and audit recording | Copy must always require the re-evaluation gate, even if the source card looks compatible |

## Evidence Needed To Promote

* [ ] A concrete demo moment exists where a user browses, inspects social signals, follows, and copies a card with policy re-evaluation.
* [ ] The leaderboard ranking formula is defined and auditable (not "top performers" disguised as "top compliant").
* [ ] The guild scope mechanism is clear — how is a guild's shared envelope defined, enforced, and communicated?
* [ ] The proposal has observable audit/replay value (social events are reconstructable from audit logs).
* [ ] Non-goals are explicit (no PnL, no gamification, no chat, no auto-execution).
* [ ] The idea can be split into independently testable epic/story work.

## Risks And Anti-Fit Signals

This should not move forward if:

* it mainly improves generic social UX without a financial-control outcome
* leaderboard rankings implicitly surface PnL, returns, or risk-taking (even if not explicitly labeled)
* it encourages blind-copying under the illusion of trust (social signal != financial guarantee)
* it cannot identify the relevant policy, approval, evidence, or replay boundary for social actions
* guilds evolve into shared-custody or shared-execution arrangements
* it duplicates M12's core copy workflow instead of extending it with social trust signals
* it makes social engagement metrics (likes, comments, follower count) the ranking signal

## Open Decisions

| Decision | Options | Owner / next step |
| --- | --- | --- |
| Leaderboard ranking formula | (a) Policy pass rate only, (b) Composite: pass rate + evidence quality + proposal discipline, (c) Custom per-guild | Product / Milestone owner |
| Guild ownership | (a) Open join (anyone can join), (b) Curated (guild owner approves), (c) Scope-bound (join only if copier's envelope matches guild scope) | Product / Milestone owner |
| Leaderboard refresh frequency | (a) Real-time from audit log, (b) Periodic snapshot, (c) On-demand query | Engineering / Milestone owner |
| Follow mechanics | (a) One-way (like Twitter), (b) Mutual consent, (c) Scope-bound (can only follow within same guild scope) | Product / Milestone owner |
| Anonymity | (a) Identity-published (real name or org name), (b) Pseudonymous, (c) Anonymous | Product / Milestone owner |

## Graduation Path

If accepted, this should become:

* [x] Epic: spans multiple stories (follow, leaderboard, guilds, social signals, social copy) and delivers a complete social-tracking product increment within M12
* [ ] Story: follow and card-level trust signals
* [ ] Story: leaderboard ranking and display
* [ ] Story: guild creation, membership, and scope tagging
* [ ] Story: social copy — copy workflow with social context
* [ ] Documentation: social tracking positioning and trust model
* [ ] Decision: leaderboard ranking formula
* [ ] Decision: guild scope and join mechanics
* [ ] Keep in backlog with notes
* [ ] Reject with rationale

Suggested next artifact:

* [ ] Create epic using `epic-template.md`
* [ ] Create stories using `story-template.md`
* [ ] Create/update product positioning doc
* [ ] Create capability/policy decision for leaderboard ranking
* [ ] Keep in backlog with notes
* [ ] Reject with rationale
