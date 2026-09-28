# Tickoni Tile Topology

## Purpose

This document maps the validator tiles currently present in the repository and
defines a separate tile topology for Tickoni's fintech event harness.

The main design decision is:

> Do not morph Solana validator tiles into Tickoni product tiles. Add a new
> Tickoni topology with new tile names, stop linking validator tiles into the
> canonical `tickoni` binary, then delete validator-only source from the product
> branch.

This keeps Tickoni product work out of upstream-hot Firedancer paths and avoids
giving unrelated concepts the same tile identity.

For delivery status, implementation facts, and remaining debt, see
[`doc/execution/tile-delivery-status.md`](../execution/tile-delivery-status.md).

## Document Ownership

This document owns tile identity and topology: which Firedancer validator tiles
exist in the repository, which ones Tickoni excludes or adapts, which Tickoni
tile IDs exist, how product event flows are shaped, and which tile owns each
financial runtime responsibility.

It does not own tile launch lifecycle, Firedancer harness adapter semantics,
runtime-tier implementation, heartbeat/staleness behavior, or process
orchestration details. Those are owned by
[`tile-orchestration.md`](tile-orchestration.md).

## Current Repository State

The repository now has two Tickoni-relevant runtime paths:

1. The compatibility `tickoni` validator binary is still derived from the full
   Firedancer application. Its main program lives in
   [`src/app/firedancer/main.c`](../../src/app/firedancer/main.c), and its
   topology lives in
   [`src/app/firedancer/topology.c`](../../src/app/firedancer/topology.c).
2. The new Zig-native Tickoni scaffold exists under
   [`src/app/tickoni/`](../../src/app/tickoni/) and
   [`src/tickoni/`](../../src/tickoni/). It currently builds
   `tickoni-supervisor` through [`build.zig`](../../build.zig).

The legacy Frankendancer topology remains in
[`src/app/fdctl/topology.c`](../../src/app/fdctl/topology.c). It is gated behind
`FD_WITH_AGAVE=1` and is outside the canonical runtime path.

The inherited C topology ABI stores tile names in `char name[ 7UL ]`, so any
tile name registered through that ABI is limited to six characters. The
proposed runtime IDs below use a `tk` prefix and fit that limit. Configuration
and documentation should expose longer descriptive aliases.

## Existing Firedancer Tile Inventory

This inventory is based on the tile registrations in
[`src/app/firedancer/main.c`](../../src/app/firedancer/main.c),
[`src/app/firedancer/topology.c`](../../src/app/firedancer/topology.c),
[`src/app/fdctl/main.c`](../../src/app/fdctl/main.c), and
[`src/app/fdctl/topology.c`](../../src/app/fdctl/topology.c), then checked
against the actual tile implementations under `src/disco/`, `src/discof/`,
`src/discoh/`, and `src/flamenco/accdb/`.

The older fifteen-tile list in [`book/guide/tuning.md`](../../book/guide/tuning.md)
is useful historical context, but it is not the complete map of the current
full Firedancer application. `doc/organization.txt` is also only a directory
guide; the tables below are source-backed.

### Full Firedancer Tiles

Full Firedancer registers these tile kinds in the canonical C application.

| Tile | Source | Enabled by | Description |
| --- | --- | --- | --- |
| `net` | [`src/disco/net/xdp/fd_xdp_tile.c`](../../src/disco/net/xdp/fd_xdp_tile.c) | XDP network mode | Kernel-bypass network I/O tile. It receives packets from AF_XDP rings, demultiplexes incoming UDP flows into topology links, and transmits packets produced by other tiles. |
| `sock` | [`src/disco/net/sock/fd_sock_tile.c`](../../src/disco/net/sock/fd_sock_tile.c) | socket network mode | Socket-backed network I/O tile used instead of `net` when XDP is not selected. It batches `recvmmsg`/`sendmmsg` style UDP traffic into the same topology link model. |
| `netlnk` | [`src/disco/netlink/fd_netlink_tile.c`](../../src/disco/netlink/fd_netlink_tile.c) | conditional network support | Netlink listener for kernel route, neighbor, and interface state. XDP networking uses it to keep packet forwarding metadata current. |
| `metric` | [`src/disco/metrics/fd_metric_tile.c`](../../src/disco/metrics/fd_metric_tile.c) | always | Prometheus HTTP endpoint for tile metrics. It uses `fd_http_server` and renders `/metrics` from the topology metric workspaces. |
| `diag` | [`src/disco/diag/fd_diag_tile.c`](../../src/disco/diag/fd_diag_tile.c) | always | Runtime diagnostics tile. It samples tile process state, `/proc` CPU and interrupt data, selected validator health signals, and crash/death visibility. |
| `genesi` | [`src/discof/genesis/fd_genesi_tile.c`](../../src/discof/genesis/fd_genesi_tile.c) | startup | Genesis bootstrap tile. It loads or retrieves Solana genesis, validates expected hash and shred version, initializes the accounts database on bootstrap, and publishes genesis metadata. |
| `ipecho` | [`src/discof/ipecho/fd_ipecho_tile.c`](../../src/discof/ipecho/fd_ipecho_tile.c) | bootstrap/network | Shred-version discovery and serving tile. It queries entrypoints for the shred version and exposes an IP echo service for peers. |
| `gossvf` | [`src/discof/gossip/fd_gossvf_tile.c`](../../src/discof/gossip/fd_gossvf_tile.c) | cluster traffic | Gossip verifier/filter tile. It validates incoming gossip traffic, tracks peers, pings, stake, and shred versions, and forwards verified gossip updates. |
| `gossip` | [`src/discof/gossip/fd_gossip_tile.c`](../../src/discof/gossip/fd_gossip_tile.c) | cluster traffic | Solana gossip protocol tile. It maintains active-set gossip state, signs outgoing gossip through keyguard, sends gossip packets, and publishes contact, vote, duplicate-shred, stake, and snapshot-related updates. |
| `shred` | [`src/disco/shred/fd_shred_tile.c`](../../src/disco/shred/fd_shred_tile.c) | cluster traffic and leader path | Shred ingress, retransmit, and production tile. It handles shreds from network Turbine traffic and leader-produced microblocks, resolves FEC sets, and sends shreds to storage and the network. |
| `repair` | [`src/discof/repair/fd_repair_tile.c`](../../src/discof/repair/fd_repair_tile.c) | cluster traffic | Solana repair client tile. It identifies missing shred data, sends repair requests, processes repair responses, and feeds completed data toward replay. |
| `rserve` | [`src/discof/repair/fd_rserve_tile.c`](../../src/discof/repair/fd_rserve_tile.c) | optional repair server | Repair server tile. It answers other validators' repair requests from local shred storage and signs repair responses through keyguard. |
| `replay` | [`src/discof/replay/fd_replay_tile.c`](../../src/discof/replay/fd_replay_tile.c) | validator runtime | Fork replay coordinator. It reassembles FEC sets into entries, executes blocks through replay workers, maintains fork/bank progress, and emits consensus, repair, leader, and RPC notifications. |
| `accdb` | [`src/flamenco/accdb/fd_accdb_tile.c`](../../src/flamenco/accdb/fd_accdb_tile.c) | validator runtime | Accounts-database background tile. It owns account database background work, compaction coordination, disk/cache metrics, and read-only consumer epoch tracking. |
| `execrp` | [`src/discof/execrp/fd_execrp_tile.c`](../../src/discof/execrp/fd_execrp_tile.c) | replay execution | Replay execution worker. It executes single replay transactions against a selected Solana bank and accounts database fork, commits results, and reports execution metrics. |
| `tower` | [`src/discof/tower/fd_tower_tile.c`](../../src/discof/tower/fd_tower_tile.c) | consensus/voting | TowerBFT and fork-choice tile. It processes replayed vote accounts, gossip/TPU vote transactions, duplicate-shred proofs, rooted slots, and emits vote/reset/root decisions. |
| `txsend` | [`src/discof/txsend/fd_txsend_tile.c`](../../src/discof/txsend/fd_txsend_tile.c) | transaction forwarding | Transaction relay tile. It tracks leader schedule and gossip contact info, manages TPU UDP/QUIC sends, and forwards transactions to the current Solana leader. |
| `quic` | [`src/disco/quic/fd_quic_tile.c`](../../src/disco/quic/fd_quic_tile.c) | leader path | TPU server tile for Solana transaction ingress over TPU/UDP and TPU/QUIC. It defragments incoming streams and publishes complete transactions to verification. |
| `verify` | [`src/disco/verify/fd_verify_tile.c`](../../src/disco/verify/fd_verify_tile.c) | leader path | Transaction signature verification tile. It verifies Solana transaction signatures from QUIC, bundle, gossip vote, and txsend paths, then forwards accepted packets. |
| `dedup` | [`src/disco/dedup/fd_dedup_tile.c`](../../src/disco/dedup/fd_dedup_tile.c) | leader path | Solana transaction duplicate filter. It merges multiple verified transaction streams, prevents repeated signatures, and republishes a single deduplicated stream. |
| `resolv` | [`src/discof/resolv/fd_resolv_tile.c`](../../src/discof/resolv/fd_resolv_tile.c) | leader path | Address lookup and recent-blockhash resolution tile. It resolves Solana address lookup tables and transaction lifetimes before transactions can be packed. |
| `pack` | [`src/disco/pack/fd_pack_tile.c`](../../src/disco/pack/fd_pack_tile.c) | leader path | Leader scheduler tile. It groups verified transactions into microblocks, respects account write conflicts and cost limits, and dispatches executable work. |
| `execle` | [`src/discof/execle/fd_execle_tile.c`](../../src/discof/execle/fd_execle_tile.c) | leader path | Leader execution worker. It executes packed microblocks against the Solana runtime, commits account changes, and emits data for PoH and pack feedback. |
| `poh` | [`src/discof/poh/fd_poh_tile.c`](../../src/discof/poh/fd_poh_tile.c) | leader path | Full Firedancer proof-of-history tile. It orders executed microblocks, performs PoH hashing/tick publication, and sends entries to shred and replay. |
| `sign` | [`src/disco/keyguard/fd_sign_tile.c`](../../src/disco/keyguard/fd_sign_tile.c) | validator keys | Validator keyguard signing tile. It loads identity and authorized voter keys, validates key pairs, and signs approved validator messages for other tiles. |
| `rpc` | [`src/discof/rpc/fd_rpc_tile.c`](../../src/discof/rpc/fd_rpc_tile.c) | optional service | Solana JSON-RPC tile. It serves validator RPC reads over HTTP using replay/bank state and read-only accounts database access. |
| `solcap` | [`src/discof/capture/fd_solcap_tile.c`](../../src/discof/capture/fd_solcap_tile.c) | optional capture | Solana capture/export tile. It records selected Solana execution or ledger artifacts for capture/debug workflows. |
| `event` | [`src/disco/events/fd_event_tile.c`](../../src/disco/events/fd_event_tile.c) | optional service | Outbound event exporter. It sends Solana transaction, shred, signed-vote, genesis, ipecho, and tile lifecycle events to an external event service. |
| `bundle` | [`src/disco/bundle/fd_bundle_tile.c`](../../src/disco/bundle/fd_bundle_tile.c) | optional Jito path | Jito block-engine bundle client. It receives bundles over gRPC/TLS, manages pending bundled transactions, and feeds the verifier/leader path when in leader range. |
| `gui` | [`src/disco/gui/fd_gui_tile.c`](../../src/disco/gui/fd_gui_tile.c) | optional service | Full Firedancer validator GUI HTTP/WebSocket tile. It summarizes topology, networking, consensus, accounts database, voting, replay, and live validator metrics. |
| `snapct` | [`src/discof/restore/fd_snapct_tile.c`](../../src/discof/restore/fd_snapct_tile.c) | snapshot startup | Snapshot controller. It discovers/blacklists snapshot peers, coordinates snapshot source selection, and drives the snapshot load pipeline. |
| `snapld` | [`src/discof/restore/fd_snapld_tile.c`](../../src/discof/restore/fd_snapld_tile.c) | snapshot startup | Snapshot loader. It reads snapshot bytes from local files or HTTP/TCP and forwards the stream to decompression. |
| `snapdc` | [`src/discof/restore/fd_snapdc_tile.c`](../../src/discof/restore/fd_snapdc_tile.c) | snapshot startup | Snapshot decompressor. It decompresses or copies full and incremental snapshot streams and forwards uncompressed bytes. |
| `snapin` | [`src/discof/restore/fd_snapin_tile.c`](../../src/discof/restore/fd_snapin_tile.c) | snapshot startup | Snapshot ingest tile. It parses full/incremental Solana snapshots, loads accounts into the accounts database, initializes banks and caches, and emits startup metadata. |
| `snapwr` | [`src/discof/restore/fd_snapwr_tile.c`](../../src/discof/restore/fd_snapwr_tile.c) | snapshot startup | Snapshot accounts writer. It parses snapshot archive records, writes account data into partitioned accounts storage, and reports snapshot write metrics. |

Full Firedancer also allocates Solana-specific shared objects such as
`accdb`, `banks`, `progcache`, `txncache`, `fec_sets`, and `store`. These
objects are not all tiles, and they should not become Tickoni's application
database.

### Frankendancer-Only Tiles

Frankendancer is the hybrid Agave/Firedancer validator path. It keeps the C
networking and leader pipeline tiles but bridges execution, PoH, storage, and
GUI data through Agave-hosted components.

| Tile | Source | Enabled by | Description |
| --- | --- | --- | --- |
| `resolh` | [`src/discoh/resolh/fd_resolh_tile.c`](../../src/discoh/resolh/fd_resolh_tile.c) | hybrid leader path | Agave-hosted address lookup and blockhash resolution bridge. It prepares transactions for pack using recent blockhash and lookup-table state supplied from Agave. |
| `bank` | [`src/discoh/bank/fd_bank_tile.c`](../../src/discoh/bank/fd_bank_tile.c) | hybrid execution | Agave bank execution bridge. It receives packed microblocks, calls Agave bank ABI functions to execute/commit transactions, and returns execution results. |
| `pohh` | [`src/discoh/pohh/fd_pohh_tile.c`](../../src/discoh/pohh/fd_pohh_tile.c) | hybrid PoH | Hybrid proof-of-history and Agave bridge. It coordinates leader transitions, PoH hashing, microblock ordering, Agave bank handoff, and plugin/gui messages. |
| `store` | [`src/discoh/store/fd_store_tile.c`](../../src/discoh/store/fd_store_tile.c) | hybrid blockstore | Agave blockstore bridge. It inserts trusted and network FEC-set shreds into Agave blockstore and updates block identifiers for completed leader slots. |
| `plugin` | [`src/discoh/plugin/fd_plugin_tile.c`](../../src/discoh/plugin/fd_plugin_tile.c) | hybrid GUI/plugin path | Validator plugin fanout tile. It normalizes replay, gossip, stake, PoH, vote, startup, and validator config messages for the hybrid GUI/plugin stream. |
| `guih` | [`src/discoh/guih/fd_guih_tile.c`](../../src/discoh/guih/fd_guih_tile.c) | optional hybrid GUI | Frankendancer GUI tile. It serves validator status from hybrid plugin, bank, PoH, pack, gossip, bundle, and metrics data. |

### Development-Only Tile Sources

The source tree also contains tiles registered by `firedancer-dev` or `fddev`
commands. They are not part of the production full Firedancer or Frankendancer
topologies, but they matter when sweeping tile sources.

| Tile | Source | Description |
| --- | --- | --- |
| `backtest` | [`src/discof/backtest/fd_backtest_tile.c`](../../src/discof/backtest/fd_backtest_tile.c) | Offline replay/backtest source tile. It reads historical ledger or pcap-style shred sources, feeds replay-style inputs, and checks replay progress. |
| `forkt` / `forktest` | [`src/app/firedancer-dev/commands/forktest/fd_forktest_tile.c`](../../src/app/firedancer-dev/commands/forktest/fd_forktest_tile.c) | Fork-test driver. It reads backtest slot metadata, emits network/gossip-like test traffic, and validates replay/fork behavior. |
| `pktgen` | [`src/app/shared_dev/commands/pktgen/fd_pktgen_tile.c`](../../src/app/shared_dev/commands/pktgen/fd_pktgen_tile.c) | Packet generator for network tile stress testing. It floods a net tile with intentionally invalid small frames that should not escape to the public Internet. |
| `udpecho` | [`src/app/shared_dev/commands/udpecho/fd_udpecho_tile.c`](../../src/app/shared_dev/commands/udpecho/fd_udpecho_tile.c) | UDP echo test tile for connectivity debugging. It mirrors incoming UDP packets back to their source and is explicitly unsafe as a production Internet service. |
| `bencho` | [`src/app/shared_dev/commands/bench/fd_bencho.c`](../../src/app/shared_dev/commands/bench/fd_bencho.c) | Benchmark orchestrator tile. It polls RPC for blockhash/readiness data and coordinates benchmark transaction generation. |
| `benchg` | [`src/app/shared_dev/commands/bench/fd_benchg.c`](../../src/app/shared_dev/commands/bench/fd_benchg.c) | Benchmark transaction generator. It creates synthetic Solana transactions for benchmark load. |
| `benchs` | [`src/app/shared_dev/commands/bench/fd_benchs.c`](../../src/app/shared_dev/commands/bench/fd_benchs.c) | Benchmark send tile. It drives benchmark transaction submission over UDP/QUIC-style paths. |

The `quic_trace` command under `src/app/shared_dev/commands/quic_trace/`
contains `*_tile.c` helper files, but they are command-local stem callbacks,
not registered `fd_topo_run_tile_t` entries in the Firedancer or Frankendancer
topologies.

## Solana Specificity And Tickoni Usefulness

The useful boundary is not "C tile versus Zig tile"; it is whether the tile
embeds Solana validator semantics. Tickoni should reuse systems substrate and
selected generic tile patterns, but it should not give a Solana tile a Tickoni
financial meaning.

### Direct Or Minimal-Adaptation Candidates

| Tile or source | Solana-specific? | Tickoni use | Reuse mode |
| --- | --- | --- | --- |
| `net` | Mostly generic packet I/O, but configured around validator UDP flows | Useful only if Tickoni later needs high-rate packet ingress/egress below normal HTTP/WebSocket APIs, such as market-data UDP capture or colocated adapter feeds. Not needed for the current in-process spike. | Adapt only the generic packet-I/O discipline; do not inherit validator packet schemas. |
| `sock` | Mostly generic UDP socket I/O | Useful for lower-rate UDP adapter feeds or tests where XDP is unnecessary. Not a replacement for `tkapi` HTTP/WebSocket. | Adapt only if Tickoni needs low-level UDP feeds. |
| `netlnk` | Generic Linux network metadata | Useful with `net` if Tickoni owns route/neighbour-aware packet I/O. | Keep paired with low-level network work; otherwise omit. |
| `metric` | Mostly generic, but assumes Firedancer metric layout and C topology | Useful model for `tkmetr` Prometheus export and `fd_http_server` integration. | Keep metric workspace/rendering patterns; expose Tickoni metric names instead of validator metric schema. |
| `diag` | Mixed: generic process diagnostics plus validator health checks | Useful model for `tkdiag` process, queue, crash, CPU, and interrupt diagnostics. | Minimal adaptation: remove validator-specific replay/tower/bundle checks and keep process/topology sampling. |
| `fd_http_server` used by `metric`, `rpc`, and `gui` | Generic HTTP/WebSocket infrastructure, not itself a tile | Useful for `tkapi`, `tkmetr`, and `tkdiag` HTTP surfaces. | Reuse the HTTP/WebSocket substrate, not Solana RPC or GUI schemas. |
| `src/disco/topo` and `src/disco/stem` | Generic tile lifecycle/polling substrate | Useful for process lifecycle, workspace construction, link validation, bounded polling, and backpressure. | Use as lifecycle/backpressure reference material. Avoid adding Tickoni fields to upstream-hot `fd_topo.h`. |
| `src/tango` | Generic queue substrate | Core Tickoni shared-memory queue and flow-control substrate. | Reuse with Tickoni-owned link schemas. |
| `src/util/sandbox` and generated seccomp pattern | Generic sandbox infrastructure with per-tile policies | Useful for tile isolation, file descriptor discipline, Landlock/seccomp, and crash-only operation. | Adapt per Tickoni tile class. |
| `backtest`, `forkt`, benchmark tiles | Solana payloads, generic offline-run idea | Useful only as examples for replay/backtest command structure and test topologies. | Do not drop in; copy patterns for `tkrepl` and harness load tests. |

### Solana-Specific Tiles To Replace Or Exclude

| Tile or group | Why it is Solana-specific | Tickoni context |
| --- | --- | --- |
| `genesi`, `ipecho`, `snapct`, `snapld`, `snapdc`, `snapin`, `snapwr` | Bootstrap Solana genesis, shred version, snapshots, accounts database, banks, and snapshot archives. | Exclude. Tickoni config loading and replay capsule loading must be Tickoni-owned and finance-schema-aware. |
| `gossvf`, `gossip`, `repair`, `rserve`, `shred`, `txsend` | Implement Solana gossip, Turbine shreds, repair protocol, leader forwarding, and validator peer state. | Exclude as product tiles. Borrow only networking/backpressure patterns if a financial adapter has a high-rate feed. |
| `quic` | TPU QUIC/UDP transaction ingress and Solana transaction reassembly. | Exclude. If Tickoni needs QUIC, build a Tickoni transport adapter or wrap lower-level `waltz/quic` primitives with financial request framing. |
| `verify` | Verifies Solana transaction and gossip vote signatures. | Replace with Tickoni envelope, adapter-manifest, proposal-hash, and action-signature verification in `tktool`, `tkadpt`, and future `tkexec`. |
| `dedup` | Deduplicates Solana transactions by signature and validator packet semantics. | Replace with `tkdedu`, using financial idempotency keys and content hashes. |
| `resolv`, `resolh` | Resolve Solana address lookup tables and recent blockhash expiry. | Exclude. Add a Tickoni entity/enrichment tile only when a financial workflow needs deterministic entity or instrument resolution. |
| `pack` | Schedules leader microblocks under Solana account locks, cost model, and blockhash lifetime. | Replace with `tkdisp`/bounded schedulers. Reuse only the discipline around backpressure, conflict-aware scheduling, and queue metrics. |
| `execle`, `execrp`, `bank` | Execute Solana transactions against Solana banks, SVM runtime, accounts database, and Agave ABI. | Exclude. Tickoni agent workers, tool calls, adapters, and future `tkexec` have different trust and financial semantics. |
| `poh`, `pohh`, `tower`, `replay` | Implement PoH, fork replay, TowerBFT, voting, Solana block IDs, and bank/fork state. | Exclude. Tickoni ordering comes from source offsets, deterministic case order, audit hashes, and replay capsules. |
| `accdb` and Solana runtime objects | Store Solana account state, forks, banks, program cache, transaction cache, and compaction state. | Exclude as storage. the approved execution ledger, the analytics store, Markdown, audit logs, and evidence stores have distinct Tickoni roles. |
| `sign` | Validator identity and authorized-voter keyguard. | Replace. Future signing belongs behind `tkexec` action envelopes; split a `tksign` tile only if execution support requires it. |
| `rpc` | Solana JSON-RPC data model and accounts/bank reads. | Exclude. `tkapi` must expose CaseOps and ingestion APIs without owning financial correctness. |
| `event`, `solcap` | Export or capture Solana transaction, shred, vote, and execution artifacts. | Exclude. Tickoni uses `tkaudt`, `tkevid`, and `tkrepl` for financial audit and replay artifacts. |
| `bundle` | Jito block-engine bundle path for Solana leaders. | Exclude. Tickoni has no Jito/MEV bundle product surface. |
| `gui`, `guih`, `plugin` | Validator GUI/plugin streams with Solana topology, vote, stake, gossip, bank, and blockstore state. | Exclude. CaseOps UI reads through `tkapi` and must use Tickoni case/evidence/audit schemas. |
| `store` | Agave blockstore bridge for Solana shreds and FEC sets. | Exclude. Tickoni evidence, audit, analytics, and ledger stores must stay separate and finance-owned. |

## Reuse Boundary

Tickoni should reuse stable systems substrate, not validator semantics.

### Reuse or wrap

| Foundation | Use in Tickoni |
| --- | --- |
| `src/tango/mcache` and `src/tango/dcache` | Shared-memory fragment queues for correctness-bearing inter-process links |
| `src/tango/fseq` or `src/tango/fctl` | Reliable consumer progress and producer backpressure |
| `src/tango/cnc` | Tile boot, heartbeat, halt, and fail state |
| `src/util/sandbox` | Process sandboxing, namespaces, file descriptor checks, Landlock, and seccomp |
| `src/disco/topo` | Reference for process lifecycle and workspace construction |
| `src/disco/stem` | Reference for bounded polling loops and backpressure |
| `src/disco/metrics` | Reference for low-overhead per-tile metrics; do not copy validator metric names as financial facts |
| `src/waltz/http` | HTTP/WebSocket substrate for `tkapi`, `tkmetr`, and diagnostics surfaces |
| `net`, `sock`, `netlnk` tile implementations | Optional low-level network ingress/egress substrate when a Tickoni workflow proves it needs packet-tile performance |
| Crash-only process model | Keep: unexpected tile failure tears down the runtime |

### Do not reuse as product tiles

Do not repurpose Solana protocol tiles as Tickoni tiles. In particular, do not
register `genesi`, `ipecho`, `gossvf`, `gossip`, `shred`, `repair`, `rserve`,
`replay`, `tower`, `quic`, `verify`, `dedup`, `resolv`, `pack`, `execle`,
`execrp`, `poh`, `accdb`, `sign`, `rpc`, `solcap`, `event`, `bundle`, `gui`,
`snapct`, `snapld`, `snapdc`, `snapin`, `snapwr`, or any Frankendancer
`resolh`, `bank`, `pohh`, `store`, `plugin`, or `guih` tile in the canonical
Tickoni product topology. Their schemas, state, and security assumptions are
validator-specific.

If generic Firedancer code is needed, expose it through the canonical Tickoni
bridge: a lower-camel Zig wrapper in `src/tickoni/c_abi/*.zig`, a private
`extern fn tk_*` declaration, and a Tickoni-owned C shim under
`src/tickoni/c_abi/shim/**` that is the only place allowed to include
Firedancer or vendored C headers. Avoid adding Tickoni fields to
`src/disco/topo/fd_topo.h`, which is a likely upstream synchronization hotspot.

### Process And Core Placement Boundary

In Tickoni Linux full-runtime process mode, a tile is a supervisor-managed OS
process with its own address space. A thread-backed topology may remain as a
dev/test compatibility lane, but it is not the process-isolation target for
runtime hardening work.

CPU placement is Tickoni-owned policy layered on top of the Firedancer
substrate. Tickoni should support:

- `exclusive`: one tile process pinned to one CPU;
- `shared`: multiple declared tile processes intentionally reuse one CPU;
- `floating`: the tile process is not pinned and the OS scheduler may place it.

Do not change Firedancer's generic tile structs or validator auto-layout
semantics to make Tickoni shared-core placement work. Shared-core placement is
accepted only when the Tickoni config declares it. Undeclared oversubscription,
malformed CPU ids, and unavailable CPU ids fail closed. Shared-core placement is
a lower-throughput placement mode and must be visible in metrics, diagnostics,
or supervisor output.

Process-mode topology tests should prove OS process identity, not only thread
identity: one child PID or equivalent thread-group/process id per configured
tile, tied back to the supervisor launch record. Shared CPU assignment does not
change that process boundary.

### Shared-Memory Negative Cases

Topology hardening must include fail-closed tests for malformed, stale,
missing, or duplicate workspace identifiers; wrong workspace join modes;
missing `mcache`, `dcache`, `fseq`/`fctl`, or `cnc` objects; dcache chunk or
fragment bounds errors; link depth, MTU, burst, or fragment-size mismatches;
non-advancing reliable consumers; accidental heap-backed correctness queues in
process mode; and forced tile crashes that must not corrupt sibling tile state.

See [workspace-management.md](workspace-management.md) for workspace lifecycle,
the Firedancer vs Tickoni backing divergence, and the object callback system.

These tests prove Tickoni's boundary around reused Firedancer substrate. They
do not require fuzzing every Firedancer workspace internal, proving arbitrary
kernel memory-attack resistance, or claiming production throughput saturation.

### Registry Design Options (from 7-20-24.md audit)

Three approaches were evaluated for how the supervisor discovers which tile
processes to launch and how it knows their expected link cardinality:

1. **Option A — Tile registry (single source of truth).** A Zig table maps
   tile ID to logical name, process/thread callback, link cardinality, and
   metric schema. The supervisor reads from this table exclusively. This is the
   recommended approach because it eliminates duplicate mappings and keeps
   launch logic generic.

2. **Option B — LaunchSpec from topology config.** Launch decisions come from a
   serialized config that lists tiles and their links. Risk: the config is
   separate from the topology source of truth, creating a second copy of the
   link graph that can drift. Requires extra validation to prevent silent
   truncation.

3. **Option C — Manual dispatch (current pain point).** `if/else` chains in
   `tile_main.zig` and `supervisor.zig` dispatch by raw tile-id string. This
   is brittle, repeats tile IDs as strings, and makes it impossible to reason
   about supported tile counts.

Option A is the chosen approach. No supervisor, process dispatcher, metrics
reader, or test harness should recreate tile identity mappings independently.
The tile registry in `topology.zig` owns that mapping.

### Firedancer TILES[] Pattern (from 7-20-24.md audit)

Firedancer's topology builder uses a `TILES[]` array of `fd_topo_run_tile_t`
pointers, populated in each binary's `main.c`. Each entry has a `name` for
string lookup, footprint/alignment functions, seccomp/FD lists, and
`privileged_init`/`unprivileged_init`/`run` callbacks. The dispatcher
(`fdctl_tile_run()`) does one linear string comparison at boot time and
returns the struct.

Firedancer has exactly one canonical lookup (fdctl_tile_run) that all
consumers call. Tickoni currently has three consumers each writing their own
`if/else` chain on raw tile-id strings — this is the problem the registry
fixes.

Firedancer's metrics are position-indexed (`topo->tiles[idx].metrics`), not
string-matched. Tickoni's `snapshotProcessMetrics` does string comparison AND
maps to payment-specific field names — the registry owns the counter schema so
`snapshotProcessMetrics` iterates the schema instead of matching strings.

### Multi-Link Pattern and Launch Spec (from 11-23.md audit)

Firedancer supports fan-in and fan-out through fixed-size arrays in
`fd_topo_tile_t`: `in_cnt`, `in_link_id[FD_TOPO_MAX_TILE_IN_LINKS]` (128),
`out_cnt`, `out_link_id[FD_TOPO_MAX_TILE_OUT_LINKS]` (32). The stem loop
(`fd_stem.c`) is a multi-input callback multiplexer that polls all inputs in
randomized round-robin order.

Firedancer has 3 layers of defense against link truncation:

1. **Topology declares it:** `fd_topo_tile_t` has `in_cnt` + arrays, not single
   fields.
2. **Stem handles it:** the run loop explicitly iterates `in_cnt` inputs.
3. **No silent truncation:** if a tile declares 3 inputs, stem reads all 3.

Tickoni's approach mirrors this at the topology level — `fd_topo_tile_t`
supports `in_cnt`/`out_cnt` arrays and the topology builder (`fd_topob`)
creates them. But in **process mode**, `LaunchSpec` currently has only one
`input_link` and one `output_link`. This means:

- A tile with multiple inputs or outputs cannot be launched in process mode
- The supervisor silently truncates multi-link topologies (last-match-wins)
- This is latent because the Phase 0 payment topology is a linear chain

**Decision:** process mode must fail closed when the `LaunchSpec` cannot
represent the tile's link cardinality from the topology. Explicit validation
must prevent silent truncation. Either extend `LaunchSpec` to support
per-tile link arrays, or deliberately restrict process mode to single-link
tiles and validate accordingly.

The Firedancer comparison is instructive: `fd_stem.c` handles arbitrary fan-in
at the callback level. Tickoni should not replicate that complexity in process
mode — single-link per tile is the correct initial contract. If fan-in is
needed, use tile aggregation patterns (dedupe before policy) rather than
multi-input process tiles.

## Canonical Tickoni Source Tree

Tickoni application, runtime, tile, schema, codec, connector, and business
logic is Zig. C is restricted to the Firedancer bridge under
`src/tickoni/c_abi/shim/**`; C code outside that shim directory is
non-canonical boundary debt, not an implementation pattern to extend.

Use this product tree:

```text
src/app/tickoni/          Zig supervisor and CLI; owns concrete product topologies (which
                           tiles run, tile IDs, channel wiring) — see src/app/tickoni/topologies.zig
src/tickoni/runtime/      Process lifecycle, topology, channels, backpressure
src/tickoni/util/         Generic Linux/CPU primitives with no Tickoni domain knowledge
                           (CPU affinity, clock, process); reusable outside this codebase
src/tickoni/c_abi/*.zig   Zig wrappers over Tickoni-owned tk_* C shim symbols
src/tickoni/c_abi/shim/   Only C bridge; only place to include Firedancer C headers
src/tickoni/codec/        Zig codec implementations for Tickoni-owned schemas
src/tickoni/schema/       Financial events, cases, capabilities, audit envelopes
src/tickoni/schema/proto/ Protobuf wire definitions for canonical contracts
src/tickoni/tiles/        Tickoni-owned tile implementations
src/tickoni/test/demo/    Deterministic CLI/test demo orchestration
src/tickoni/connectors/   Signed adapter manifests and connector implementations
```

`src/app/tickoni/`, `src/tickoni/runtime/`, `src/tickoni/util/`,
`src/tickoni/c_abi/`, and `src/tickoni/tiles/` already exist. Schema, codec,
and demo paths are Tickoni-owned support roots around the runtime.
`connectors/` should be added only when implementation work needs it.

### Runtime IDs

| Runtime ID | Logical name | Responsibility |
| --- | --- | --- |
| `tkings` | `ingest_tile` | Receive the configured event source, synthetic or external, validate framing, assign source offsets, and apply ingress backpressure |
| `tknorm` | `normalize_tile` | Convert adapter-specific input into the canonical financial event schema |
| `tkdedu` | `dedupe_tile` | Deduplicate canonical financial events by stable idempotency key and content hash |
| `tkcase` | `case_router_tile` | Deterministically create or update cases and emit case lifecycle transitions |
| `tkpoly` | `policy_tile` | Evaluate versioned finance-native capability policy, including destination allowlists, amount/exposure/frequency limits, and allow, deny, or require-approval decisions |
| `tkaudt` | `audit_tile` | Own append-only hash-chain ordering and JSONL export |
| `tkevid` | `evidence_tile` | Store and retrieve content-addressed evidence blobs |
| `tkrepl` | `replay_tile` | Re-inject replay capsules with external effects disabled and report divergence |
| `tkmetr` | `metric_tile` | Export Tickoni runtime metrics |
| `tkdiag` | `diag_tile` | Export process, queue, and crash diagnostics |
| `tkdisp` | `agent_dispatch_tile` | Schedule bounded stub agent runs by role, synthetic case, priority, and remaining budget |
| `tkagnt` | `agent_worker_tile` | Run memory-isolated role agents without direct shell, unrestricted syscall, or unrestricted network access |
| `tkmodl` | `model_gateway_tile` | Own model-provider or LLM-server network access, in-process GPU inference, routing, context limits, retry limits, token accounting, and spend caps. Supported providers: OpenAI, Anthropic (Claude), Qwen, DeepSeek, and a configured local/dev LLM endpoint. |
| `tktool` | `tool_broker_tile` | Normalize model-native function calls and MCP requests into finance-native adapter or proposal envelopes, validate capability scope, and route approved requests to signed or stub adapters |
| `tkadpt` | `adapter_tile` | Run a signed, manifest-scoped financial adapter or local stub adapter with narrowly allowed destinations, rails, accounts, venues, instruments, and network access |
| `tkapi` | `caseops_api_tile` | Serve CaseOps board queries, evidence reads, approvals, and audit timeline reads |
| `tkexec` | `action_executor_tile` | Execute only approved, signed downstream financial mutations within destination, amount, frequency, and approval scope; own privileged accounting ledger credentials |

`tkagnt` and `tkadpt` are tile classes and may have multiple instances. Start
with one instance of each needed role or adapter and scale only after queue
metrics justify it.

### Event Flow

```text
configured event source
  -> tkings
  -> tknorm
  -> tkdedu
  -> tkpoly
  -> tkaudt

tkdisp -> tkagnt                    bounded investigation
tkcase -> tkdisp -> tkagnt          case-scoped investigation

tkagnt -> tkmodl                    model calls
tkagnt -> tktool -> tkadpt          finance-capability-scoped reads and proposals
tkapi  -> tkpoly -> tkexec          approved sensitive actions only

all boundary events -> tkaudt
evidence records    -> tkevid
replay capsule      -> tkrepl -> deterministic pipeline with tkexec disabled
all tile metrics    -> tkmetr
```

AI is not part of the deterministic event critical path. A case can be created,
audited, and replayed before an agent runs. Model outputs and external adapter
results are captured as evidence and substituted from the capsule during
forensic replay.

Financial capability semantics are owned by
[`capabilities.md`](../strategy/capabilities.md). Tiles enforce that product contract:

- `tkpoly` decides whether a financial capability envelope is allowed, denied,
  approval-required, evidence-required, or escalated.
- `tktool` converts model-native function calls and MCP requests into
  finance-native requests such as `payment_retry.propose`,
  `ledger_correction.propose`, and `trading_order.propose`.
- `tkadpt` executes only adapter calls that stay inside the approved financial
  scope, such as payment rail, beneficiary, IBAN hash, wallet, broker account,
  venue, sector, instrument, amount, and frequency limits.
- `tkexec` remains disabled until approved execution support exists and must
  never execute outside signed proposal, policy, approval, and destination
  scope.

## Existing Tile Decisions

In this table, "exclude" means do not register or link the tile in the new
Tickoni product topology. Validator-only source should be deleted after the new
runtime no longer depends on it.

| Existing tile or group | Decision | Tickoni replacement |
| --- | --- | --- |
| `net`, `netlnk`, `sock` | Exclude from the initial product topology. Start with a conventional sandboxed API socket; add specialized packet ingress only if benchmarks justify it. | `tkings` |
| `quic` | Exclude. TPU QUIC is Solana-specific. | `tkings` protocol adapter if ever needed |
| `verify` | Exclude. Solana signature verification is not financial adapter verification. | Manifest and envelope verification in `tktool`, `tkadpt`, and `tkexec` |
| `dedup` | Replace, do not morph. The existing tile understands Solana transaction packets. | `tkdedu` |
| `pack` | Replace, do not morph. The useful idea is bounded scheduling and backpressure, not leader packing. | `tkdisp` |
| `bank`, `execle`, `execrp` | Exclude. Solana transaction execution is unrelated to agent execution. | `tkagnt`, `tktool`, `tkexec` |
| `poh`, `pohh` | Exclude. Tickoni ordering comes from stable event offsets, deterministic IDs, and audit hashes. | `tkaudt` |
| `shred`, `gossip`, `gossvf`, `repair`, `rserve`, `tower`, `txsend` | Exclude. These are Solana network and consensus tiles. | None |
| `genesi`, `ipecho`, `snapct`, `snapld`, `snapdc`, `snapin`, `snapwr` | Exclude. These bootstrap and restore a Solana validator. | Tickoni config and replay capsule loading |
| `sign` | Replace, do not morph. Validator keyguard policy is not a fintech action-signing policy. | Narrow signing support owned by `tkexec`; split a `tksign` tile later if needed |
| `accdb`, `store`, `funk`, `progcache`, `txncache`, `banks` | Exclude. They are Solana runtime state. | Dedicated case, evidence, audit, and connector stores |
| `event` | Exclude. It is an outbound Solana telemetry exporter. | `tkings`, `tkaudt` |
| `metric`, `diag` | Reimplement with Tickoni IDs while reusing the generic metrics and sandbox substrate where practical. | `tkmetr`, `tkdiag` |
| `rpc`, `gui`, `guih`, `plugin` | Exclude as validator tiles. The validator RPC and GUI data model do not fit CaseOps. The plugin fanout pattern may still be useful if Tickoni needs a governed connector or marketplace surface. | `tkapi` and a separate CaseOps frontend |
| `bundle` | Exclude. Jito bundles are Solana-specific. | None |
| `resolh`, `resolv` | Exclude. Solana lookup resolution is unrelated to financial entity enrichment. | Add a new `tkenty` enrichment tile only when a workflow requires it |
| `solcap` | Exclude. It captures Solana execution state. | `tkaudt`, `tkevid`, `tkrepl` |
| Dev-only `backtest`, `forkt`, `bencho`, `benchg`, `benchs`, `pktgen`, `udpecho` | Exclude from product topology. These are test, benchmark, or debugging tiles. | Tickoni-owned replay and load-test harnesses |
