/// Root of the tickoni runtime module: Tickoni's own process lifecycle,
/// topology, channels, and backpressure. Generic Linux/CPU primitives with
/// no Tickoni domain knowledge live in src/tickoni/util/ instead.
/// Import as @import("runtime") in files that use the build module system.
pub const topology = @import("topology.zig");
pub const tile = @import("tile.zig");
pub const link = @import("link.zig");
pub const launch_spec = @import("launch_spec.zig");
pub const cpu_placement = @import("cpu_placement.zig");
pub const boot = @import("boot.zig");
pub const cnc_counters = @import("cnc_counters.zig");
pub const sandbox = @import("sandbox.zig");
pub const tile_process = @import("tile_process.zig");
pub const topo_build = @import("topo_build.zig");
pub const topology_spec = @import("topology_spec.zig");
pub const file_io = @import("file_io.zig");
