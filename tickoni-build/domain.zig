/// Main module declarations entry point for the Tickoni build system.
///
/// Re-exports from build/domain/ directory.

const std = @import("std");

pub const domain = @import("tickoni-build/domain/domain.zig");
pub const builder = @import("tickoni-build/domain/builder.zig");
pub const common = @import("tickoni-build/domain/common.zig");
pub const ballet = @import("tickoni-build/domain/ballet.zig");
pub const flamenco = @import("tickoni-build/domain/flamenco.zig");
pub const disco = @import("tickoni-build/domain/disco.zig");

pub const Domain = domain.Domain;
pub const DomainName = domain.DomainName;
