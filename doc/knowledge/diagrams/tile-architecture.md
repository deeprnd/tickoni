# Tickoni Tile Architecture

Target tile architecture: small single-purpose tiles with explicit links, a
deterministic event path with no AI in it, a bounded agent harness and operator
control beside it, every boundary event audited, all on Firedancer
infrastructure.

This diagram shows architecture, not delivery status. For what currently runs,
see [`tile-delivery-status.md`](../../execution/tile-delivery-status.md).

- Each external system is reachable only through its owning tile: model
  providers through `tkmodl`, financial APIs through `tkadpt`, the execution
  ledger through `tkexec`, and the CaseOps UI through `tkapi`.
- `tkexec` acts only after a `tkpoly` decision and human approval.
- `tkrepl` replays captured capsules with external effects disabled.

```mermaid
flowchart TB
  subgraph events["Deterministic event path · no AI in the critical path"]
    direction LR
    src(["financial events"])
    tkings["<b>tkings</b><br/>ingest · source offsets"]
    tknorm["<b>tknorm</b><br/>canonical normalize"]
    tkdedu["<b>tkdedu</b><br/>idempotent dedupe"]
    tkcase["<b>tkcase</b><br/>deterministic cases"]
    tkpoly["<b>tkpoly</b><br/>capability policy"]
    src --> tkings --> tknorm --> tkdedu --> tkcase --> tkpoly
  end

  subgraph agents["Bounded agent harness · proposal-first"]
    direction LR
    tkdisp["<b>tkdisp</b><br/>bounded dispatch"]
    tkagnt["<b>tkagnt</b><br/>agent worker<br/>no direct shell or network"]
    tkmodl["<b>tkmodl</b><br/>model gateway · budgets"]
    tktool["<b>tktool</b><br/>tool broker"]
    tkadpt["<b>tkadpt</b><br/>signed adapters"]
    llm(["LLM servers<br/>model providers"])
    apis(["financial APIs"])
    tkdisp --> tkagnt
    tkagnt --> tkmodl --> llm
    tkagnt --> tktool --> tkadpt --> apis
  end

  subgraph control["Operator control · approved actions only"]
    direction LR
    ui(["CaseOps UI"])
    tkapi["<b>tkapi</b><br/>CaseOps API"]
    tkexec["<b>tkexec</b><br/>approved execution"]
    ledger[("execution ledger")]
    ui --> tkapi
    tkapi -- "human approval" --> tkexec
    tkexec --> ledger
  end

  subgraph record["Audit, evidence, replay, observability"]
    direction LR
    tkaudt["<b>tkaudt</b><br/>hash-chained audit"]
    tkevid["<b>tkevid</b><br/>content-addressed evidence"]
    tkrepl["<b>tkrepl</b><br/>replay · effects off"]
    tkmetr["<b>tkmetr</b><br/>metrics"]
    tkdiag["<b>tkdiag</b><br/>diagnostics"]
    tkaudt ~~~ tkevid ~~~ tkrepl ~~~ tkmetr ~~~ tkdiag
  end

  subgraph substrate["Firedancer infrastructure"]
    direction LR
    tango["Tango shared-memory queues"]
    topo["topology · workspaces"]
    cnc["heartbeat · halt"]
    sandbox["sandbox<br/>seccomp · Landlock"]
    http["fd_http_server"]
    crash["crash-only tile processes"]
    tango ~~~ topo ~~~ cnc ~~~ sandbox ~~~ http ~~~ crash
  end

  events -. "cases" .-> agents
  events -. "tkpoly decisions" .-> control
  events -. "events, decisions" .-> record
  agents -. "model, tool, adapter calls" .-> record
  control -. "approvals, actions" .-> record
  record ~~~ substrate

  classDef tile fill:#e8f1ff,stroke:#2b5fb4,stroke-width:1.5px,color:#0b1f44
  classDef external fill:#ffffff,stroke:#7a869a,stroke-width:1px,color:#2d3748
  classDef infra fill:#f3f4f6,stroke:#6b7280,stroke-width:1px,color:#111827

  class tkings,tknorm,tkdedu,tkcase,tkpoly,tkdisp,tkagnt,tkmodl,tktool,tkadpt,tkapi,tkexec,tkaudt,tkevid,tkrepl,tkmetr,tkdiag tile
  class src,llm,apis,ui,ledger external
  class tango,topo,cnc,sandbox,http,crash infra

  style events fill:#f7faff,stroke:#2b5fb4,color:#0b1f44
  style agents fill:#f7faff,stroke:#2b5fb4,color:#0b1f44
  style control fill:#f7faff,stroke:#2b5fb4,color:#0b1f44
  style record fill:#f7faff,stroke:#2b5fb4,color:#0b1f44
  style substrate fill:#f9fafb,stroke:#6b7280,color:#111827
```

## Sources

- [`tile-topology.md`](../tile-topology.md): tile IDs, responsibilities, event
  flow, reuse boundary
- [`tile-orchestration.md`](../tile-orchestration.md): lifecycle, heartbeat,
  crash-only behavior, Firedancer substrate reuse
- [`architecture.md`](../architecture.md): system layers, governed external
  systems, AI outside the deterministic critical path
