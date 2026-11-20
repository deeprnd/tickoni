const std = @import("std");
const c_abi = @import("c_abi");
const process = @import("util").process;
const LinkHandles = @import("handles.zig").LinkHandles;
const join_mod = @import("join.zig");
const wait = @import("wait.zig");

/// Bounded, backpressuring producer side of a reliable link: waits for the
/// consumer's fseq progress instead of dropping when the ring is full.
pub const Producer = struct {
    wksp: *c_abi.wksp.Wksp,
    mcache: [*]c_abi.queue.FragMeta,
    dcache_base: [*]u8,
    fseq: [*]volatile u64,
    fctl_mem: [c_abi.fctl.single_rx_footprint]u8 align(c_abi.fctl.fctl_align),
    slow_count: u64 = 0,
    cr_avail: usize,
    depth: usize,
    mtu: usize,
    next_seq: u64 = 0,

    pub fn join(wksp: *c_abi.wksp.Wksp, handles: LinkHandles) !Producer {
        const joined = try join_mod.joinTriplet(wksp, handles);
        var producer: Producer = .{
            .wksp = wksp,
            .mcache = joined.mcache,
            .dcache_base = joined.dcache_base,
            .fseq = joined.fseq,
            .fctl_mem = undefined,
            .cr_avail = 0,
            .depth = handles.depth,
            .mtu = handles.mtu,
        };
        const shfctl = c_abi.fctl.new(&producer.fctl_mem, 1) orelse return error.FctlNewFailed;
        const fctl_ptr = c_abi.fctl.join(shfctl) orelse return error.FctlJoinFailed;
        _ = c_abi.fctl.cfgRxAdd(fctl_ptr, handles.depth, @volatileCast(joined.fseq), @ptrCast(&producer.slow_count)) orelse return error.FctlCfgRxAddFailed;
        _ = c_abi.fctl.cfgDone(fctl_ptr, 1, 0, 0, 0) orelse return error.FctlCfgDoneFailed;
        producer.cr_avail = c_abi.fctl.crMax(fctl_ptr);
        return producer;
    }

    fn fctlPtr(self: *Producer) *c_abi.fctl.Fctl {
        return c_abi.fctl.join(&self.fctl_mem) orelse unreachable;
    }

    pub fn leave(self: *Producer) void {
        _ = c_abi.queue.mcacheLeave(self.mcache);
        _ = c_abi.dcache.dcacheLeave(self.dcache_base);
        _ = c_abi.fseq.fseqLeave(@volatileCast(self.fseq));
        _ = c_abi.fctl.leave(self.fctlPtr());
        _ = c_abi.fctl.delete(&self.fctl_mem);
    }

    fn writeSlot(self: *Producer, payload: []const u8) !u32 {
        if (payload.len > self.mtu) return error.PayloadTooLarge;
        const line = c_abi.queue.mcacheLineIdx(self.next_seq, self.depth);
        const slot_footprint = c_abi.dcache.dcacheSlotFootprint(self.mtu);
        const slot = self.dcache_base[line * slot_footprint ..][0..slot_footprint];
        @memcpy(slot[0..payload.len], payload);
        const gaddr = c_abi.wksp.wkspGaddr(self.wksp, &slot[0]);
        return @intCast(gaddr / c_abi.dcache.chunk_align);
    }

    /// Blocks until the consumer has room or stop is signalled. Polls with a
    /// bounded spin-pause budget before backing off to a bounded sleep; see
    /// runtime/link/wait.zig for why this deviates from Firedancer's
    /// non-sleeping hot transmit path.
    ///
    /// `cnc`, if non-null, gets a heartbeat and a halt-signal check on every
    /// idle-backoff iteration (v2.14.S8.T6) — this is what makes a producer
    /// blocked inside this wait still visible to supervisor-side
    /// heartbeat-staleness detection and still responsive to a HALT that
    /// arrives mid-wait, instead of only being checked between stage
    /// iterations. Optional (not folded into `stop`) so link-primitive
    /// tests can exercise backpressure/timeout behavior without a real cnc.
    pub fn publish(
        self: *Producer,
        payload: []const u8,
        backpressure_waits: *std.atomic.Value(u64),
        stop: *const std.atomic.Value(bool),
        cnc: ?*c_abi.cnc.Cnc,
    ) error{ Stopped, PayloadTooLarge }!void {
        return self.publishFragment(payload, 0, 0, backpressure_waits, stop, cnc);
    }

    /// `publish` with an explicit fragment `sig` and control bits (`ctl`: SOM
    /// bit 0, EOM bit 1), for a multipart message. A message larger than one
    /// fragment is a contiguous run of these calls, each waiting for credit.
    pub fn publishFragment(
        self: *Producer,
        payload: []const u8,
        sig: u64,
        ctl: u16,
        backpressure_waits: *std.atomic.Value(u64),
        stop: *const std.atomic.Value(bool),
        cnc: ?*c_abi.cnc.Cnc,
    ) error{ Stopped, PayloadTooLarge }!void {
        const fctl_ptr = self.fctlPtr();
        ready: while (true) {
            if (self.cr_avail >= c_abi.fctl.crBurst(fctl_ptr)) break :ready;
            self.cr_avail = c_abi.fctl.crQuery(fctl_ptr, self.next_seq, null);
            if (self.cr_avail >= c_abi.fctl.crBurst(fctl_ptr)) break :ready;
            var spins: u32 = 0;
            while (spins < wait.spin_poll_max) : (spins += 1) c_abi.boot.spinPause();
            _ = backpressure_waits.fetchAdd(1, .release);
            if (stop.load(.acquire)) return error.Stopped;
            if (cnc) |c| {
                c_abi.cnc.heartbeat(c, process.monotonicNanos());
                if (c_abi.cnc.signalQuery(c) == c_abi.cnc.signal_halt) return error.Stopped;
            }
            process.sleepNanos(wait.idle_sleep_ns);
        }

        const chunk = try self.writeSlot(payload);
        c_abi.queue.mcachePublish(self.mcache, self.depth, self.next_seq, sig, chunk, @intCast(payload.len), ctl, 0, 0);
        self.next_seq += 1;
        self.cr_avail -= 1;
    }

    /// Fragments published and not yet consumed, at most the link depth. A
    /// consumer that has not published its position yet (the topology creates the
    /// fseq at the maximum sequence) has consumed nothing.
    pub fn backlog(self: *const Producer) u64 {
        const consumer_seq = c_abi.fseq.fseqQuery(self.fseq);
        const lag = if (consumer_seq == std.math.maxInt(u64)) self.next_seq else self.next_seq -% consumer_seq;
        return @min(lag, self.depth);
    }

    pub fn publishLossy(self: *Producer, payload: []const u8, dropped: *std.atomic.Value(u64)) error{PayloadTooLarge}!void {
        const consumer_seq = c_abi.fseq.fseqQuery(self.fseq);
        const lag = self.next_seq -% consumer_seq;
        if (lag >= self.depth) _ = dropped.fetchAdd(1, .release);

        const chunk = try self.writeSlot(payload);
        c_abi.queue.mcachePublish(self.mcache, self.depth, self.next_seq, 0, chunk, @intCast(payload.len), 0, 0, 0);
        self.next_seq += 1;
    }
};
