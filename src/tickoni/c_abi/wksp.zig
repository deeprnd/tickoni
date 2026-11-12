/// Narrow Zig bindings over the subset of src/util/wksp/fd_wksp.h needed to
/// create/join a named, process-shared workspace that backs Tango
/// mcache/dcache/fseq/cnc objects for v2.14 process mode.
///
/// Uses FD_SHMEM_NORMAL_PAGE_SZ (4 KiB) workspaces, which fd_wksp_new_named
/// backs with a plain file under the FD_SHMEM_PATH directory (see
/// src/util/shmem/fd_shmem_admin.c) rather than hugetlbfs — no gigantic/huge
/// pages or root privileges are required, matching the roadmap requirement
/// that Tickoni not inherit Firedancer validator's hugepage assumption.
///
/// Link requirements: -lfd_util plus shim/wksp.c at link time.
const std = @import("std");

// ---------------------------------------------------------------------------
// Constants (from fd_shmem.h)
// ---------------------------------------------------------------------------

pub const shmem_normal_page_sz: usize = 4096;

/// Opaque workspace handle returned by fd_wksp_new_named / fd_wksp_attach.
pub const Wksp = opaque {};

// ---------------------------------------------------------------------------
// Extern declarations — require -lfd_util at link time
// ---------------------------------------------------------------------------

pub const wksp_success: c_int = 0;

/// Returns FD_WKSP_SUCCESS (0) or a negative FD_WKSP_ERR_* code — NOT a
/// workspace handle. Call wkspAttach afterward to join it.
extern fn tk_wksp_new_named(
    name: [*:0]const u8,
    page_sz: usize,
    sub_cnt: usize,
    sub_page_cnt: [*]const usize,
    sub_cpu_idx: [*]const usize,
    mode: usize,
    seed: u32,
    opt_part_max: usize,
) c_int;
extern fn tk_wksp_delete_named(name: [*:0]const u8) c_int;
extern fn tk_wksp_attach(name: [*:0]const u8) ?*Wksp;
extern fn tk_wksp_detach(wksp: *Wksp) c_int;
extern fn tk_wksp_alloc_at_least(
    wksp: *Wksp,
    alignment: usize,
    sz: usize,
    tag: usize,
    lo: *usize,
    hi: *usize,
) usize;
extern fn tk_wksp_alloc(wksp: *Wksp, alignment: usize, sz: usize, tag: usize) usize;
extern fn tk_wksp_free(wksp: *Wksp, gaddr: usize) void;
extern fn tk_wksp_laddr(wksp: *const Wksp, gaddr: usize) ?*anyopaque;
extern fn tk_wksp_gaddr(wksp: *const Wksp, laddr: *const anyopaque) usize;
extern fn tk_wksp_exists_named(name: [*:0]const u8) c_int;

pub fn wkspNewNamed(
    name: [*:0]const u8,
    page_sz: usize,
    sub_cnt: usize,
    sub_page_cnt: [*]const usize,
    sub_cpu_idx: [*]const usize,
    mode: usize,
    seed: u32,
    opt_part_max: usize,
) c_int {
    return tk_wksp_new_named(name, page_sz, sub_cnt, sub_page_cnt, sub_cpu_idx, mode, seed, opt_part_max);
}

pub fn wkspDeleteNamed(name: [*:0]const u8) c_int {
    return tk_wksp_delete_named(name);
}

pub fn wkspAttach(name: [*:0]const u8) ?*Wksp {
    return tk_wksp_attach(name);
}

pub fn wkspDetach(wksp: *Wksp) c_int {
    return tk_wksp_detach(wksp);
}

pub fn wkspAllocAtLeast(wksp: *Wksp, alignment: usize, sz: usize, tag: usize, lo: *usize, hi: *usize) usize {
    return tk_wksp_alloc_at_least(wksp, alignment, sz, tag, lo, hi);
}

/// Mirrors the upstream workspace allocation helper: a fixed-alignment
/// wrapper around fd_wksp_alloc_at_least with dummy [lo,hi) outputs.
pub fn wkspAlloc(wksp: *Wksp, alignment: usize, sz: usize, tag: usize) usize {
    return tk_wksp_alloc(wksp, alignment, sz, tag);
}

pub fn wkspFree(wksp: *Wksp, gaddr: usize) void {
    tk_wksp_free(wksp, gaddr);
}

pub fn wkspLaddr(wksp: *const Wksp, gaddr: usize) ?*anyopaque {
    return tk_wksp_laddr(wksp, gaddr);
}

pub fn wkspGaddr(wksp: *const Wksp, laddr: *const anyopaque) usize {
    return tk_wksp_gaddr(wksp, laddr);
}

pub fn wkspExistsNamed(name: [*:0]const u8) bool {
    return tk_wksp_exists_named(name) != 0;
}

// ---------------------------------------------------------------------------
// Canonical workspace names for Tickoni topology.
// These mirror Firedancer's workspace name conventions used by
// the metric tile (fd_tile_metric.name = "metric") and the
// metric_in workspace that collects metric tile outputs.
//
// topo_build.zig and supervisor.zig use these constants instead
// of raw string literals to keep topology declaration centralized.
// ---------------------------------------------------------------------------

pub const wksp_name_metric: [*:0]const u8 = "metric";
pub const wksp_name_metric_in: [*:0]const u8 = "metric_in";

// ---------------------------------------------------------------------------
// Tests — constants only; no C linkage required
// ---------------------------------------------------------------------------

test "shmem normal page size matches header" {
    try std.testing.expectEqual(@as(usize, 4096), shmem_normal_page_sz);
}
