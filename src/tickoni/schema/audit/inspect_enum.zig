const std = @import("std");

// Inspect what translate-c generates for PolicyOutcome
const audit_mod = @import("audit_mod");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    // Print the type info for PolicyOutcome from translate-c
    const ty = @TypeOf(audit_mod.PolicyOutcome);
    try stdout.print("audit_mod.PolicyOutcome type info:\n", .{});

    // Check if it's an enum or c_uint
    const fields = @typeInfo(ty);
    try stdout.print("  TypeInfo kind: {any}\n", .{fields});

    // Try to see actual enum values
    switch (fields) {
        .@"enum" => |info| {
            try stdout.print("  Is a proper Zig enum with {d} tags\n", .{info.tag_type});
        },
        .@"struct" => |info| {
            try stdout.print("  Is a struct with {d} fields\n", .{info.fields.len});
            for (info.fields) |f| {
                try stdout.print("    field: {s} type={any}\n", .{ f.name, f.field_type });
            }
        },
        .int => |info| {
            try stdout.print("  Is an int type with {d} bits, signed={any}\n", .{ info.bits, info.signedness });
        },
        else => |info| {
            try stdout.print("  TypeInfo: {any}\n", .{info});
        },
    }

    // Check AuditHeader
    const header_ty = audit_mod.AuditHeader;
    const header_info = @typeInfo(header_ty);
    switch (header_info) {
        .@"struct" => |info| {
            try stdout.print("\naudit_mod.AuditHeader: {d} fields, size={d}, align={d}\n", .{ info.fields.len, @sizeOf(header_ty), @alignOf(header_ty) });
        },
        else => {},
    }

    // Check PolicyDecisionPayload from C
    const pdp_ty = audit_mod.PolicyDecisionPayload;
    const pdp_info = @typeInfo(pdp_ty);
    switch (pdp_info) {
        .@"struct" => |info| {
            try stdout.print("\naudit_mod.PolicyDecisionPayload: {d} fields\n", .{info.fields.len});
            for (info.fields, 0..) |f, i| {
                try stdout.print("  [{d}] {s} type={any} (is_enum: {any})\n", .{ i, f.name, f.field_type, @typeInfo(f.field_type) });
            }
        },
        else => {},
    }
}
