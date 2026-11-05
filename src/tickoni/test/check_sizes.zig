const std = @import("std");
const audit = @import("../schema/audit/audit.zig");

pub fn main() void {
    std.debug.print("Header size: {d}\n", .{@sizeOf(audit.Header)});
    std.debug.print("PolicyDecisionPayload size: {d}\n", .{@sizeOf(audit.PolicyDecisionPayload)});
    std.debug.print("AuditEvent size: {d}\n", .{@sizeOf(audit.AuditEvent)});
}
