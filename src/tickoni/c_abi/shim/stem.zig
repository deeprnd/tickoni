/// Zig bindings for tk_stem_zig.h — provides `stemRegisterCtx` to populate
/// `tk_stem_ctx_t` in workspace at tile_obj_id, so fd_stem can dispatch
/// into Zig during its run loop.
///
/// Called from tile_process.zig's `tk_tile_privileged_init` via
/// `stemRegisterCtx()` — before `fd_stem_run` starts its loop.

const c_abi = @import("../c_abi.zig");
const std = @import("std");

/// Callback function pointer types — Zig exports functions matching these signatures.
pub const BeforeCreditFn = *const fn (zig_state: *anyopaque, stem: *anyopaque, charge_busy: *c_int) callconv(.c) void;
pub const DuringFragFn = *const fn (zig_state: *anyopaque, idx: c_uint, seq: c_ulong, sig: c_uint, chunk: c_ulong, sz: c_uint, ctl: c_uint) callconv(.c) void;
pub const AfterCreditFn = *const fn (zig_state: *anyopaque, stem: *anyopaque, poll_in: *c_int, charge_busy: *c_int) callconv(.c) void;
pub const MetricsWriteFn = *const fn (zig_state: *anyopaque) callconv(.c) void;
pub const ShouldShutdownFn = *const fn (zig_state: *anyopaque) callconv(.c) c_int;

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
    // Convert optional callbacks to function pointers (or null)
    tk_stem_register_ctx(
        topo,
        tile,
        zig_state,
        wksp,
        before_credit orelse null,
        during_frag orelse null,
        after_credit orelse null,
        metrics_write orelse null,
        should_shutdown orelse null,
    );
}
