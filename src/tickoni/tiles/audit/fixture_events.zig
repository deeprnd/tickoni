const std = @import("std");
const schema = @import("types.zig");
const codec = @import("codec.zig");

/// Convert std.c.environ ([*:0]u8) to a proper slice for Environ.block.
fn getEnvSlice() []const [*:0]const u8 {
    const env = std.c.environ;
    var count: usize = 0;
    while (env[count] != null) : (count += 1) {}
    return env[0..count];
}

fn parseFixedAsciiBytes(comptime N: usize, value: []const u8) ![N]u8 { if (value.len > N) return error.StringTooLong;
    var out: [N]u8 = std.mem.zeroes([N]u8);
    for (value, 0..) |byte, idx| { if (byte < 0x20 or byte > 0x7e) return error.InvalidStringByte;
        out[idx] = byte; }
    return out;
}

fn fixtureHeader(
    seq: u64,
    source_offset: u64,
    tile_id: []const u8,
    logical_actor_id: u64,
    policy_version: []const u8,
    capability_envelope_id: u128,
    timestamp_ns: u64,
    prev_hash: u64,
    run_id: u64,
    runtime_tier: []const u8,
    isolation_tier: []const u8,
    release_digest: []const u8,
    demo_manifest_id: []const u8,
    tickoni_version: []const u8,
) schema.Header { var hdr = std.mem.zeroes(schema.Header);
    hdr.schema_version = schema.audit_schema_version;
    hdr.run_id = run_id;
    hdr.seq = seq;
    hdr.source_offset = source_offset;
    hdr.tile_id = parseFixedAsciiBytes(6, tile_id) catch unreachable;
    hdr.logical_actor_id = logical_actor_id;
    hdr.policy_version = parseFixedAsciiBytes(32, policy_version) catch unreachable;
    hdr.capability_envelope_id = capability_envelope_id;
    hdr.timestamp_ns = timestamp_ns;
    hdr.prev_hash = prev_hash;
    hdr.record_hash = 0;
    // T5: Populate runtime metadata from VersionInfo
    hdr.version = parseFixedAsciiBytes(64, tickoni_version) catch unreachable;
    hdr.platform_tier = parseFixedAsciiBytes(64, runtime_tier) catch unreachable;
    hdr.isolation_tier = parseFixedAsciiBytes(64, isolation_tier) catch unreachable;
    hdr.release_digest = parseFixedAsciiBytes(64, release_digest) catch unreachable;
    hdr.demo_manifest_id = parseFixedAsciiBytes(64, demo_manifest_id) catch unreachable;
    return hdr; }

pub fn makeFixtures() [12]schema.AuditEvent { // Runtime metadata populated from VersionInfo (T5)
    const version = "0.1.0-dev";
    const runtime = "linux_full";
    const isolation = "full";
    const digest = "abc123";
    const manifest_id = "demo.investment.v1";
    const headers = [_]schema.Header{
        fixtureHeader(1, 10, "tkings", 1001, "policy_ingress_v1", 1, 111, 500, 0, runtime, isolation, digest, manifest_id, version),
        fixtureHeader(2, 11, "tknorm", 1002, "policy_norm_v1", 2, 222, 501, 0, runtime, isolation, digest, manifest_id, version),
        fixtureHeader(3, 12, "tkpoly", 1003, "policy_poly_v1", 3, 333, 502, 0, runtime, isolation, digest, manifest_id, version),
        fixtureHeader(4, 13, "tkmodl", 1004, "policy_model_v1", 4, 444, 503, 0, runtime, isolation, digest, manifest_id, version),
        fixtureHeader(5, 14, "tkadpt", 1005, "policy_adpt_v1", 5, 555, 504, 0, runtime, isolation, digest, manifest_id, version),
        fixtureHeader(6, 15, "tkagnt", 1006, "policy_prop_v1", 6, 666, 505, 0, runtime, isolation, digest, manifest_id, version),
        fixtureHeader(7, 16, "tkpoly", 1007, "policy_dest_v1", 7, 777, 506, 0, runtime, isolation, digest, manifest_id, version),
        fixtureHeader(8, 17, "tkpoly", 1008, "policy_limt_v1", 8, 888, 507, 0, runtime, isolation, digest, manifest_id, version),
        fixtureHeader(9, 18, "tkpoly", 1009, "policy_aprv_v1", 9, 999, 508, 0, runtime, isolation, digest, manifest_id, version),
        fixtureHeader(10, 19, "tkpoly", 1010, "policy_deny_v1", 10, 1110, 509, 0, runtime, isolation, digest, manifest_id, version),
        fixtureHeader(11, 20, "tkmetr", 1011, "policy_metr_v1", 11, 1221, 510, 0, runtime, isolation, digest, manifest_id, version),
        fixtureHeader(12, 21, "tkrepl", 1012, "policy_repl_v1", 12, 1332, 511, 0, runtime, isolation, digest, manifest_id, version), };

    const events = [_]schema.AuditEvent{ codec.buildEvent(headers[0], .{ .source_event = .{
            .source_system = parseFixedAsciiBytes(16, "feed_alpha") catch unreachable,
            .event_type = parseFixedAsciiBytes(32, "payment_exception") catch unreachable,
            .raw_hash = 9001, } }),
        codec.buildEvent(headers[1], .{ .normalization = .{
            .source_event_hash = 9001,
            .normalized_hash = 9002,
            .canonical_event_type = parseFixedAsciiBytes(32, "payment.normalized") catch unreachable, } }),
        codec.buildEvent(headers[2], .{ .policy_decision = .{
            .outcome = .require_approval,
            .rule_id = 42,
            .failed_scope_dim = parseFixedAsciiBytes(32, "amount_limit") catch unreachable,
            .source_event_hash = 9002,
            .catalog_schema_version = 0,
            .taxonomy_id = std.mem.zeroes([32]u8),
            .taxonomy_version = 0,
            .classification_code = std.mem.zeroes([32]u8),
        } }),
        codec.buildEvent(headers[3], .{ .model_call = .{
            .model_id = parseFixedAsciiBytes(32, "gpt_local_stub") catch unreachable,
            .prompt_hash = 9100,
            .response_hash = 9101,
            .token_estimate = 512,
            .retry_count = 2,
            .actor_role = parseFixedAsciiBytes(16, "ops_reviewer") catch unreachable,
            .workflow = parseFixedAsciiBytes(16, "replay_demo") catch unreachable,
            .policy_decision_id = 77,
            .replay_substitution_id = 88, } }),
        codec.buildEvent(headers[4], .{ .financial_adapter_call = .{
            .adapter_id = parseFixedAsciiBytes(16, "broker") catch unreachable,
            .request_hash = 9200,
            .response_hash = 9201,
            .replay_substitution_id = 7, } }),
        codec.buildEvent(headers[5], .{ .proposal = .{
            .proposal_type = parseFixedAsciiBytes(32, "trading_order.propose") catch unreachable,
            .proposal_hash = 9300,
            .approval_state = 1, } }),
        codec.buildEvent(headers[6], .{ .destination_check = .{
            .destination_type = parseFixedAsciiBytes(16, "broker_account") catch unreachable,
            .allowlist_version = 8,
            .outcome = .allow, } }),
        codec.buildEvent(headers[7], .{ .limit_check = .{
            .limit_type = .per_day,
            .value = 1200,
            .limit = 1000,
            .outcome = .deny, } }),
        codec.buildEvent(headers[8], .{ .approval_required = .{
            .action_class = parseFixedAsciiBytes(32, "payment_retry.propose") catch unreachable,
            .approval_path = parseFixedAsciiBytes(32, "maker_checker") catch unreachable,
            .proposal_hash = 9300, } }),
        codec.buildEvent(headers[9], .{ .denial = .{
            .action_class = parseFixedAsciiBytes(32, "trading_order.place") catch unreachable,
            .reason_code = 17,
            .failed_scope_dim = parseFixedAsciiBytes(32, "environment") catch unreachable,
            .catalog_schema_version = 2,
            .taxonomy_id = parseFixedAsciiBytes(32, "gics_sector") catch unreachable,
            .taxonomy_version = 2025,
            .classification_code = parseFixedAsciiBytes(32, "materials") catch unreachable, } }),
        codec.buildEvent(headers[10], .{ .telemetry_checkpoint = .{
            .metric_set_hash = 9400,
            .source_offset_watermark = 41, } }),
        codec.buildEvent(headers[11], .{ .replay_result = .{
            .capsule_id = 9500,
            .divergences = 3,
            .first_divergent_seq = 9, } }),
    };

    return events;
}

test "computeRecordHash excludes timestamp_ns" { const hdr = fixtureHeader(0, 0, "tkpoly", 0, "policy", 0, 0, 0, 0, "linux_full", "full", "abc", "demo.v1", "0.1.0");
    const payload = schema.AuditEvent.Payload{ .policy_decision = .{
        .outcome = .allow,
        .rule_id = 1,
        .failed_scope_dim = parseFixedAsciiBytes(32, "scope") catch unreachable,
        .source_event_hash = 2,
        .catalog_schema_version = 0,
        .taxonomy_id = std.mem.zeroes([32]u8),
        .taxonomy_version = 0,
        .classification_code = std.mem.zeroes([32]u8),
    } };
    var header_with_timestamp = hdr;
    header_with_timestamp.timestamp_ns = 999_999;
    const e0 = codec.buildEvent(hdr, payload);
    const e1 = codec.buildEvent(header_with_timestamp, payload);
    try std.testing.expectEqual(e0.header.record_hash, e1.header.record_hash);
}

test "hash chain mutation changes downstream records" { const first = codec.buildEvent(fixtureHeader(0, 0, "tkpoly", 0, "policy", 0, 0, 0, 0, "linux_full", "full", "abc", "demo.v1", "0.1.0"), .{ .policy_decision = .{
        .outcome = .allow,
        .rule_id = 1,
        .failed_scope_dim = parseFixedAsciiBytes(32, "scope") catch unreachable,
        .source_event_hash = 3,
        .catalog_schema_version = 0,
        .taxonomy_id = std.mem.zeroes([32]u8),
        .taxonomy_version = 0,
        .classification_code = std.mem.zeroes([32]u8),
    } });
    var second_header = fixtureHeader(1, 1, "tkpoly", 0, "policy", 0, 0, first.header.record_hash, 0, "linux_full", "full", "abc", "demo.v1", "0.1.0");
    const second = codec.buildEvent(second_header, .{ .policy_decision = .{
        .outcome = .allow,
        .rule_id = 1,
        .failed_scope_dim = parseFixedAsciiBytes(32, "scope") catch unreachable,
        .source_event_hash = 3,
        .catalog_schema_version = 0,
        .taxonomy_id = std.mem.zeroes([32]u8),
        .taxonomy_version = 0,
        .classification_code = std.mem.zeroes([32]u8),
    } });

    const mutated_first = codec.buildEvent(fixtureHeader(0, 9, "tkpoly", 0, "policy", 0, 0, 0, 0, "linux_full", "full", "abc", "demo.v1", "0.1.0"), .{ .policy_decision = .{
        .outcome = .allow,
        .rule_id = 1,
        .failed_scope_dim = parseFixedAsciiBytes(32, "scope") catch unreachable,
        .source_event_hash = 3,
        .catalog_schema_version = 0,
        .taxonomy_id = std.mem.zeroes([32]u8),
        .taxonomy_version = 0,
        .classification_code = std.mem.zeroes([32]u8),
    } });
    second_header.prev_hash = mutated_first.header.record_hash;
    const mutated_second = codec.buildEvent(second_header, second.payload);

    try std.testing.expect(first.header.record_hash != mutated_first.header.record_hash);
    try std.testing.expect(second.header.record_hash != mutated_second.header.record_hash);
}

test "binary and wire format pinned" {
    const env = std.process.Environ{ .block = .{ .slice = getEnvSlice() } };
    if (std.process.getPosix(env, "TK_GEN_FIXTURES") != null) return error.SkipZigTest;
    const golden = @import("fixture_audit_gen").values;
    for (makeFixtures(), &golden) |event, g| {
        try std.testing.expectEqual(g.expected_hash, event.header.record_hash);
        var buf: [codec.max_binary_len]u8 = undefined;
        const binary = try codec.formatBinary(&buf, event);
        try std.testing.expectEqual(g.expected_binary_len, binary.len);
        try std.testing.expectEqualSlices(u8, g.expected_binary_bytes, binary); }
}

test "policy_decision and denial classification evidence survives binary round-trip" { const h = fixtureHeader(0, 0, "tkpoly", 0, "policy", 0, 0, 0, 0, "linux_full", "full", "abc", "demo.v1", "0.1.0");

    const policy_event = codec.buildEvent(h, .{ .policy_decision = .{
        .outcome = .deny,
        .rule_id = 1201,
        .failed_scope_dim = parseFixedAsciiBytes(32, "wrong_sector") catch unreachable,
        .source_event_hash = 4242,
        .catalog_schema_version = 2,
        .taxonomy_id = parseFixedAsciiBytes(32, "gics_sector") catch unreachable,
        .taxonomy_version = 2025,
        .classification_code = parseFixedAsciiBytes(32, "materials") catch unreachable, } });

    const denial_event = codec.buildEvent(h, .{ .denial = .{
        .action_class = parseFixedAsciiBytes(32, "trading_order.propose") catch unreachable,
        .reason_code = 9,
        .failed_scope_dim = parseFixedAsciiBytes(32, "wrong_sector") catch unreachable,
        .catalog_schema_version = 2,
        .taxonomy_id = parseFixedAsciiBytes(32, "gics_sector") catch unreachable,
        .taxonomy_version = 2025,
        .classification_code = parseFixedAsciiBytes(32, "materials") catch unreachable, } });

    for ([_]schema.AuditEvent{ policy_event, denial_event }) |event| { var binary_buf: [codec.max_binary_len]u8 = undefined;
        const binary = try codec.formatBinary(&binary_buf, event);
        const parsed = try codec.parseBinary(binary);
        try std.testing.expect(codec.auditEventsEql(event, parsed.event));

        switch (parsed.event.payload) {
            .policy_decision => |p| {
                try std.testing.expectEqual(@as(u32, 2), p.catalog_schema_version);
                try std.testing.expectEqualStrings("gics_sector", std.mem.sliceTo(&p.taxonomy_id, 0));
                try std.testing.expectEqual(@as(u32, 2025), p.taxonomy_version);
                try std.testing.expectEqualStrings("materials", std.mem.sliceTo(&p.classification_code, 0)); },
            .denial => |p| { try std.testing.expectEqual(@as(u32, 2), p.catalog_schema_version);
                try std.testing.expectEqualStrings("gics_sector", std.mem.sliceTo(&p.taxonomy_id, 0));
                try std.testing.expectEqual(@as(u32, 2025), p.taxonomy_version);
                try std.testing.expectEqualStrings("materials", std.mem.sliceTo(&p.classification_code, 0)); },
            else => unreachable,
        }
    }
}

test "binary round-trip and hash consistency" { for (makeFixtures()) |event| {
        try std.testing.expectEqual(codec.computeRecordHash(event), event.header.record_hash);

        var binary_buf: [codec.max_binary_len]u8 = undefined;
        const binary = try codec.formatBinary(&binary_buf, event);
        try std.testing.expectEqual(binary.len, try codec.peekBinaryLen(binary));

        const parsed_binary = try codec.parseBinary(binary);
        try std.testing.expectEqual(binary.len, parsed_binary.consumed_len);
        try std.testing.expect(codec.auditEventsEql(event, parsed_binary.event)); }
}

test "parseBinary rejects future schema version" { const event = makeFixtures()[0];
    var binary_buf: [codec.max_binary_len]u8 = undefined;
    const binary = try codec.formatBinary(&binary_buf, event);
    binary[@sizeOf(u32) + 1] = schema.audit_schema_version + 1;
    try std.testing.expectError(error.UnknownSchemaVersion, codec.parseBinary(binary)); }

test "parseBinary rejects truncated record" { const event = makeFixtures()[0];
    var binary_buf: [codec.max_binary_len]u8 = undefined;
    const binary = try codec.formatBinary(&binary_buf, event);
    try std.testing.expectError(error.UnexpectedEof, codec.parseBinary(binary[0 .. binary.len - 1])); }

test "parseBinary rejects unknown policy outcome enum" { const event = makeFixtures()[2];
    var binary_buf: [codec.max_binary_len]u8 = undefined;
    var binary = try codec.formatBinary(&binary_buf, event);
    const outcome_idx = try findPolicyDecisionOutcome(binary, 2);
    binary[outcome_idx] = 7;
    try std.testing.expectError(error.UnknownEnumValue, codec.parseBinary(binary)); }

test "parseBinary rejects oversized policy outcome varint" { const event = makeFixtures()[2];
    var binary_buf: [codec.max_binary_len]u8 = undefined;
    const binary = try codec.formatBinary(&binary_buf, event);
    var mutated_buf: [codec.max_binary_len + 1]u8 = undefined;
    const mutated = try expandPolicyDecisionOutcomeVarint(binary, &mutated_buf);
    try std.testing.expectError(error.InvalidBinaryRecord, codec.parseBinary(mutated)); }

fn findPolicyDecisionOutcome(binary: []const u8, expected: u8) !usize { var idx: usize = @sizeOf(u32);
    while (idx + 8 < binary.len) : (idx += 1) {
        if (binary[idx] == 0x72 and
            binary[idx + 1] == 0x9D and
            binary[idx + 2] == 0x80 and
            binary[idx + 3] == 0x80 and
            binary[idx + 4] == 0x80 and
            binary[idx + 5] == 0x00 and
            binary[idx + 6] == 0x08 and
            binary[idx + 7] == expected and
            binary[idx + 8] == 0x10)
        {
            return idx + 7; }
    }
    return error.PatternNotFound;
}

fn expandPolicyDecisionOutcomeVarint(binary: []const u8, out: []u8) ![]u8 { if (out.len < binary.len + 1) return error.NoSpaceLeft;
    const outcome_idx = try findPolicyDecisionOutcome(binary, 2);
    const payload_tag_idx = outcome_idx - 7;

    @memcpy(out[0..outcome_idx], binary[0..outcome_idx]);
    out[outcome_idx] = 0x80;
    out[outcome_idx + 1] = 0x02;
    @memcpy(out[outcome_idx + 2 .. binary.len + 1], binary[outcome_idx + 1 ..]);

    out[payload_tag_idx + 1] = binary[payload_tag_idx + 1] + 1;
    const body_len = std.mem.readInt(u32, binary[0..@sizeOf(u32)], .little);
    std.mem.writeInt(u32, out[0..@sizeOf(u32)], body_len + 1, .little);
    return out[0 .. binary.len + 1]; }

/// Generates the Zig fixture source file with pinned hashes and binary bytes.
/// Run with: just gen-audit-fixtures
/// Use the output to snapshot the current encoding after intentional changes.
fn writeFixtureFile() !void {
    const path = "src/tickoni/test/fixtures/fixture_audit_gen.zig";
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    try file.writeAll(
        \\\ // Auto-generated by `just gen-audit-fixtures`. Do not edit manually.
        \\\pub const Fixture = struct {
        \\\    expected_hash: u64,
        \\\    expected_binary_len: usize,
        \\\    expected_binary_bytes: []const u8,
        \\\};
        \\\
        \\\pub const values = [12]Fixture{
        \\\
    );

    var buf: [512]u8 = undefined;
    for (makeFixtures()) |event| {
        var binary_buf: [codec.max_binary_len]u8 = undefined;
        const binary = try codec.formatBinary(&binary_buf, event);
        try file.writeAll(try std.fmt.bufPrint(
            &buf,
            "    .{{ .expected_hash = {d}, .expected_binary_len = {d}, .expected_binary_bytes = &.{{",
            .{ event.header.record_hash, binary.len },
        ));
        for (binary, 0..) |b, j| {
            const sep: []const u8 = if (j > 0) ", " else "";
            try file.writeAll(try std.fmt.bufPrint(&buf, "{s}0x{X:0>2}", .{ sep, b }));
        }
        try file.writeAll("} },\n");
    }

    try file.writeAll("};\n");
    std.debug.print("wrote {s}\n", .{path});
}

test "gen audit fixture values" {
    const env = std.process.Environ{ .block = .{ .slice = getEnvSlice() } };
    if (std.process.getPosix(env, "TK_GEN_FIXTURES") == null) return error.SkipZigTest;
    try writeFixtureFile();
}
