/// Comptime descriptor for the `tk_get_<stem>_run_*` accessor set that every
/// fd_stem tile shim exports (see c_abi/shim/topo_run/tk_*_stem.h): the tile
/// name, the `fd_topo_run_tile_t` pointer, and its run / scratch / init
/// callback pointers.
///
/// `sym` is the C symbol infix (e.g. "policy" -> `tk_get_policy_run_name`).
/// The symbol set is a closed list built here, not looked up at runtime, so a
/// missing C export is still a link error. Tile-specific accessors (scratch
/// footprint, counters, setters) stay as explicit `extern fn` declarations in
/// each tile's own module.
///
/// Not used by audit.zig: it is its own build module (`c_abi_audit`) and
/// cannot import files that also belong to the `c_abi` module.
pub fn RunDescriptor(comptime sym: []const u8, comptime Tile: type) type {
    return struct {
        fn accessor(comptime T: type, comptime field: []const u8) *const fn () callconv(.c) T {
            return @extern(*const fn () callconv(.c) T, .{ .name = "tk_get_" ++ sym ++ "_run_" ++ field });
        }

        pub fn name() [*:0]const u8 {
            return accessor([*:0]const u8, "name")();
        }

        pub fn tile() ?*Tile {
            return accessor(?*Tile, "tile")();
        }

        pub fn run() ?*anyopaque {
            return accessor(?*anyopaque, "run")();
        }

        pub fn scratchAlign() ?*anyopaque {
            return accessor(?*anyopaque, "scratch_align")();
        }

        pub fn scratchFootprint() ?*anyopaque {
            return accessor(?*anyopaque, "scratch_footprint")();
        }

        pub fn privilegedInit() ?*anyopaque {
            return accessor(?*anyopaque, "privileged_init")();
        }

        pub fn unprivilegedInit() ?*anyopaque {
            return accessor(?*anyopaque, "unprivileged_init")();
        }
    };
}
