/// v2.14.S1 process-mode payment pipeline stage orchestration: runs inside
/// each tile's own process (dispatched from src/app/tickoni/tile_registry.zig),
/// reading/writing Tango shared-memory links (src/tickoni/runtime/link.zig)
/// instead of the thread-mode heap ring
/// (src/tickoni/tiles/payment_pipeline/queue.zig's BoundedQueue). The pure
/// decision logic — hashing, framing validation, dedup comparison, policy
/// decision, audit record building — is reused unchanged from
/// src/tickoni/tiles/payment_pipeline/{runtime,audit_sink}.zig; only the
/// transport and state ownership differ from thread mode. Dedup state
/// (tkdedu) and the audit log (tkaudt) are local to that tile's own
/// process now, not a struct shared across tiles.
///
/// The pipeline is deterministic and bounded (cfg.event_count messages
/// flow through every stage — normalization/dedupe/policy mark and
/// forward rather than drop), so consumers loop exactly event_count times
/// instead of needing an explicit end-of-stream signal on the link.
///
/// v2.14.S8.T2: these functions take a PaymentPipelineConfig by value
/// instead of reading event_count/policy_limit_cents/duplicate/
/// inject_malformed off a LaunchSpec — this file has no dependency on
/// LaunchSpec's shape at all. The supervisor writes one shared config file
/// per run (writeProcessConfig below); tile_registry.zig's process-mode
/// wrappers read it (readProcessConfig) and pass the result in here.
///
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const util = @import("util");
const payment_runtime = @import("runtime.zig");
const model_request_source = @import("model_request_source.zig");
const audit_mod = @import("audit_mod");

const PaymentMessage = payment_runtime.PaymentMessage;

fn halted(cnc: *c_abi.cnc.Cnc) bool {
    const sig = c_abi.cnc.signalQuery(cnc);
    std.debug.print("[halted] signal={d} halt={d} result={s}\n", .{ sig, c_abi.cnc.signal_halt, if (sig == c_abi.cnc.signal_halt) "true" else "false" });
    return sig == c_abi.cnc.signal_halt;
}

// ---------------------------------------------------------------------------
// Payment-pipeline process-mode config: round-tripped through a single file
// shared by every tile in the run (identical for all of them), separate
// from each tile's own LaunchSpec. Same magic/version/fail-closed idiom as
// runtime/launch_spec.zig's LaunchSpec.
// ---------------------------------------------------------------------------

pub const process_config_magic: u32 = 0x544b5043; // "TKPC"
/// v4: ModelRequestSource carries per-slot tiers, the prompt/response shape and a
/// test-only stream fault.
/// v5: the pipeline config carries the full workflow's dispatch template.
pub const process_config_version: u16 = 5;

pub const StuckTileHook = struct {
    tile_idx: u32,
    after_messages: u64 = 0,
    sleep_ns: u64 = 60 * std.time.ns_per_s,
};

pub const ProcessRuntimeConfig = struct {
    pipeline: payment_runtime.PaymentPipelineConfig = .{},
    /// Test-only hook for supervisor heartbeat-staleness integration proofs:
    /// after `after_messages` iterations, the selected tile sleeps forever
    /// without emitting further heartbeats or observing HALT.
    stuck_tile: ?StuckTileHook = null,
};

pub const ProcessConfigFile = struct {
    magic_field: u32 = process_config_magic,
    version_field: u16 = process_config_version,
    cfg: ProcessRuntimeConfig = .{},
};

pub fn writeProcessConfig(cfg: ProcessRuntimeConfig, io: std.Io, dir: std.Io.Dir, sub_path: []const u8) !void {
    const file_struct = ProcessConfigFile{ .cfg = cfg };
    var file = try rt.file_io.createFile(io, dir, sub_path);
    defer file.close(io);
    try file.writePositionalAll(io, std.mem.asBytes(&file_struct), 0);
}

pub fn readProcessConfig(io: std.Io, dir: std.Io.Dir, sub_path: []const u8) !ProcessRuntimeConfig {
    var file = try rt.file_io.openFile(io, dir, sub_path);
    defer file.close(io);
    var file_struct: ProcessConfigFile = undefined;
    const buf = std.mem.asBytes(&file_struct);
    const n = try file.readPositionalAll(io, buf, 0);
    if (n != @sizeOf(ProcessConfigFile)) return error.ProcessConfigTruncated;
    if (file_struct.magic_field != process_config_magic) return error.ProcessConfigBadMagic;
    if (file_struct.version_field != process_config_version) return error.ProcessConfigUnsupportedVersion;
    return file_struct.cfg;
}

fn sleepNanos(ns: u64) void {
    util.os_api.sleepNanos(ns);
}

fn maybeBlockForTest(process_cfg: ProcessRuntimeConfig, tile_idx: u32, completed_messages: u64) void {
    const hook = process_cfg.stuck_tile orelse return;
    if (hook.tile_idx != tile_idx or completed_messages < hook.after_messages) return;
    std.log.warn(
        "stuck_tile hook triggered: tile_idx={d}, after_messages={d}, sleep_ns={d} — entering infinite block",
        .{
            hook.tile_idx,
            hook.after_messages,
            hook.sleep_ns,
        },
    );
    while (true) sleepNanos(hook.sleep_ns);
}

// ---------------------------------------------------------------------------
// Pipeline stages.
// ---------------------------------------------------------------------------

pub fn runIngestProcess(process_cfg: ProcessRuntimeConfig, tile_idx: u32, output: *rt.link.Producer, cnc: *c_abi.cnc.Cnc) void {
    const cfg = process_cfg.pipeline;
    var stop_flag = std.atomic.Value(bool).init(false);
    var backpressure_waits = std.atomic.Value(u64).init(0);

    var produced: u64 = 0;
    var offset: u64 = 0;
    while (offset < cfg.event_count) : (offset += 1) {
        maybeBlockForTest(process_cfg, tile_idx, produced);
        if (halted(cnc)) break;
        const raw = payment_runtime.syntheticPayment(cfg, offset);
        const msg = PaymentMessage{ .raw = raw, .pipeline_hops = 1 };
        output.publish(std.mem.asBytes(&msg), &backpressure_waits, &stop_flag, cnc) catch break;
        produced += 1;
    }
    rt.cnc_counters.appCounterWrite(cnc, 0, produced);
}

/// Test-build agent-request stream. When the process config carries a
/// `ModelRequestSource`, the process publishes one agent request per offset
/// instead of a payment event: a logical message (header plus prompt) sent as a
/// contiguous multipart fragment stream, each fragment under the same bounded,
/// backpressured publish path as `runIngestProcess`. Offset `n` is run `n+1`.
pub fn runModelRequestSourceProcess(
    process_cfg: ProcessRuntimeConfig,
    tile_idx: u32,
    output: *rt.link.Producer,
    cnc: *c_abi.cnc.Cnc,
) error{ModelRequestSourceRequiresTestBuild}!void {
    const source = process_cfg.pipeline.model_requests orelse return;
    // The request source is a test fixture, never a production ingest path.
    if (!rt.test_build.enabled) return error.ModelRequestSourceRequiresTestBuild;

    const cfg = process_cfg.pipeline;
    var stop_flag = std.atomic.Value(bool).init(false);
    var backpressure_waits = std.atomic.Value(u64).init(0);

    // One message buffer, sized for the largest logical message.
    const body_buf = std.heap.page_allocator.alloc(u8, c_abi.multipart.max_message_bytes) catch return;
    defer std.heap.page_allocator.free(body_buf);

    var produced: u64 = 0;
    var offset: u64 = 0;
    send: while (offset < cfg.event_count) : (offset += 1) {
        maybeBlockForTest(process_cfg, tile_idx, produced);
        if (halted(cnc)) break;
        const body = model_request_source.buildAgentRequest(source, offset, body_buf);
        const hash = c_abi.multipart.messageHash(body);
        const frags = c_abi.multipart.fragCount(body.len);
        var frag: [c_abi.multipart.link_mtu]u8 = undefined;
        const fault = if (offset == source.fault_offset) source.fault else .none;
        for (0..frags) |idx| {
            // A deliberately faulty producer, for the receiver's fail-closed tests.
            switch (fault) {
                .none => {},
                .drop_middle => if (idx == 1) continue,
                .omit_last => if (idx == frags - 1) continue,
                .corrupt_payload => {},
            }
            const f = c_abi.multipart.writeFragment(&frag, .request, .agent_request, model_request_source.runIdAt(offset), offset + 1, body, hash, idx);
            if (fault == .corrupt_payload and idx == 1) frag[c_abi.multipart.header_size + 1] ^= 0x5a;
            output.publishFragment(
                frag[0..f.sz],
                audit_mod.TK_LINK_SIG_AGENT_REQUEST,
                c_abi.multipart.ctlBits(f.som, f.eom),
                &backpressure_waits,
                &stop_flag,
                cnc,
            ) catch break :send;
        }
        produced += 1;
    }
    rt.cnc_counters.appCounterWrite(cnc, 0, produced);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "ProcessConfig round-trips through a file" {
    const tmp = util.tmpDir();

    const cfg = ProcessRuntimeConfig{
        .pipeline = .{
            .event_count = 123,
            .policy_limit_cents = 45_600,
            .duplicate = .{ .offset = 3, .source = 1 },
            .inject_malformed = true,
        },
        .stuck_tile = .{ .tile_idx = 2, .after_messages = 7, .sleep_ns = 1234 },
    };
    try writeProcessConfig(cfg, std.testing.io, tmp.dir, "payment_pipeline.config");

    const read_back = try readProcessConfig(std.testing.io, tmp.dir, "payment_pipeline.config");
    try std.testing.expectEqual(@as(u64, 123), read_back.pipeline.event_count);
    try std.testing.expectEqual(@as(i64, 45_600), read_back.pipeline.policy_limit_cents);
    if (read_back.pipeline.duplicate) |dup| {
        try std.testing.expectEqual(@as(u64, 3), dup.offset);
        try std.testing.expectEqual(@as(u64, 1), dup.source);
    } else {
        try std.testing.expect(false);
    }
    try std.testing.expect(read_back.pipeline.inject_malformed);
    try std.testing.expectEqual(@as(?u32, 2), if (read_back.stuck_tile) |hook| hook.tile_idx else null);
    try std.testing.expectEqual(@as(?u64, 7), if (read_back.stuck_tile) |hook| hook.after_messages else null);
}

test "ProcessConfig readProcessConfig rejects a truncated file" {
    var tmp = util.tmpDir();

    var file = try tmp.dir.createFile(std.testing.io, "short.config", .{});
    try file.writePositionalAll(std.testing.io, &[_]u8{ 1, 2, 3, 4 }, 0);
    file.close(std.testing.io);

    try std.testing.expectError(error.ProcessConfigTruncated, readProcessConfig(std.testing.io, tmp.dir, "short.config"));
}

test "ProcessConfig readProcessConfig rejects a bad magic" {
    var tmp = util.tmpDir();

    var file_struct = ProcessConfigFile{};
    file_struct.magic_field = 0xdeadbeef;
    var file = try tmp.dir.createFile(std.testing.io, "bad_magic.config", .{});
    try file.writePositionalAll(std.testing.io, std.mem.asBytes(&file_struct), 0);
    file.close(std.testing.io);

    try std.testing.expectError(error.ProcessConfigBadMagic, readProcessConfig(std.testing.io, tmp.dir, "bad_magic.config"));
}
