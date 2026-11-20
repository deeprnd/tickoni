const std = @import("std");

/// Narrow Zig bindings over src/disco/topo/fd_topo.h's per-process tile
/// launcher: on Linux, process mode must stay on upstream fd_topo_run_tile
/// (join workspaces -> privileged_init -> sandbox/user switch -> fill links
/// -> register metrics/events -> unprivileged_init -> run -> enforce
/// shutdown); on non-Linux, Tickoni's shim mirrors the same workflow where
/// upstream's Linux-only implementation is unavailable. This file and
/// shim/topo_run.c are the only places fd_topo_t/fd_topo_tile_t exist in
/// Tickoni, even by name — Topo/TopoTile below are opaque; nothing outside
/// this file may construct or introspect them.
///
/// v2.14.S8.T3 delivers only this adapter. Nothing calls it yet: building
/// a real fd_topo_t/fd_topo_tile_t (a thin Tickoni struct embedding their
/// Solana-free fields) and migrating tile_process.zig's lifecycle to call
/// topoRunTile is v2.14.S8.T4.
///
/// Link requirements: -lfd_disco -lfd_ballet -lfd_waltz (plus -lfd_tango
/// -lfd_util, already required by other c_abi wrappers) and
/// shim/topo_run.c at link time.
/// Opaque handle for fd_topo_t. Only shim/topo_run.c knows its real layout.
pub const Topo = opaque {};
/// Opaque handle for fd_topo_tile_t. Only shim/topo_run.c knows its real layout.
pub const TopoTile = opaque {};

// ---------------------------------------------------------------------------
// Extern declarations — require -lfd_disco -lfd_ballet -lfd_waltz -lfd_tango
// -lfd_util at link time
// ---------------------------------------------------------------------------

extern fn tk_topo_join_tile_workspaces(topo: *Topo, tile: *TopoTile, core_dump_level: c_int) void;
extern fn tk_topo_fill_tile(topo: *Topo, tile: *TopoTile) void;
extern fn tk_topo_run_tile(
    topo: *Topo,
    tile: *TopoTile,
    sandbox: c_int,
    keep_controlling_terminal: c_int,
    core_dump_level: c_int,
    uid: c_uint,
    gid: c_uint,
    allow_fd: c_int,
    /// *const fd_topo_run_tile_t. Stays untyped here too — the shim casts
    /// and forwards without needing the real 9-field struct layout on the
    /// Zig side; T4 defines the matching Zig type for Tickoni's own
    /// callbacks and passes its address through here.
    tile_run: *anyopaque,
) void;

/// v2.14.S8.T4: simplified entry point wired to Tickoni's own
/// fd_topo_run_tile_t (built entirely inside shim/tile_run.c from two
/// Zig `export fn` callbacks — see tile_process.zig's
/// tk_tile_privileged_init/tk_tile_run). Linux dispatches directly to
/// upstream fd_topo_run_tile(); non-Linux dispatches to Tickoni's shim.
/// sandbox=0, current process's own uid/gid, regular core dumps.
extern fn tk_topo_run_tile_simple(topo: *Topo, tile: *TopoTile) void;
extern fn tk_topo_run_tile_simple_uses_upstream() c_int;

// ---------------------------------------------------------------------------
// Public Zig wrappers.
// ---------------------------------------------------------------------------

pub fn topoJoinTileWorkspaces(topo: *Topo, tile: *TopoTile, core_dump_level: i32) void {
    tk_topo_join_tile_workspaces(topo, tile, core_dump_level);
}

pub fn topoFillTile(topo: *Topo, tile: *TopoTile) void {
    tk_topo_fill_tile(topo, tile);
}

pub fn topoRunTile(
    topo: *Topo,
    tile: *TopoTile,
    sandbox: bool,
    keep_controlling_terminal: bool,
    core_dump_level: i32,
    uid: u32,
    gid: u32,
    allow_fd: i32,
    tile_run: *anyopaque,
) void {
    tk_topo_run_tile(
        topo,
        tile,
        @intFromBool(sandbox),
        @intFromBool(keep_controlling_terminal),
        core_dump_level,
        uid,
        gid,
        allow_fd,
        tile_run,
    );
}

pub fn runTileSimple(topo: *Topo, tile: *TopoTile) void {
    tk_topo_run_tile_simple(topo, tile);
}

pub fn runTileSimpleUsesUpstream() bool {
    return tk_topo_run_tile_simple_uses_upstream() != 0;
}

test "runTileSimple dispatch stays on the canonical Linux launcher" {
    try std.testing.expectEqual(@import("builtin").os.tag == .linux, runTileSimpleUsesUpstream());
}
