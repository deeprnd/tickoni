/// Shared symbols from audit_sink.zig that consumers import independently.
/// This module replaces `audit_sink` imports in normalize.zig, policy.zig,
/// replay.zig, runtime.zig for constant lookups.
pub const tile_id_tknorm: [6]u8 = "tknorm".*;
pub const tile_id_tkdedu: [6]u8 = "tkdedu".*;
pub const tile_id_tkpoly: [6]u8 = "tkpoly".*;

pub const audit_seed: u64 = 0xcbf29ce484222325;
