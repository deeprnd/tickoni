# Backlog Proposal: Mac And Windows Consumer Runtime Support

**Candidate issue type if accepted:** epic
**Candidate labels:** `platform`, `operations`, `security`, `trust`
**Related docs / examples:** [`development.md`](../../../../execution/development.md), [`architecture.md`](../../../../knowledge/architecture.md), [`firedancer.md`](../../../../execution/contribution/firedancer.md), [`V2.14`](../../epics/v2.14.md), [Hermes installer](https://hermes-agent.nousresearch.com/install.sh), [Hermes PowerShell installer](https://hermes-agent.nousresearch.com/install.ps1), [OpenClaw README](https://github.com/openclaw/openclaw)

## Proposal Summary

Tickoni should support consumer-grade Mac and Windows machines without hiding that the current Firedancer-derived runtime is Linux-first. The backlog direction is to define an official Mac/Windows support model, package it with clear version identity, publish install/update scripts, and introduce runtime version checks that preserve policy gates, audit, replay, paper/sandbox behavior, and CaseOps trust surfaces while clearly separating full Linux tile performance from portable consumer modes.

## Product Fit Thesis

This fits Tickoni because a consumer-money product cannot require every user, reviewer, or partner evaluator to run a tuned Linux workstation before they can inspect a policy-gated proposal, replay proof, or paper action. Mac and Windows support expands who can run Tickoni locally while keeping financial authority bounded and visible. Clear versioning and installation checks are part of that trust surface: users must know which Tickoni build produced a proposal or replay artifact.

It is not just developer productivity because the consequence is product trust: a user on commercial hardware should be able to verify what Tickoni would allow, deny, require approval for, and replay before any live money path exists.

## Tickoni Fit Checklist

| Fit question                                                                                                                                            | Answer |
| ------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| What financial or money-adjacent consequence does this help control?                                                                                    | It lets consumer users inspect investing, payment, crypto, and ledger proposals locally before any live execution path is available. |
| Which user/operator trust problem does it reduce?                                                                                                       | It removes the hidden assumption that trust proofs only work on Linux hosts, while still making degraded platform guarantees explicit. |
| How does it support policy-gated proposals instead of uncontrolled execution?                                                                           | Mac/Windows support should start with paper/sandbox and proposal-only flows, not privileged execution or direct adapter authority. |
| What audit, evidence, or replay value does it create?                                                                                                   | Portable runs should emit the same proposal hashes, policy decisions, audit records, and replay proofs as Linux for deterministic fixture flows. |
| What finance-native scope matters: account, beneficiary, wallet, rail, currency, market, venue, instrument, amount, exposure, frequency, approval path? | The same scope dimensions as Linux matter; platform support must not reduce policy-envelope requirements. |
| How does it keep agents off the direct money path?                                                                                                      | The support tier should deny live execution by default and route any model, tool, or adapter access through existing Tickoni boundaries. |
| How does it avoid becoming generic agent automation or trading-alpha UX?                                                                                | The visible object is platform support for safe money decisions and replay, not faster agent autonomy, ranking, PnL, or alpha discovery. |

## User / Operator Problem

A consumer user, reviewer, or partner evaluator may have a MacBook, Windows laptop, or Windows desktop as their primary machine. Today the repo states that Firedancer-derived runtime work requires x86-64 Linux, and the justfile only offers a macOS container workaround. That blocks a product experience where a user can run the money-decision loop on normal commercial hardware and operating systems.

The install experience is also not yet product-grade for demos. A user cannot install a named Tickoni version, run a preflight/version check, and know whether their local runtime is supported for a specific demo scenario.

## Current Gap

Tickoni cannot yet name a supported Mac or Windows runtime tier. The active docs and code point to Linux as the only native Firedancer runtime target.

Observed Linux-only or Linux-first dependencies:

* Build target assumptions: Firedancer build recipes use Linux machine profiles such as `linux_gcc_x86_64`, `linux_clang_x86_64`, and Linux ARM compile lanes; Tickoni links Zig code to Firedancer C libraries.
* CPU and memory-ordering assumptions: Firedancer documentation calls out x86-64 Linux, LP64 layout, x86 TSO, SSE/AVX metadata publication, and hot paths that must not be ported by search-and-replace.
* Shared-memory workspace setup: `fd_shmem_cfg`, hugetlbfs, huge/gigantic pages, NUMA placement, `/sys/kernel/mm/hugepages`, `/dev/shm`, memlock, and `prlimit` appear in build/test/runtime guidance.
* Sandbox and isolation: Tickoni exposes `src/tickoni/c_abi/sandbox.zig` over Firedancer sandbox APIs, which rely on Linux concepts such as seccomp-BPF, Landlock, namespaces, capabilities, uid/gid switching, rlimits, and `prctl`.
* Process and tile lifecycle: Firedancer process supervision and diagnostics use Linux process primitives, CPU affinity, `/proc`, signals, clone/fork-style startup, and crash-only tile assumptions.
* Networking substrate: Firedancer networking paths include Linux netlink/rtnetlink, XDP/AF_XDP, eBPF, io_uring, and Linux socket/filter headers. These are not native Mac or Windows APIs.
* Repository command surface: current `just` recipes use Linux commands such as `nproc`, `free`, `sudo`, `prlimit`, `/sys` hugepage reads, and Linux container images. The macOS `dock` recipe is a Linux container path, not native macOS support.
* Packaging gap: there is no published consumer installer, no platform-specific install script, no version-check command, no update-check path, and no explicit demo support matrix by Tickoni version.

The Phase 0 payment pipeline intentionally avoids hugetlbfs, Tango workspaces, and sandbox privileges in tests by using in-process threads and heap-backed queues. That creates a possible portability path for consumer demos, but it is not yet a product commitment or support tier.

## Proposed Product Behavior

When a consumer user or partner evaluator is on Mac or Windows, Tickoni should present an explicit supported runtime mode so that safe money-decision demos, policy decisions, audit output, and replay proofs can run without requiring a native Linux workstation.

Expected behavior:

* Tickoni documents support tiers instead of implying one runtime fits every OS.
* The full Firedancer tile runtime remains a Linux production/high-throughput tier unless a later decision approves a native port.
* Mac and Windows users can run deterministic paper/sandbox flows through an approved portable mode, container mode, WSL2 mode, or VM mode.
* Any degraded mode is visible in CLI, CaseOps, audit metadata, and docs where it affects isolation, performance, or external side-effect guarantees.
* Portable modes preserve deterministic event hashes, policy outcomes, proposal hashes, replay capsules, and no-bypass model/tool/adapter boundaries for fixture-backed flows.
* Every distributed artifact exposes a clear semantic version, build id, platform tier, git revision or release digest, and supported demo matrix.
* Installers perform a preflight check before setup and a version check after setup, failing closed when the host cannot support the selected runtime tier.
* Demo commands refuse to run when the installed Tickoni version is below the minimum version required by the demo, unless the command is explicitly a documentation-only preview.
* Install/update scripts are published from an official Tickoni domain or release channel, with checksums, signatures or attestations, and a documented manual verification path.

## Packaging And Installation Direction

Tickoni should be packaged as a consumer demo product, not only as a source checkout. The initial package does not need to enable live financial side effects, but it must make version, provenance, and platform support obvious.

Consumer packages must include only the Firedancer tiles and source files that Tickoni actually reuses — queues, topology, workspaces, sandboxing, metrics, diagnostics, and `fd_http_server`. Solana validator tiles, RPC schemas, and unrelated Firedancer code must be excluded from distributed artifacts to keep the package surface accurate, auditable, and free of unrelated runtime assumptions.

Expected package behavior:

* `tickoni --version` prints the Tickoni version, build id, git revision, target OS/architecture, runtime tier, and whether the full Firedancer tile runtime is available.
* `tickoni doctor` or equivalent validates host OS, architecture, container/WSL2/VM support, required local tools, demo fixture availability, model/mock mode, and disabled live-execution status.
* `tickoni demo ...` checks the installed version against a demo manifest before running.
* `tickoni update` or a documented reinstall path preserves user-created local evidence while updating the runtime only from an official release channel.
* Installer output tells the user where code, config, logs, audit/replay artifacts, and uninstall hooks live.
* Release notes name newly introduced demo versions and any breaking replay, audit, policy, or fixture changes.

Comparable installer ergonomics to study:

```bash
# Hermes Agent Linux/macOS example
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
```

```powershell
# Hermes Agent Windows PowerShell example
irm https://hermes-agent.nousresearch.com/install.ps1 | iex
```
These are examples of user-facing installation shape, not authority models to copy. Tickoni's installer must be stricter because it produces money-adjacent proposals and audit/replay artifacts. Piped shell and PowerShell installers should have a documented safer path that downloads the installer, verifies checksum/signature, and then runs it.

## Demo And Security Preparation

Before Mac/Windows support graduates, a demo-ready distribution should include:

* A published support matrix by Tickoni version, OS, architecture, runtime tier, and supported demo workflows.
* A minimum-version manifest for each demo, including required fixtures and replay schema version.
* A signed release artifact or verifiable checksum for each installer and binary package.
* A clear default of fixture/mock providers, paper trading, sandbox adapters, and live execution denied.
* A preflight that detects unsupported host capabilities instead of silently downgrading isolation.
* A warning and refusal path for unsupported direct source builds used as consumer demos.
* Separate user-scoped install locations by default; admin/root installation should be opt-in and justified.
* Logs, audit JSONL, replay capsules, and local config stored in documented per-user directories.
* Uninstall instructions that remove binaries and services without deleting audit/replay evidence unless explicitly requested.
* A no-secrets default: installers must not ask for broker, payment, crypto, approved execution ledger, or live model-provider credentials to run the demo.
* Installer telemetry disabled by default unless a later privacy decision explicitly approves opt-in diagnostics.

## Why Now

M2 moves Tickoni from in-process logical tiles toward real process and shared-memory topology. That is the right time to decide whether Mac/Windows support is a first-class consumer mode, a container/WSL2 packaging path, or a later native-port effort. Deferring the decision until after the Linux process topology hardens risks baking Linux-only assumptions into the product surface.

## Example Scenario

```text
Given:  A Windows user wants to evaluate a USD 2,000 investment thesis in paper mode.
When:   They run the Tickoni consumer runtime on their local machine.
Then:   Tickoni shows the supported platform tier, builds a policy-checked proposal,
        records audit and replay artifacts, denies live execution, and reports any
        platform-specific isolation or performance downgrade explicitly.
```

## Product Boundaries

### In Scope

* Define Mac and Windows support tiers for consumer-money demos, paper flows, audit, and replay.
* Define package version, build metadata, release digest, installer provenance, and demo compatibility checks.
* Publish and document official install/update/uninstall scripts for Linux/macOS and Windows.
* Introduce a version-check and host-preflight command before user-facing demos are promoted.
* Inventory Linux-only runtime assumptions that affect consumer support, isolation, or determinism.
* Decide whether first support should be native portable mode, Linux container, WSL2, VM packaging, or a combination.
* Keep Linux as the full high-throughput Firedancer runtime unless a separate architecture decision approves a native port.
* Make platform mode visible in operator and audit surfaces where it affects trust.
* Define which Firedancer tiles and source files are included in consumer packages; exclude Solana-specific tiles, RPC schemas, and any Firedancer code that Tickoni does not reuse.
* Ensure the engine code coverage badge measures only the Firedancer code actually reused by Tickoni; it must not reflect coverage of the full Firedancer project, including Solana and unrelated source.

### Out Of Scope

* Porting the entire Firedancer hot path to macOS or Windows in this proposal.
* Weakening audit, replay, capability envelopes, or adapter boundaries for portability.
* Enabling live trading, payments, crypto transfers, ledger posting, or privileged execution on Mac/Windows consumer modes.
* Requesting production financial credentials during demo install or first run.
* Shipping opaque self-updating background services without explicit version and provenance checks.
* Replacing Tickoni's tile architecture with a generic cross-platform web backend.
* Claiming throughput parity with Linux before measured evidence exists.

### Authority Boundary

| Action class        | Proposed boundary |
| ------------------- | ----------------- |
| Observe             | Allowed in supported portable/container/WSL2 modes with platform tier recorded. |
| Analyze             | Allowed for fixture-backed and scoped local flows through `tkmodl` and governed mocks. |
| Draft               | Allowed for proposals and explanations; review state remains explicit. |
| Recommend           | Allowed only with evidence, policy scope, and replay-safe captured inputs. |
| Propose             | Policy check required; paper/sandbox only on consumer modes until approved otherwise. |
| Prepare             | Sandbox or signed-envelope simulation only; no hidden host privilege escalation. |
| Execute             | Denied for consumer Mac/Windows modes unless a future `tkexec` support decision approves a privileged path. |
| Override/Administer | Denied / out of scope. |

## Fit Against Product Principles

| Principle                                        | How this proposal fits | Concern / open question |
| ------------------------------------------------ | ---------------------- | ----------------------- |
| Financial consequence over generic tool access   | Platform support is scoped to money-decision visibility and proof, not generic automation. | Which workflows must run on day one: investing only, or payment/crypto fixtures too? |
| Proposal-first agent behavior                    | Mac/Windows modes remain proposal-first and paper/sandbox only. | Need a visible product marker when a platform cannot enforce Linux tile isolation. |
| Policy gates and approval paths                  | Capability envelopes and policy outcomes must be identical for deterministic fixture flows. | Need conformance tests comparing Linux and portable modes. |
| Audit-grade evidence                             | Platform tier, isolation tier, and degraded guarantees should be recorded with audit metadata. | Decide exact audit field or metadata carrier later. |
| Deterministic replay or replay-safe substitution | Replay remains external-effect-free and should be the primary cross-platform proof. | Need to decide which runtime sources can differ without breaking replay hashes. |
| Bounded model/tool/adapter spend                 | Model/tool access stays behind Tickoni gateways; local modes can default to mocks. | Real local model servers on Mac/Windows need a separate support matrix. |
| Fail-closed behavior                             | Unsupported host capabilities should block privileged modes instead of silently downgrading. | Need preflight UX for missing WSL2, Docker Desktop, Colima, or required VM support. |
| No live side effects unless explicitly approved  | Consumer Mac/Windows support starts with no live effects. | Future live execution on non-Linux should require a separate decision record. |
| Versioned product proof                          | Installed version, demo manifest version, policy version, fixture version, and replay schema version are visible. | Need a single source of truth for release metadata. |

## Evidence Needed To Promote

* [ ] A concrete consumer workflow or demo moment exists on Mac and Windows.
* [ ] The controlled financial consequence is clear.
* [ ] The relevant policy/capability boundary is known or decision-needed.
* [ ] The proposal has an observable audit/replay/evidence value.
* [ ] A versioned installer, preflight, and version-check behavior are defined.
* [ ] The demo support matrix names OS, architecture, runtime tier, and minimum Tickoni version.
* [ ] A secure manual verification path exists for users who do not want to pipe remote scripts into a shell.
* [ ] Non-goals are explicit.
* [ ] The idea can be split into independently testable epic/story work.

## Risks And Anti-Fit Signals

This should not move forward if:

* it mainly improves generic developer convenience without a consumer-money trust outcome
* it encourages autonomous money movement, ledger posting, payout approval, account freezing, or risk override
* it makes native portability more important than audit, replay, fail-closed behavior, or no-bypass boundaries
* it hides degraded sandboxing, memory isolation, networking, or performance guarantees from users
* it encourages users to pipe remote install scripts without offering checksum/signature verification
* it permits ambiguous `latest` installs for reproducibility-sensitive demos without recording the resolved version
* it requires live external side effects before Tickoni has a safe paper/sandbox path
* it duplicates an epic/story that already covers the same outcome

## Open Decisions

| Decision | Options | Owner / next step |
| -------- | ------- | ----------------- |
| First Mac support path | Native portable Tickoni mode, Linux container through Docker/Colima, lightweight VM, or hybrid | Product/architecture decision before M2 topology hardening |
| First Windows support path | **RESOLVED: Native portable Tickoni on Windows.** Chosen in S4.T5 — no WSL2, Docker Desktop, or VM. CI runs directly on Windows 2025 and Windows 11 ARM64 runners. | Done — S4.T5 |
| Support tier language | Full Linux runtime vs portable proof runtime vs unsupported host | Define in docs and CLI preflight before accepting implementation work |
| Installer channel | Official shell/PowerShell scripts, package manager, signed binary releases, container image, or combined approach | Product/security decision before public demo distribution |
| Version source of truth | `build.zig.zon`, generated release manifest, git tag, signed metadata file, or release registry | Build/release decision before adding `tickoni --version` |
| Version enforcement | Hard minimum per demo, warning-only compatibility, or strict manifest lock | Product/security decision; default should fail closed for demos |
| Installer verification | SHA256 checksums, Sigstore, minisign, GPG, platform package signatures, or multiple | Security decision before publishing scripts |
| Sandbox substitute | Linux-only seccomp/Landlock, host-native sandbox equivalents, or no privileged native mode | Security decision; do not infer silently |
| Shared-memory substitute | Keep Firedancer workspaces Linux-only, use heap/normal-page queues for portable proof mode, or design an OS abstraction | Architecture decision tied to `V2.14` |
| Cross-platform conformance | Hash/replay fixture equivalence, CLI smoke tests, CaseOps paper-demo tests, or full integration matrix | Testing decision before graduating to stories |

## Graduation Path

If accepted, this should become:

* [x] Epic: when it spans platform preflight, support tiers, portable runtime behavior, packaging, version checks, docs, and conformance tests.
* [ ] Story: when one independently verifiable support tier is selected.
* [x] Documentation: when it clarifies supported OS, support tiers, and non-goals.
* [x] Decision record: when it resolves native vs container/WSL2/VM support and sandbox guarantees.

Suggested next artifact:

* [x] Create epic using `epic-template.md`
* [ ] Create story using `story-template.md`
* [ ] Create/update product positioning doc
* [x] Create capability/policy decision
* [ ] Keep in backlog with notes
* [ ] Reject with rationale
