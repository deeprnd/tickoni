/// Zig bindings for tk_stem_zig.h — provides `stemRegisterCtx` to populate
/// `tk_stem_ctx_t` in workspace at tile_obj_id, so fd_stem can dispatch
/// into Zig during its run loop.
///
/// Called from tile_process.zig's `tk_tile_privileged_init` via
/// `stemRegisterCtx()` — before `fd_stem_run` starts its loop.
const c_abi = @import("../c_abi.zig");
const std = @import("std");

/// Callback function pointer types — Zig exports functions matching these signatures.
pub const BeforeCreditFn = *allowzero const fn (zig_state: *anyopaque, stem: *anyopaque, charge_busy: *c_int) callconv(.c) void;
pub const DuringFragFn = *allowzero const fn (zig_state: *anyopaque, idx: c_uint, seq: c_ulong, sig: c_uint, chunk: c_ulong, sz: c_uint, ctl: c_uint) callconv(.c) void;
pub const AfterCreditFn = *allowzero const fn (zig_state: *anyopaque, stem: *anyopaque, poll_in: *c_int, charge_busy: *c_int) callconv(.c) void;
pub const MetricsWriteFn = *allowzero const fn (zig_state: *anyopaque) callconv(.c) void;
pub const ShouldShutdownFn = *allowzero const fn (zig_state: *anyopaque) callconv(.c) c_int;

extern fn tk_stem_register_ctx(
    topo: *anyopaque,
    tile: *anyopaque,
    zig_state: *anyopaque,
    wksp: *anyopaque,
    before_credit: BeforeCreditFn,
    during_frag: DuringFragFn,
    after_credit: AfterCreditFn,
    metrics_write: MetricsWriteFn,
    should_shutdown: ShouldShutdownFn,
) void;

/// Register tile callbacks: populates `tk_stem_ctx_t` in workspace at
/// tile_obj_id. Called once from tile_process.zig's `tk_tile_privileged_init`
/// before fd_stem_run starts.
///
/// All callback pointers may be null for tiles that don't need them.
pub fn stemRegisterCtx(
    topo: *anyopaque,
    tile: *anyopaque,
    zig_state: *anyopaque,
    wksp: *anyopaque,
    before_credit: ?BeforeCreditFn,
    during_frag: ?DuringFragFn,
    after_credit: ?AfterCreditFn,
    metrics_write: ?MetricsWriteFn,
    should_shutdown: ?ShouldShutdownFn,
) void {
    // Convert optional callbacks to function pointers.
    // Zig 0.17: can't cast zero address; use zeroes for null fn ptr representation.
    const null_bc: BeforeCreditFn = std.mem.zeroes(BeforeCreditFn);
    const null_df: DuringFragFn = std.mem.zeroes(DuringFragFn);
    const null_ac: AfterCreditFn = std.mem.zeroes(AfterCreditFn);
    const null_mw: MetricsWriteFn = std.mem.zeroes(MetricsWriteFn);
    const null_ss: ShouldShutdownFn = std.mem.zeroes(ShouldShutdownFn);
    tk_stem_register_ctx(
        topo,
        tile,
        zig_state,
        wksp,
        if (before_credit) |v| v else null_bc,
        if (during_frag) |v| v else null_df,
        if (after_credit) |v| v else null_ac,
        if (metrics_write) |v| v else null_mw,
        if (should_shutdown) |v| v else null_ss,
    );
}
