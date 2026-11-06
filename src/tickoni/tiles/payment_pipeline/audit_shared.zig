/// Shared constants used across the payment-pipeline audit stages.
/// Extracted from audit_sink.zig so consumers do not need the full audit
/// sink module just to read tile ids or the audit seed.
const std = @import("std");

pub const tile_id_tknorm: [6]u8 = "tknorm".*;
pub const tile_id_tkdedu: [6]u8 = "tkdedu".*;
pub const tile_id_tkpoly: [6]u8 = "tkpoly".*;
pub const audit_seed: u64 = 0xcbf29ce484222325;
