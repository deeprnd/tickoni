<!--
Tickoni backlog proposal.

Use this template when an idea is not ready to become an epic or story yet.
A backlog proposal answers: why does this belong in Tickoni?

It should be product-fit first, implementation-light. Do not turn this into an
acceptance-criteria document. If the proposal is accepted, graduate it into an
epic or story using the relevant template.
-->

# Backlog Proposal: YouTube Research Monitor

**Candidate issue type if accepted:** epic
**Candidate labels:** [`agents` | `audit` | `investing` | `operations` | `platform` | `security` | `trust` | `documentation`]
**Related docs / examples:** [`doc/strategy/roadmap/backlog/proposals/youtube-research-monitor.md` (source), `doc/knowledge/architecture.md`, `doc/strategy/positioning.md`, `doc/strategy/capabilities.md`]

## Proposal Summary

A user-directed YouTube monitoring and summarization capability that reads only channels the authenticated user subscribes to, detects new videos, fetches available metadata and captions via the official YouTube Data API, produces source-grounded summary signals, and routes those signals through Tickoni's audit, capability, and CaseOps surfaces. No transcript storage, no model training, no trade recommendations, no auto-execution. The product position is a research assistant that summarizes selected YouTube videos, links back to the source video, does not train models on the content, does not expose full transcript downloads, and frames outputs as "what the creator said" rather than trading advice.

Monitoring scope is limited to user-subscribed channels. The app may recommend which subscribed channels to monitor and may let the user add channels manually, but it does not crawl arbitrary channels or bulk-scrape.

## Product Fit Thesis

This fits Tickoni because it extends the research-intelligence surface into a governed channel that feeds analyst-sourced commentary into the investment proposal pipeline. YouTube financial commentary, earnings-call recap videos, macro analysis, and technical deep-dives are a real source of market narrative. Tickoni's job is not to replace human judgment; it is to capture the narrative in a way that is auditable, replayable, policy-gated, and distinct from the raw source material.

The Tickoni-specific consequence is threefold:

1. **Audit trail for external research inputs.** Every video summary ingested into Tickoni becomes a sourced, hash-chained event that CaseOps can surface alongside trading proposals, payment intents, and compliance signals. An operator reviewing a trade ticket can see which analyst videos informed the recommendation and trace each claim back to a timestamped source link.

2. **Policy-gated signal ingestion.** The monitoring capability becomes a new financial-domain capability (e.g. `research_signal.youtube_ingest`) with explicit scope constraints: user-subscribed channels only, summary-only output, no transcript storage, no model training, no export of raw captions. This is a concrete instantiation of the "bounded model/tool access" invariant — the YouTube Data API call is a governed adapter path, not a raw credential exposed to agents.

3. **Replay-safe research capsule.** If a trading proposal is audited or replayed, the YouTube-sourced evidence can be replayed deterministically: same video, same summary, same timestamp references. External effects (API calls) are disabled during replay; stored summaries serve as the substitution capsule.

It is not just "a YouTube scraper" or "generic agent automation" because the entire capability is constrained by finance-native capability envelopes, audit-chained evidence records, and CaseOps visibility. A generic scraper does not answer "which analyst video informed this trade proposal?" or "can we replay exactly what evidence the agent used?" Tickoni does.

## Tickoni Fit Checklist

| Fit question | Answer |
| --- | --- |
| What financial or money-adjacent consequence does this help control? | Ingests external research signals into the investment proposal pipeline with policy-gated boundaries: summary-only, no transcript storage, no auto-execution, explicit "not investment advice" framing. |
| Which user/operator trust problem does it reduce? | Operators can trace which external research influenced each proposal. Analyst commentary is not a black box; every claim links back to a timestamped video segment. Reduces reliance on unvetted or untraceable alpha sources. |
| How does it support policy-gated proposals instead of uncontrolled execution? | YouTube ingest capability has explicit scope: user-subscribed channels only, summary-only output, no full caption export. All summaries route through `tkmodl` for model governance, through `tktool`/`tkadpt` for adapter dispatch, and are recorded in `tkaudt` before any agent references them. |
| What audit, evidence, or replay value does it create? | Every video summary becomes a content-addressed evidence record with video URL, title, publish date, summary hash, timestamp references, and source attribution. Replay capsules substitute the summary instead of re-calling the YouTube API. |
| What finance-native scope matters: account, beneficiary, wallet, rail, currency, market, venue, instrument, amount, exposure, frequency, approval path? | Account: user's YouTube subscription scope (OAuth-scoped). Market: the markets/sectors/instruments discussed in the video. Instrument: specific tickers or asset classes referenced. Exposure: narrative influence weight, not direct capital allocation. Approval path: ingest capability requires policy check; summaries are evidence, not execution. |
| How does it keep agents off the direct money path? | YouTube summaries are research evidence, not execution triggers. They feed into proposal context via `tkaudt` and CaseOps. Agents reference summaries during investigation but cannot trigger trades, payments, or ledger entries based on video content alone. |
| How does it avoid becoming generic agent automation or trading-alpha UX? | The capability is explicitly scoped to user-subscribed channels only. Outputs are "what the creator said" with source links and timestamps — not recommendations, not trade signals, not alpha rankings. The product boundary is research intelligence, not alpha generation. |

## User / Operator Problem

**Investment analyst / operator:** When reviewing a trading proposal or conducting due diligence on a market event, they need to know which external research sources informed the analysis. YouTube is a major channel for financial commentary, earnings analysis, and macro research — but it is unstructured, untraceable, and hard to audit. Analysts waste time manually watching, bookmarking, and timestamping relevant video segments. They need a governed way to monitor relevant channels, detect new content, get structured summaries, and attach those summaries as auditable evidence to cases and proposals.

**Compliance / risk operator:** When auditing a trade or investment decision, they need to see the full evidence trail. If a trading analyst recommended a position partly based on an earnings-call recap video, compliance needs to verify that the video was relevant, the summary was accurate, and no unauthorized claims were made. Currently, there is no Tickoni surface for tracing external video research to proposal evidence.

**Consumer user:** The user wants to stay informed about financial markets through YouTube channels they follow. They do not want to be bombarded with random crypto shills, trading gurus, or unvetted sources. They want curated, subscription-based monitoring with clear boundaries on what the app does with the content.

## Current Gap

Tickoni has no external-source monitoring capability. The current Phase 0 tiles (`tkings`, `tknorm`, `tkdedu`, `tkpoly`, `tkaudt`, `tkrepl`, `tkmetr`, `tkdiag`) handle internal financial event streams but have no ingestion path for structured external research data. There is no:

- YouTube or external-source adapter (`tkadpt` path for YouTube Data API)
- Research-signal capability definition in the capability model
- CaseOps surface for viewing YouTube-sourced evidence alongside other research
- Audit schema for external-source ingestion events
- Replay capsule behavior for research-sourced summaries
- Policy boundaries for research signal ingestion (what sources are allowed, what output is permitted)
- Model governance path for generating summaries (who calls the LLM, how summaries are bounded, how summaries are stored)

## Proposed Product Behavior

When the authenticated user is in the `research_monitor` workflow, Tickoni should:

1. Authenticate the user's YouTube/Google account via OAuth using the YouTube Data API.
2. Read the user's subscribed channels (OAuth-scoped — no arbitrary channel crawling).
3. Optionally recommend which subscribed channels are most relevant to the user's investment focus (market, sector, instrument).
4. Let the user select which subscribed channels to monitor.
5. Periodically check monitored channels for new videos using the YouTube Data API.
6. For each new video, fetch metadata: title, URL, thumbnail, publish date, description.
7. Attempt to obtain subtitles/captions (officially available only for videos where the user has download rights or captions are publicly available; viewer OAuth does not grant caption-download for arbitrary subscribed channels).
8. Generate a source-grounded summary signal using the video metadata and available captions.
9. Route the summary through Tickoni's governance: `tkmodl` for model access, `tkaudt` for audit recording, `tkevid` for evidence attachment (when available).
10. Surface the summary in CaseOps as auditable research evidence linked to the source video with timestamps.

Expected behavior:

* No full transcript text is stored — only summary and timestamp references.
* No model training or fine-tuning on video content.
* No long-term transcript database or full transcript export.
* No bulk random scraping — only user-subscribed, user-selected channels.
* No personalized trade recommendations — outputs framed as "what the creator said," not investment advice.
* No auto-execution of trades based on video content.
* Clear "not investment advice" disclaimers on all YouTube-sourced content.
* Every summary event is audit-chained and replayable.
* Source links and timestamps are always present alongside summaries.

## Why Now

1. **Research-signal ingestion is a gap in the V1 pipeline.** The current roadmap covers investment intent, payment guardrails, and portfolio management. But the investment workflow begins with information gathering — and YouTube commentary is a primary source of real-time market narrative for retail and institutional investors alike. Closing this gap makes the investment pipeline complete: research → analysis → proposal → approval → (paper) execution.

2. **Demonstrates Tickoni's auditability advantage over generic scrapers.** A YouTube scraper is a commodity. Tickoni's value is wrapping that capability in audit, replay, and CaseOps visibility. If Tickoni does not own this surface, it loses ground on the "trace every evidence source" promise.

3. **Low-risk entry point for external-source capability.** The YouTube monitor is scoped, policy-gated, and non-executing. It does not move money, post ledger entries, or place trades. It is a research tool that feeds evidence, not execution. This makes it a safe V1 candidate that demonstrates the broader pattern for external-source ingestion (podcasts, news feeds, regulatory filings) without financial risk.

4. **Aligns with consumer-finance positioning.** Tickoni's V1 narrative leads with investment intent. A consumer-facing YouTube research monitor is the kind of tool a retail investor or independent analyst would actually use — while the backend enforces the Tickoni control layer.

## Example Scenario

```text
Given: A user has authenticated their YouTube account and selected 5 subscribed channels
       to monitor (e.g., a financial news channel, an earnings-analysis channel, a macro
       strategy channel, a technical-analysis channel, a crypto-research channel)
When:  A new video is published on the earnings-analysis channel about Apple Q3 results,
       and the monitor detects it via the YouTube Data API
Then:  Tickoni fetches the video metadata and available captions, generates a source-
       grounded summary ("the creator discussed Q3 revenue miss, margin compression in
       Services, and guided for iPhone weakness in Q4"), records it as an audit-chained
       evidence event with video URL and timestamp references, and surfaces it in CaseOps
       as research evidence. The summary is tagged with market "US", instrument "AAPL",
       and sector "Information Technology" based on the extracted content. No trade
       recommendation is produced. The summary is available for reference during trading
       proposal review but does not trigger any action.
```

## Product Boundaries

### In Scope

* OAuth authentication via Google/YouTube account
* Reading user's subscribed channels via YouTube Data API
* User selection of which subscribed channels to monitor
* Periodic detection of new videos on monitored channels
* Fetching video metadata (title, URL, thumbnail, publish date, description)
* Caption/subtitle download (only when available via official API)
* Summary generation via governed model path (`tkmodl`)
* Audit recording of ingestion events (`tkaudt`)
* Evidence attachment (when `tkevid` is available)
* CaseOps surface for viewing YouTube-sourced evidence
* Timestamp references alongside summaries
* Source-linking back to the original video

### Out Of Scope

* Bulk scraping of arbitrary channels
* Full transcript storage or export
* Model training or fine-tuning on video content
* Real-time live-stream monitoring
* Audio-only podcast ingestion (future separate capability)
* Sentiment analysis or alpha scoring
* Automated trade signal generation
* Portfolio impact scoring based on YouTube sentiment
* Social media monitoring beyond YouTube
* Video content moderation or fact-checking
* Subscription management (user selects channels manually)
* Video recommendation beyond subscribed-channel context

### Authority Boundary

| Action class | Proposed boundary |
| --- | --- |
| Observe | Allowed — read user subscriptions, detect new videos, fetch metadata via YouTube Data API |
| Analyze | Allowed — extract market/instrument/sector tags from video content, generate summaries |
| Draft | Allowed — draft summary text with timestamp references |
| Recommend | Allowed — but only as "what the creator said," not as investment advice |
| Propose | Policy check required — `research_signal.youtube_ingest` capability envelope with channel allowlist, summary-only constraint |
| Prepare | N/A — no action envelopes for research ingestion |
| Execute | Denied — YouTube monitor never executes financial actions; it produces evidence |
| Override/Administer | Denied — out of scope |

## Fit Against Product Principles

| Principle | How this proposal fits | Concern / open question |
| --- | --- | --- |
| Financial consequence over generic tool access | YouTube monitor feeds research evidence into the investment proposal pipeline. It is not a generic "watch YouTube" tool — it is a governed research-signal source for financial decisions. | Open: how to quantify "narrative influence" without tipping into alpha scoring? |
| Proposal-first agent behavior | Summaries are evidence, not proposals or recommendations. They sit in CaseOps for operator review but do not trigger execution. | Open: what if a summary contains a direct trading call from the creator? We classify it as evidence, not Tickoni advice. |
| Policy gates and approval paths | `research_signal.youtube_ingest` capability with explicit scope: user-subscribed channels only, summary-only output, no transcript storage. | Decision needed: should the capability require explicit user approval to activate, or is subscription-level consent sufficient? |
| Audit-grade evidence | Every summary becomes a content-addressed audit record with video URL, timestamp references, summary hash, and source attribution. | Open: hash of what exactly? Summary text + metadata? |
| Deterministic replay or replay-safe substitution | Replay capsules store the summary text; replay does not re-call the YouTube API. | Open: captions may change (creator edits). Should replay use the caption snapshot at time of ingest, or always pull fresh captions? |
| Bounded model/tool/adapter spend | YouTube Data API calls are bounded to monitored channels + periodic poll intervals. Model calls for summary generation are bounded by `tkmodl` token budgets and context limits. | Open: what poll interval is reasonable? Daily? Hourly? Channel-specific? |
| Fail-closed behavior | If YouTube API is unavailable, the monitor skips polling and logs the failure. It does not fall back to unofficial scraping methods. If captions are unavailable, it falls back to metadata-only summary with a clear disclaimer. | Open: should metadata-only summaries be flagged differently in CaseOps? |
| No live side effects unless explicitly approved | YouTube ingest never executes financial actions. It only reads data and produces audit records. | None — this is inherent to the design. |

## Evidence Needed To Promote

* [ ] A concrete workflow or demo moment exists (e.g., user selects channels → monitor detects video → summary appears in CaseOps).
* [ ] The controlled financial consequence is clear (research evidence feeding investment proposals, not alpha generation).
* [ ] The relevant policy/capability boundary is defined (`research_signal.youtube_ingest` with channel allowlist, summary-only constraint).
* [ ] The proposal has an observable audit/replay/evidence value (summary hash, timestamp refs, source links).
* [ ] Non-goals are explicit (no bulk scraping, no transcript storage, no auto-execution).
* [ ] The idea can be split into independently testable epic/story work (OAuth setup, channel monitoring, summary generation, audit recording, CaseOps surface).

## Risks And Anti-Fit Signals

This should not move forward if:

* it drifts into alpha generation, sentiment scoring, or automated trading signals based on video content
* it encourages bulk channel scraping or monitoring non-subscribed sources
* it stores full transcripts or enables full transcript export
* it trains models on video content
* it cannot define a clear audit trail that traces YouTube evidence to proposal decisions
* it requires live external side effects (YouTube API calls) during replay without a substitution strategy
* it duplicates existing research-capability work (e.g., news-feed ingestion, regulatory filing ingestion)

## Open Decisions

| Decision | Options | Owner / next step |
| --- | --- | --- |
| Capability name | `research_signal.youtube_ingest` vs `research.youtube.monitor` vs `external_source.youtube` | Product + policy team |
| Channel selection model | User selects from subscribed channels only vs. user can add arbitrary channels (with policy gating) | Product — default: subscribed-only |
| Summary granularity | One summary per video vs. segmented summaries by timestamp topic | Product — default: one summary per video with timestamp refs |
| Caption availability handling | Skip videos without captions vs. metadata-only summary with disclaimer | Engineering + product |
| Poll frequency | Global poll interval (e.g., every 6 hours) vs. per-channel frequency | Engineering — default: global configurable interval |
| Replay caption strategy | Use snapshot at ingest time vs. always pull fresh captions | Engineering — default: snapshot at ingest for deterministic replay |
| OAuth scope boundary | YouTube subscription scope vs. full Google account scope | Engineering — default: YouTube API scope only |
| Integration with `tkmodl` summary path | Use existing model gateway path vs. dedicated research-summary model path | Engineering — default: use existing `tkmodl` path |

## Graduation Path

If accepted, this should become:

* [x] Epic: spans OAuth authentication, channel monitoring, summary generation, audit recording, and CaseOps surface integration
* [ ] Stories: decomposed per story template (see Story Breakdown below)
* [ ] Documentation: update `doc/strategy/positioning.md` with YouTube monitor capability, update `doc/strategy/capabilities.md` with `research_signal.youtube_ingest` definition, update `doc/knowledge/tile-topology.md` with `tkytb` tile (YouTube adapter) placement

Suggested next artifact:

* [ ] Create epic using `doc/strategy/templates/epic-template.md`
* [ ] Create stories under the epic using `doc/strategy/templates/story-template.md`
* [ ] Create capability definition in `doc/strategy/capabilities.md`
* [ ] Update tile topology with new YouTube adapter tile if needed

## Story Breakdown (Pre-Graduation)

If this epic is accepted, it should decompose along these lines:

```
V?.?.S1: YouTube OAuth and channel read — authenticate user via YouTube Data API, read subscribed channels, present selectable list to user.
V?.?.S2: Channel monitoring poll — periodic detection of new videos on user-selected channels, metadata fetch.
V?.?.S3: Caption retrieval and summary generation — download available captions, generate source-grounded summary via `tkmodl` path, with metadata-only fallback.
V?.?.S4: Audit recording and evidence attachment — record ingestion events in `tkaudt`, attach evidence in `tkevid` (when available), hash-chained audit trail.
V?.?.S5: CaseOps surface — display YouTube-sourced research evidence alongside other case evidence, with source links, timestamps, and "not investment advice" framing.
V?.?.S6: Policy and capability definition — define `research_signal.youtube_ingest` capability in `tkpoly`, establish channel-scope constraints, summary-only boundaries, and approval path.
V?.?.S7: Replay support — deterministic replay of YouTube ingest events with summary substitution capsules, no external API calls during replay.
V?.?.S8: Evidence, demo, and release closure — fixtures, demo flow, quality gates, documentation.
```
