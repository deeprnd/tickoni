/// Domain system types for the Tickoni build system.
///
/// A domain is a named, compilable unit that may depend on other domains.
/// Domains are loaded from config and resolved recursively.

const std = @import("std");
const base = @import("../strategy/base.zig");

/// Build result for any domain strategy: an archive (optional) and a module.
pub const DomainResult = base.DomainResult;

/// Map from domain name to its build result.
pub const DomainMap = std.StringHashMap(DomainResult);

/// Initialize an empty domain map.
pub fn initDomainMap(allocator: std.mem.Allocator) !DomainMap {
    return DomainMap.init(allocator);
}

/// Get a domain's result by name.
pub fn get(map: *const DomainMap, name: []const u8) ?DomainResult {
    return map.get(name);
}

/// Insert a domain into the map.
pub fn put(map: *DomainMap, key: []const u8, value: DomainResult) !void {
    try map.put(key, value);
}
