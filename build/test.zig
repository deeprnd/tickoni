/// Entry point for @import("build/test.zig").
/// Exports registry, helpers, unit/cov/integration/system specs.

pub const registry = @import("test/registry.zig");
pub const helpers = @import("test/helpers.zig");
pub const unit_specs = @import("test/unit_specs.zig");
pub const cov_specs = @import("test/cov_specs.zig");
pub const integration_specs = @import("test/integration_specs.zig");
pub const system_specs = @import("test/system_specs.zig");
