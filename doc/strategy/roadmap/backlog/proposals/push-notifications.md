<!--
Tickoni backlog proposal template.

Use this template when an idea is not ready to become an epic or story yet.
A backlog proposal answers: why does this belong in Tickoni?

It should be product-fit first, implementation-light. Do not turn this into an
acceptance-criteria document. If the proposal is accepted, graduate it into an
epic or story using the relevant template.
-->

# Backlog Proposal: Push Notifications And Device Subscriptions

**Candidate issue type if accepted:** epic
**Candidate labels:** [`platform` | `security` | `investing` | `operations`]
**Related docs / examples:**
- `doc/strategy/roadmap/epics/v4.5.md` — V5.5 explicitly excludes push notifications as out of scope
- `doc/strategy/roadmap/backlog/proposals/portfolio-valuation-queue.md` — mentions "subscription delivery" as an open decision
- `doc/execution/contribution/tickoni-engine-issues.md` — `fd_http_server` / `tkapi` security surface
- `doc/knowledge/architecture.md` — `tkapi` tile, attached systems
- `doc/knowledge/tile-topology.md` — `tkapi` tile definition, `tkmetr` tile
- `doc/execution/observability.md` — operator signals
- `doc/execution/telemetry.md` — diagnostics

## Proposal Summary

Build a server-side subscription and push notification system that delivers Tickoni
governance events — valuation completions, rebalance suggestions, policy decisions,
and case updates — to user devices (desktop browser, mobile app, or CLI) in
real-time. The system uses `tkapi` WebSocket subscriptions as the primary transport,
with optional push notification bridges (browser Push API, FCM/APNs) as extension
points. Every notification carries an immutable event reference from Tickoni's
audit chain, so recipients can verify that the notification is tied to a real,
policy-checked financial event — not a synthetic alert.

## Product Fit Thesis

This fits Tickoni because it closes the feedback loop for the consumer investing
workflow. V5.5 delivers watchlist management and automatic DCF valuation, but
the user currently has to poll or refresh CaseOps to see when a valuation completes
or a rebalance suggestion arrives. Push notifications transform Tickoni from a
"check-back-and-see" system into a proactive governance platform: the user is
told when a valuation finishes, when a rebalance drift exceeds their limits, and
when a case needs operator review. The notification itself is a deterministic
pointer into the audit chain, not a opaque alert — recipients can click through to
the exact event, replay capsule, and policy decision.

It is not just a generic notification service or "send a push when something happens"
because the notification system must conform to Tickoni's trust model: every
notification carries the source event hash, capability scope, and policy outcome
from the audit chain. The subscription system itself must be auditable — who
subscribed, what topics they opted into, when notifications were delivered or
failed — and replay-safe. A subscription delivery failure must not silently
suppress governance events; it must log to `tkaudt` and surface in CaseOps.

## Tickoni Fit Checklist

| Fit question | Answer |
| --- | --- |
| What financial or money-adjacent consequence does this help control? | Notification delivery is gated by the same policy outcomes (`allow`, `deny`, `require_approval`) that govern the underlying events. A user receives a notification about a valuation completion or rebalance proposal only because those events passed policy checks — the notification is a derivative of the governance state, not an independent signal. |
| Which user/operator trust problem does it reduce? | Eliminates the trust gap where a user or operator receives a "valuation complete" alert but cannot verify it against the audit chain. Every notification is cryptographically tied to its source event, preventing spoofed alerts from appearing legitimate. |
| How does it support policy-gated proposals instead of uncontrolled execution? | Notifications carry capability envelope metadata (actor, role, workflow, case/run id, scope, policy version) extracted from the audit record. The subscription system never executes or proposes — it only relays metadata references to the actual audit events stored in `tkaudt`. |
| What audit, evidence, or replay value does it creates? | Every subscription creation, topic subscription, notification dispatch, delivery attempt, and failure is recorded in `tkaudt`. The replay system substitutes captured notification payloads so replay never sends real pushes. Notification delivery state (delivered, failed, expired) is queryable in CaseOps. |
| What finance-native scope matters: account, beneficiary, wallet, rail, currency, market, venue, instrument, amount, exposure, frequency, approval path? | Subscriptions are scoped to event types (valuation.complete, rebalance.propose, case.approval_required, policy.decision) and optional filters (portfolio_id, ticker, case_id). Each notification carries the financial scope of its source event for display and verification. |
| How does it keep agents off the direct money path? | Agents cannot create or modify subscriptions. Subscriptions are managed through the operator UI or through governed API endpoints accessed via `tkapi` with explicit `subscription.manage` capability scope. Agents produce events; subscriptions relay them. |
| How does it avoid becoming generic agent automation or trading-alpha UX? | The notification system is a transport layer, not a decision layer. It does not generate, summarize, or rank events — it relays metadata references. There is no "notification preference tuning by agents" or "smart notification grouping by LLM." |

## User / Operator Problem

A consumer investor has Tickoni valuing companies on their watchlist. A DCF
valuation completes, a rebalance suggestion appears, or a case requires operator
review. Currently, the user must open Tickoni CaseOps, browse the board, and hope
they notice the new event. In a mobile or desktop context, the user may not have
CaseOps open at all. This creates a trust and usability gap: the user wants Tickoni
to tell them when governance-relevant events occur, but they also want to be able to
verify that the notification is tied to a real, policy-checked financial event — not
a synthetic alert or a fabricated summary.

The CaseOps operator has the same problem in reverse: when a case they are monitoring
receives a new valuation, policy decision, or replay result, they need to know
immediately so they can review it. CaseOps polling works for a single active session,
but breaks down for cross-device workflows or when the operator steps away.

## Current Gap

Tickoni has:
- `tkapi` with `fd_http_server` providing the CaseOps API surface (HTTP/WebSocket).
- V5.5 watchlist management and automatic valuation queue.
- `tkaudt` append-only, hash-chained audit records.
- `tkmetr` tile for metrics.
- An explicit open decision in V5.5 about "subscription delivery: WebSocket to CaseOps API vs event-sourced analytics store table vs both."
- V5.5 explicitly marks "push notifications or device push" as out of scope.

Tickoni does not have:
- Any subscription or push notification transport layer.
- WebSocket-based real-time event delivery to clients.
- A `notification.dispatch` or `subscription.manage` capability scope.
- Notification delivery auditing (who received what, when, did it succeed).
- Push notification bridges (browser Push API, FCM/APNs) for mobile/desktop push.
- A topic/event type taxonomy beyond what `tkaudt` already produces.
- Replay-safe notification substitution.
- Subscription state storage or durability.

## Proposed Product Behavior

When [user/operator] configures a subscription in Tickoni CaseOps or through a
governed `tkapi` endpoint, Tickoni should deliver real-time notifications for
selected event types, so that [the user receives timely, verifiable governance
alerts without polling, and every notification is cryptographically tied to its
source audit event].

Expected behavior:

* Subscription creation: the user or operator creates a subscription through
  CaseOps, selecting which event types to receive (valuation.complete,
  rebalance.propose, case.approval_required, policy.decision) and optional
  filters (portfolio_id, ticker, case_id). The subscription is stored in
  the analytics store with a stable `subscription_id` and recorded in `tkaudt`.
* WebSocket delivery: `tkapi` opens a persistent WebSocket connection to the
  subscribed device/browser. When a matching event enters `tkaudt`, `tkapi`
  publishes a notification payload containing the event reference (hash, source
  offset, event type), capability scope (actor, role, workflow, case id, scope
  dimensions), and policy outcome.
* Push notification bridges: optional extensions to browser Push API, FCM
  (Android), and APNs (iOS) deliver notifications when the user's device is
  not actively connected via WebSocket. Push payloads carry only the event
  reference hash — the full detail is fetched from CaseOps when the user taps
  the notification.
* Notification verification: the user can verify any notification by opening
  CaseOps, which resolves the event reference hash to the full audit record,
  evidence packet, and replay capsule. This closes the trust loop: the
  notification is a pointer, not a summary.
* Delivery auditing: every dispatch attempt (success, failure, retry) is
  recorded in `tkaudt`. Failed deliveries are surfaced in CaseOps for
  operator review.
* Replay safety: replay runs substitute captured notification payloads and
  never send real pushes to any device or channel.

## Why Now

V5.5 closes the loop for watchlist-driven valuation but leaves the user in a
"check CaseOps" pattern. This is the minimum gap between a working governance
system and a usable consumer product. The infrastructure is already in place:
`tkapi` uses `fd_http_server` which supports WebSocket upgrades, V5.5 produces
the governance events (valuation completions, rebalance proposals), and `tkaudt`
provides the immutable audit chain that notifications reference. Adding
subscriptions and push notifications is the last step to make Tickoni's consumer
workflow feel real-time rather than poll-based.

The open subscription delivery decision in V5.5 is a blocker for M5 demo quality
if the demo requires showing real-time valuation completion to a user who is
not actively watching CaseOps. Adding this as a parallel or near-parallel
increment removes that blocker and demonstrates Tickoni's ability to govern
real-time event delivery — not just batch audit recording.

Additionally, the security considerations from `tickoni-engine-issues.md` about
`fd_http_server` WINDOW_UPDATE bounds mean that any WebSocket extension must be
designed with the same security discipline as the HTTP surface — this is an
opportunity to get it right early rather than retro-fitting security onto an
ad-hoc notification system.

## Example Scenario

```text
Given:  A user has subscribed to "valuation.complete" events for their "Growth"
        portfolio (portfolio_id = growth_001, tickers = [AMZN, AAPL, MSFT])
When:   The DCF valuation for AMZN completes and is recorded in tkaudt
Then:   Tickoni's tkapi publishes a WebSocket notification to the user's device
        containing: event_type=valuation.complete, event_hash=<tkaudt_hash>,
        portfolio_id=growth_001, ticker=AMZN, policy_outcome=allow,
        intrinsic_value_range=[175, 220], monte_carlo_ci=90
When:   The user is not actively browsing CaseOps (device in background)
Then:   A push notification (browser FCM/APNs) delivers: "AMZN valuation complete:
        $175–$220 (90% CI). Tap to review." — tapping opens CaseOps to the
        full valuation evidence card and replay capsule.
When:   A compliance operator replays the valuation with substituted outputs
Then:   No WebSocket or push notification is sent to any device. The replay
        capsule captures the notification payload that would have been sent,
        and replay output reports: "1 notification would have been dispatched,
        0 actually sent (replay mode)."
```

## Product Boundaries

### In Scope

* WebSocket subscription transport via `tkapi` (persistent connections, topic
  routing, payload formatting)
* Subscription CRUD: create/list/delete/update subscriptions with event type
  and filter configuration
* Subscription state storage: the analytics store subscription table with stable `subscription_id`,
  scoped to `tkapi` and `tkaudt`
* Basic event taxonomy: valuation.complete, rebalance.propose, case.approval_required,
  policy.decision, replay.complete
* Delivery auditing: every dispatch attempt recorded in `tkaudt` with outcome
* Replay-safe notification substitution: replay substitutes payloads, sends no
  real pushes
* CaseOps subscription management UI: configure, view, and delete subscriptions
* Notification verification: users can click from notification to full event
  record in CaseOps

### Out Of Scope

* Push notification bridge implementations (browser Push API, FCM, APNs) —
  these are future extensions after WebSocket transport is proven
* Notification grouping, summarization, or "digest" mode
* Notification priority, throttling, or rate limiting beyond basic backpressure
* Multi-channel delivery (email, SMS, Slack, Teams)
* Agent-driven notification management (agents cannot create/modify subscriptions)
* Notification analytics (open rate, click rate, delivery success rate dashboards)
* User preference profiles beyond event-type subscriptions (quiet hours,
  channel selection, digest frequency)
* Cross-device session sync for active WebSocket connections
* Notification scheduling or delayed delivery

### Authority Boundary

| Action class | Proposed boundary |
| --- | --- |
| Observe | Allowed — users can observe their own subscriptions; operators can observe case-related subscriptions |
| Analyze | Allowed — notification delivery state is deterministic from audit records |
| Draft | N/A — subscriptions are created, not drafted |
| Recommend | N/A — notification topics are user-configured, not agent-drafted |
| Propose | Policy check required — `subscription.manage` capability scope with actor/role/case scope |
| Prepare | N/A — subscriptions are metadata management, not action preparation |
| Execute | Allowed — dispatching a notification is a non-money-impacting execution |
| Override/Administer | Denied for agents — only operator/admin can manage subscriptions |

### Capability Scope

| Capability scope | Outcome |
| --- | --- |
| `subscription.manage` | User/operator can create, list, delete, update subscriptions |
| `subscription.observe` | User/operator can view their own subscriptions |
| `notification.dispatch` | System-internal scope for `tkapi` notification dispatch (not user-facing) |
| `subscription.override` | Denied — no override mechanism for subscription state |

## Fit Against Product Principles

| Principle | How this proposal fits | Concern / open question |
| --- | --- | --- |
| Financial consequence over generic tool access | Notifications are purely transport — they relay metadata references to real governance events. The value is in the event, not the delivery channel. | Must ensure notifications never become a "notification spam" vector that dilutes the signal of actual governance events. |
| Proposal-first agent behavior | Agents cannot create, modify, or suppress notifications. Only humans (users, operators) manage subscriptions. | What if an agent produces a high-severity policy.decision that should trigger an urgent notification? Can agents escalate, or only humans? |
| Policy gates and approval paths | Every notification carries the capability scope and policy outcome from its source audit record. A notification about a denied rebalance proposal shows `deny` alongside the proposal details. | Does the notification system need its own policy gate for delivery? E.g., can a subscription be created for an event the subscriber has no authority to view? |
| Audit-grade evidence | Every subscription lifecycle event (create, dispatch, failure) is recorded in `tkaudt`. The notification payload is a deterministic function of the audit record. | How large should the stored notification payload be in `tkaudt`? Storing full payloads per dispatch could bloat audit storage for high-volume event types. |
| Deterministic replay or replay-safe substitution | Replay substitutes captured notification payloads and never sends real pushes. This must be explicitly tested to verify no WebSocket connections are opened during replay. | Must ensure replay substitution is complete: not just the payload, but also the dispatch attempt record. What happens if replay substitutes a payload that was never actually captured? |
| Bounded model/tool/adapter spend | Notifications do not involve model/tool/adapter calls. They are pure event relay from `tkaudt` to `tkapi`. | N/A |
| Fail-closed behavior | If `tkapi` WebSocket delivery fails, the dispatch attempt is logged in `tkaudt` with failure status. The event is not suppressed — it is recorded as failed delivery. CaseOps surfaces failures for review. | What is the retry policy? Immediate retry with exponential backoff, or best-effort with operator review? |
| No live side effects unless explicitly approved | Notifications are the one allowed "live side effect" — they change the state of the user's device (ring, banner, badge) but not any financial state. This must be explicitly approved as a non-money-impacting side effect. | Is notification delivery itself a "live side effect" that requires explicit approval? Or is it considered a passive observation relay (like CaseOps polling) with no approval needed? |

## Evidence Needed To Promote

* [ ] A concrete WebSocket subscription flow can be demonstrated (create subscription -> event enters audit -> notification delivered).
* [ ] The notification payload structure is clearly defined and includes event hash, capability scope, and policy outcome.
* [ ] The `subscription.manage` and `notification.dispatch` capability scopes are defined in `tkpoly`.
* [ ] The proposal has an observable audit/replay/evidence value (full subscription lifecycle in `tkaudt`).
* [ ] Replay safety is proven: no notifications sent during replay, substitution is complete.
* [ ] Non-goals are explicit (no push bridges, no grouping, no agent management).
* [ ] The idea can be split into independently testable epic/story work.

## Risks And Anti-Fit Signals

This should not move forward if:

* it becomes a generic notification service without clear financial governance integration
* it encourages autonomous notification generation by agents (e.g., "notify me when X is profitable")
* notification delivery failures create audit gaps (events suppressed without recording the failure)
* it introduces a new persistent transport layer (WebSocket) that conflicts with Firedancer's polling-based tile lifecycle
* it requires live external push services (FCM, APNs) before Tickoni has a safe paper/sandbox path
* it duplicates an epic/story that already covers real-time event delivery through CaseOps
* the notification payload becomes so large that it bloats `tkaudt` audit storage
* subscription management by users introduces a new attack surface (subscription hijacking, unauthorized event forwarding)
* it becomes clear that users prefer polling-based CaseOps over push notifications, making the investment low-ROI

## Open Decisions

| Decision | Options | Owner / next step |
| --- | --- | --- |
| WebSocket vs HTTP polling for real-time delivery | WebSocket (persistent, bidirectional) vs HTTP long-polling (simpler, no persistent connections) vs SSE (unidirectional stream, simpler than WebSocket) | Platform: WebSocket is the natural extension of `fd_http_server` but requires connection lifecycle management. SSE may be simpler for notification-only (server-to-client) delivery. |
| Notification payload size in `tkaudt` | Full payload (event hash + capability scope + all scope dimensions + policy outcome) vs compact payload (event hash + event type only, full details fetched from CaseOps) | Audit: compact payload reduces storage bloat but breaks self-contained audit records. Full payload supports forensic reconstruction but may bloat audit chain for high-volume events. |
| Delivery retry policy | Best-effort (one attempt, logged in audit) vs retry with exponential backoff (3 attempts) vs immediate retry + operator review queue | Platform: retry increases complexity but improves UX. Best-effort is simpler but may frustrate users with failed deliveries. |
| Subscription ownership model | User-owned (each user manages their own subscriptions) vs portfolio-scoped (subscriptions tied to portfolio ownership) vs case-scoped (operators subscribe to case events) | Product: user-owned is simplest. Portfolio-scoped is more secure (subscribers can only see events for portfolios they own). Case-scoped is operator-only. |
| Push notification bridge timing | Parallel with WebSocket (build bridge in same epic) vs sequential (WebSocket first, bridge in follow-up) | Platform: sequential is lower risk and lets us validate the WebSocket transport before investing in push bridge complexity. |
| Replay substitution completeness | Substitute notification payload only vs substitute payload + log dispatch attempt vs substitute everything including failure state | Audit: substitute everything to fully mirror live behavior in replay. But requires capturing dispatch state, not just payload. |
| Notification verification model | Hash-pointer (notification contains event hash, user resolves in CaseOps) vs self-contained (notification contains all details, CaseOps shows full record) | Trust: hash-pointer is smaller and requires network call to verify. Self-contained is faster but may be stale if the underlying record changes. |

## Graduation Path

If accepted, this should become:

* [ ] Epic: spans multiple stories (WebSocket transport, subscription management, delivery auditing, replay safety, CaseOps UI)
* [ ] Story: each independently implementable and verifiable
* [ ] Documentation: updates to `tkapi` tile definition, security docs, and tile-topology
* [ ] Decision record: when it primarily resolves WebSocket vs SSE, payload size, or delivery retry policy

Suggested next artifact:

* [ ] Create epic using `epic-template.md` with the expanded scope from this proposal
* [ ] Create investigation story for WebSocket transport vs SSE tradeoff
* [ ] Create story for WebSocket subscription transport in `tkapi` (proof-of-concept)
* [ ] Create story for subscription CRUD and analytics store storage
* [ ] Create story for `subscription.manage` capability scope and policy definition
* [ ] Create story for delivery auditing in `tkaudt`
* [ ] Create story for replay-safe notification substitution
* [ ] Create story for CaseOps subscription management UI
* [ ] Keep in backlog with notes if WebSocket transport conflicts with Firedancer tile lifecycle
