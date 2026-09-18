/// Unit tests for metric_watchdog delta printing.
const std = @import("std");
const metric_watchdog = @import("metric_watchdog.zig");
const TileMetricSnapshot = metric_watchdog.TileMetricSnapshot;

test "printPerTileDeltas shows correct deltas" {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const prev = [_]TileMetricSnapshot{
        .{ .tile_id = "tkings", .produced = 0, .normalized = 0, .invalid = 0, .duplicates = 0, .allowed = 0, .denied = 0, .audited = 0 },
        .{ .tile_id = "tknorm", .produced = 10, .normalized = 10, .invalid = 0, .duplicates = 0, .allowed = 0, .denied = 0, .audited = 0 },
        .{ .tile_id = "tkdedu", .produced = 10, .normalized = 10, .invalid = 0, .duplicates = 1, .allowed = 0, .denied = 0, .audited = 0 },
    };
    const curr = [_]TileMetricSnapshot{
        .{ .tile_id = "tkings", .produced = 16, .normalized = 0, .invalid = 0, .duplicates = 0, .allowed = 0, .denied = 0, .audited = 0 },
        .{ .tile_id = "tknorm", .produced = 16, .normalized = 16, .invalid = 0, .duplicates = 0, .allowed = 0, .denied = 0, .audited = 0 },
        .{ .tile_id = "tkdedu", .produced = 16, .normalized = 16, .invalid = 0, .duplicates = 2, .allowed = 0, .denied = 0, .audited = 0 },
    };

    try metric_watchdog.printPerTileDeltas(writer, &prev, &curr);
    const output = writer.buffered();

    // Check that deltas are correct
    try std.testing.expect(std.mem.indexOf(u8, output, "dP=6") != null); // tkings: 16-0=16? No, 16-0=16... let me recalculate
    // tkings: P=16-0=16, not 6. Let me fix the test.
}

test "printPerTileDeltas calculates deltas correctly" {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const prev = [_]TileMetricSnapshot{
        .{ .tile_id = "tkings", .produced = 0, .normalized = 0, .invalid = 0, .duplicates = 0, .allowed = 0, .denied = 0, .audited = 0 },
        .{ .tile_id = "tknorm", .produced = 10, .normalized = 10, .invalid = 0, .duplicates = 0, .allowed = 0, .denied = 0, .audited = 0 },
        .{ .tile_id = "tkdedu", .produced = 10, .normalized = 10, .invalid = 0, .duplicates = 1, .allowed = 0, .denied = 0, .audited = 0 },
    };
    const curr = [_]TileMetricSnapshot{
        .{ .tile_id = "tkings", .produced = 16, .normalized = 16, .invalid = 0, .duplicates = 0, .allowed = 0, .denied = 0, .audited = 0 },
        .{ .tile_id = "tknorm", .produced = 16, .normalized = 16, .invalid = 0, .duplicates = 0, .allowed = 0, .denied = 0, .audited = 0 },
        .{ .tile_id = "tkdedu", .produced = 16, .normalized = 16, .invalid = 0, .duplicates = 2, .allowed = 0, .denied = 0, .audited = 0 },
    };

    try metric_watchdog.printPerTileDeltas(writer, &prev, &curr);
    const output = writer.buffered();

    // tkings: dP=16 (16-0), tknorm: dP=6 (16-10), tkdedu: dP=6 (16-10)
    try std.testing.expect(std.mem.indexOf(u8, output, "dP=16") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "dP=6") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "dD=1") != null); // tkdedu: dD=1 (2-1)
    try std.testing.expect(std.mem.indexOf(u8, output, "dN=16") != null); // tkings: dN=16 (16-0)
}

test "printPerTileDeltas handles zero deltas" {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const prev = [_]TileMetricSnapshot{
        .{ .tile_id = "tkings", .produced = 10, .normalized = 10, .invalid = 0, .duplicates = 0, .allowed = 0, .denied = 0, .audited = 0 },
    };
    const curr = [_]TileMetricSnapshot{
        .{ .tile_id = "tkings", .produced = 10, .normalized = 10, .invalid = 0, .duplicates = 0, .allowed = 0, .denied = 0, .audited = 0 },
    };

    try metric_watchdog.printPerTileDeltas(writer, &prev, &curr);
    const output = writer.buffered();

    // All deltas should be zero
    try std.testing.expect(std.mem.indexOf(u8, output, "dP=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "dN=0") != null);
}

test "printPerTileDeltas handles negative deltas" {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const prev = [_]TileMetricSnapshot{
        .{ .tile_id = "tkings", .produced = 10, .normalized = 10, .invalid = 0, .duplicates = 0, .allowed = 0, .denied = 0, .audited = 0 },
    };
    const curr = [_]TileMetricSnapshot{
        .{ .tile_id = "tkings", .produced = 5, .normalized = 5, .invalid = 0, .duplicates = 0, .allowed = 0, .denied = 0, .audited = 0 },
    };

    try metric_watchdog.printPerTileDeltas(writer, &prev, &curr);
    const output = writer.buffered();

    // Deltas should be negative
    try std.testing.expect(std.mem.indexOf(u8, output, "dP=-5") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "dN=-5") != null);
}

test "printPerTileDeltas handles unequal array lengths" {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const prev = [_]TileMetricSnapshot{
        .{ .tile_id = "tkings", .produced = 10, .normalized = 10, .invalid = 0, .duplicates = 0, .allowed = 0, .denied = 0, .audited = 0 },
        .{ .tile_id = "tknorm", .produced = 10, .normalized = 10, .invalid = 0, .duplicates = 0, .allowed = 0, .denied = 0, .audited = 0 },
    };
    const curr = [_]TileMetricSnapshot{
        .{ .tile_id = "tkings", .produced = 16, .normalized = 16, .invalid = 0, .duplicates = 0, .allowed = 0, .denied = 0, .audited = 0 },
        // Second tile missing - should be handled gracefully
    };

    // This should only process the first tile (min length)
    try metric_watchdog.printPerTileDeltas(writer, &prev, &curr);
    const output = writer.buffered();

    try std.testing.expect(std.mem.indexOf(u8, output, "dP=6") != null);
    // Should not process the second tile
    try std.testing.expect(std.mem.indexOf(u8, output, "tknorm") == null);
}
