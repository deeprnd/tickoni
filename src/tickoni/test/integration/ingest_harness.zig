/// Test harness that feeds events into a running topology through its one
/// link that no tile produces (`rt.link.external_src`, Firedancer's
/// permit_no_producers).
///
/// In the product topologies that link is tkgate's input, and the harness stands
/// in for the terminal tile (the Qt CaseOps app) that will publish user
/// requests on it. In the isolation fixtures without tkgate it is tkings's
/// input, and the harness stands in for tkgate. It joins the link from the test
/// process through the supervisor's workspace join, the way tkrepl replay
/// will, and publishes one `TkEvent` fragment per event
/// (shim/tk_event_wire.h), stamping what a producer owns: version, kind,
/// source (tkgate), trace_id and idempotency_key. tkgate and tkings check and
/// frame the rest.
///
/// Feeds:
///   * `payments`: the synthetic payment stream (`tiles.syntheticPayment`), with
///     its test-only duplicate and malformed injection;
///   * `agent_requests`: one agent request per offset from a
///     `ModelRequestSource`, carrying its scope and prompt reference;
///   * `events`: an explicit list, for framing tests that need malformed
///     envelopes.
///
/// Publishing runs on its own thread with credit-based backpressure, as a tile
/// producer would; `finish` stops and joins it. It must be called before the
/// supervisor unmaps the workspace (stopProcess).
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const supervisor_mod = @import("supervisor");
const tiles = @import("tiles");

const Supervisor = supervisor_mod.Supervisor;
const mrs = tiles.model_request_source;
pub const TkEvent = c_abi.tkings.TkEvent;

const event_sig: u64 = 0; // TK_LINK_SIG_EVENT
const source_tkgate: u8 = 1; // TK_EVENT_SOURCE_TKGATE
const kind_payment: u8 = 1; // TK_EVENT_KIND_PAYMENT
const kind_agent_request: u8 = 2; // TK_EVENT_KIND_AGENT_REQUEST
const event_wire_version: u16 = 1; // TK_EVENT_WIRE_VERSION

comptime {
    // The local names above are the C header's (shim/tk_event_wire.h).
    std.debug.assert(@sizeOf(TkEvent) == 400);
}

/// Trace id of the event at stream `offset`: nonzero, one per request.
pub fn traceIdAt(offset: u64) u64 {
    return offset + 1;
}

fn envelope(kind: u8, offset: u64, idempotency_key: u64) TkEvent {
    var ev = std.mem.zeroes(TkEvent);
    ev.version = event_wire_version;
    ev.kind = kind;
    ev.source = source_tkgate;
    ev.trace_id = c_abi.trace_id.fromInt(traceIdAt(offset));
    ev.idempotency_key = idempotency_key;
    return ev;
}

/// The payment event at stream `offset` of the synthetic stream `cfg`.
pub fn paymentEvent(cfg: tiles.PaymentPipelineConfig, offset: u64) TkEvent {
    const raw = tiles.syntheticPayment(cfg, offset);
    var ev = envelope(kind_payment, offset, raw.idempotency_key);
    ev.body.payment.amount_cents = raw.amount_cents;
    ev.body.payment.account_id = raw.account_id;
    ev.body.payment.currency = raw.currency;
    ev.body.payment.malformed = @intFromBool(raw.malformed);
    return ev;
}

/// The agent-request event at stream `offset` of `source`. Each request has its
/// own idempotency key, so tkdedu never drops a distinct request. `scratch`
/// must hold `source.shape.prompt_bytes`.
pub fn agentRequestEvent(source: mrs.ModelRequestSource, offset: u64, scratch: []u8) TkEvent {
    var ev = envelope(kind_agent_request, offset, 1_000_000 + offset);
    ev.body.agent_request = mrs.buildAgentRequest(source, offset, scratch);
    return ev;
}

pub const Feed = union(enum) {
    payments: tiles.PaymentPipelineConfig,
    agent_requests: mrs.ModelRequestSource,
    events: []const TkEvent,
};

pub const Harness = struct {
    producer: rt.link.Producer = undefined,
    feed: Feed = .{ .events = &.{} },
    event_count: u64 = 0,
    scratch: []u8 = &.{},
    allocator: std.mem.Allocator = undefined,
    thread: ?std.Thread = null,
    stop: std.atomic.Value(bool) = .init(false),
    backpressure_waits: std.atomic.Value(u64) = .init(0),
    /// Events published so far.
    published: std.atomic.Value(u64) = .init(0),

    /// Joins the externally fed link of `sup`'s running topology and starts
    /// publishing `event_count` events from `feed` (for `events`, the list's
    /// length). `self` must not move until `finish`.
    pub fn start(self: *Harness, allocator: std.mem.Allocator, sup: *Supervisor, feed: Feed, event_count: u64) !void {
        std.debug.assert(self.thread == null);
        const state = sup.process_state orelse return error.NoProcessState;
        const handles = sup.linkHandles(try ingestInputChannel(sup.topo)) orelse return error.NoProcessState;
        const scratch_len: usize = switch (feed) {
            .agent_requests => |s| s.shape.prompt_bytes,
            else => 0,
        };
        self.* = .{
            .feed = feed,
            .event_count = switch (feed) {
                .events => |list| list.len,
                else => event_count,
            },
            .allocator = allocator,
            .scratch = try allocator.alloc(u8, scratch_len),
        };
        errdefer allocator.free(self.scratch);
        self.producer = try rt.link.Producer.join(state.wksp, handles);
        errdefer self.producer.leave();
        self.thread = try std.Thread.spawn(.{}, run, .{self});
    }

    /// Stops publishing (a producer blocked on credit gives up), joins the
    /// thread and leaves the link. Safe to call when never started, and twice.
    pub fn finish(self: *Harness) void {
        const thread = self.thread orelse return;
        self.stop.store(true, .release);
        thread.join();
        self.thread = null;
        self.producer.leave();
        self.allocator.free(self.scratch);
        self.scratch = &.{};
    }

    fn eventAt(self: *Harness, offset: u64) TkEvent {
        return switch (self.feed) {
            .payments => |cfg| paymentEvent(cfg, offset),
            .agent_requests => |source| agentRequestEvent(source, offset, self.scratch),
            .events => |list| list[@intCast(offset)],
        };
    }

    fn run(self: *Harness) void {
        const whole = c_abi.multipart.ctlBits(true, true);
        var offset: u64 = 0;
        while (offset < self.event_count) : (offset += 1) {
            const ev = self.eventAt(offset);
            self.producer.publishFragment(
                std.mem.asBytes(&ev),
                event_sig,
                whole,
                &self.backpressure_waits,
                &self.stop,
                null,
            ) catch return;
            self.published.store(offset + 1, .release);
        }
    }
};

/// The one channel that no tile produces: tkgate's input where the topology has
/// tkgate, otherwise tkings's.
pub fn ingestInputChannel(topo: rt.topology.Topology) !usize {
    const ingress = supervisor_mod.tile_registry.ingressTile(topo);
    for (topo.channels, 0..) |ch, i| {
        if (!ch.hasProducerTile() and topo.tiles[ch.dst_idx].name.eql(ingress)) return i;
    }
    return error.NoIngestInput;
}

/// Test-only payment injection options, the producer's side of the old
/// `ProcessPipelineConfig.duplicate` / `.inject_malformed`.
pub const PaymentOptions = struct {
    duplicate: ?tiles.DuplicateConfig = null,
    inject_malformed: bool = false,
};

/// Starts `sup` with `config`, then feeds it `config.event_count` synthetic
/// payments (none for an idle run with event_count 0). Call `feed.finish()`
/// before `sup.stopProcess`.
pub fn startPaymentRun(sup: *Supervisor, feed: *Harness, config: supervisor_mod.ProcessPipelineConfig, opts: PaymentOptions) !void {
    try sup.startPaymentPipelineProcess(std.testing.io, config);
    if (config.event_count == 0) return;
    try feed.start(std.testing.allocator, sup, .{ .payments = .{
        .event_count = config.event_count,
        .policy_limit_cents = config.policy_limit_cents,
        .duplicate = opts.duplicate,
        .inject_malformed = opts.inject_malformed,
    } }, config.event_count);
}

test "a payment event carries the synthetic payment under a canonical envelope" {
    const cfg = tiles.PaymentPipelineConfig{ .event_count = 8, .policy_limit_cents = 1_000 };
    const ev = paymentEvent(cfg, 7);
    const raw = tiles.syntheticPayment(cfg, 7);
    try std.testing.expect(c_abi.tkings.framingOk(&ev));
    try std.testing.expectEqual(raw.idempotency_key, ev.idempotency_key);
    try std.testing.expectEqual(raw.amount_cents, ev.body.payment.amount_cents);
    try std.testing.expectEqual(@as(u128, 8), c_abi.trace_id.toInt(ev.trace_id));
    try std.testing.expectEqual(@as(u64, 0), ev.source_offset);
}

test "an agent-request event names its prompt by reference and passes tkings and tknorm" {
    var scratch: [96]u8 = undefined;
    const ev = agentRequestEvent(.{}, 3, &scratch);
    try std.testing.expect(c_abi.tkings.framingOk(&ev));
    try std.testing.expect(c_abi.tknorm.eventValid(&ev));
    try std.testing.expectEqual(@as(u32, 96), ev.body.agent_request.prompt_ref.prompt_len);
    try std.testing.expect(agentRequestEvent(.{}, 4, &scratch).idempotency_key != ev.idempotency_key);
}
