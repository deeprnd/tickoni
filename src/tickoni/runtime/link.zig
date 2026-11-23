/// Runtime-owned link contracts and shared-memory link role implementations.
/// This module owns link descriptors, workspace names, handle PODs, and the
/// producer/consumer/factory split used by process-mode tiles.
const types = @import("link/types.zig");
const handles = @import("link/handles.zig");
const factory = @import("link/factory.zig");
const producer = @import("link/producer.zig");
const consumer = @import("link/consumer.zig");

pub const WorkspaceName = types.WorkspaceName;
pub const LinkBacking = types.LinkBacking;
pub const LinkReliability = types.LinkReliability;
pub const Channel = types.Channel;
pub const external_src = types.external_src;

pub const LinkHandles = handles.LinkHandles;
pub const Producer = producer.Producer;
pub const Consumer = consumer.Consumer;

pub const create = factory.create;
