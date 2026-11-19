/// Semantic tier of a configured tkmodl instance. A tier is an architectural
/// role, not a model id and not a link position: which actual models a tier
/// may run is `TkModlRuntimeConfig.allowed_model_ids`, and which process serves
/// a tier is the `(tkmodl, kind_id)` the topology maps it to.
///
/// One source of truth for the supported maximum (five classifier tiers, one
/// embedding tier, five LLM tiers) so topology validation, per-instance config
/// files, and the tkagnt route table all derive from the same list. See the
/// tkagnt fd_stem migration plan, "Multi-tkmodl fan-out design".
const std = @import("std");

pub const TkAgntModelTier = enum(u8) {
    classifier_fast,
    classifier_complex,
    classifier_escalation,
    classifier_hosted,
    classifier_hosted_newer,
    embedding,
    low,
    medium,
    high,
    @"extra-high",
    max,

    /// Number of supported tiers.
    pub const count: usize = @typeInfo(TkAgntModelTier).@"enum".field_names.len;

    pub fn name(self: TkAgntModelTier) []const u8 {
        return @tagName(self);
    }

    /// Fail-closed decode of a serialized tier. Null for any value outside the
    /// supported set.
    pub fn fromInt(v: u8) ?TkAgntModelTier {
        if (v >= count) return null;
        return @fromBackingInt(@intCast(v));
    }

    pub fn isClassifier(self: TkAgntModelTier) bool {
        return switch (self) {
            .classifier_fast, .classifier_complex, .classifier_escalation, .classifier_hosted, .classifier_hosted_newer => true,
            else => false,
        };
    }

    pub fn isEmbedding(self: TkAgntModelTier) bool {
        return self == .embedding;
    }

    pub fn isLlm(self: TkAgntModelTier) bool {
        return !self.isClassifier() and !self.isEmbedding();
    }
};

/// A workflow configures between 0 and this many tkmodl instances: one per
/// supported tier, never two for the same tier.
pub const max_model_instances: usize = TkAgntModelTier.count;

test "the supported maximum is 11 tiers: 5 classifier, 1 embedding, 5 LLM" {
    try std.testing.expectEqual(@as(usize, 11), TkAgntModelTier.count);
    try std.testing.expectEqual(@as(usize, 11), max_model_instances);

    var classifiers: usize = 0;
    var embeddings: usize = 0;
    var llms: usize = 0;
    for (0..TkAgntModelTier.count) |i| {
        const tier: TkAgntModelTier = @fromBackingInt(@intCast(i));
        if (tier.isClassifier()) classifiers += 1;
        if (tier.isEmbedding()) embeddings += 1;
        if (tier.isLlm()) llms += 1;
        // Every tier is exactly one of the three roles.
        try std.testing.expectEqual(@as(usize, 1), @as(usize, @intFromBool(tier.isClassifier())) + @intFromBool(tier.isEmbedding()) + @intFromBool(tier.isLlm()));
    }
    try std.testing.expectEqual(@as(usize, 5), classifiers);
    try std.testing.expectEqual(@as(usize, 1), embeddings);
    try std.testing.expectEqual(@as(usize, 5), llms);
}

test "tier names match the plan's vocabulary" {
    try std.testing.expectEqualStrings("classifier_fast", TkAgntModelTier.classifier_fast.name());
    try std.testing.expectEqualStrings("classifier_hosted_newer", TkAgntModelTier.classifier_hosted_newer.name());
    try std.testing.expectEqualStrings("embedding", TkAgntModelTier.embedding.name());
    try std.testing.expectEqualStrings("extra-high", TkAgntModelTier.@"extra-high".name());
    try std.testing.expectEqualStrings("max", TkAgntModelTier.max.name());
}

test "fromInt round-trips every tier and rejects out-of-range values" {
    for (0..TkAgntModelTier.count) |i| {
        const tier = TkAgntModelTier.fromInt(@intCast(i)) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(@as(u8, @intCast(i)), @backingInt(tier));
    }
    try std.testing.expectEqual(@as(?TkAgntModelTier, null), TkAgntModelTier.fromInt(TkAgntModelTier.count));
    try std.testing.expectEqual(@as(?TkAgntModelTier, null), TkAgntModelTier.fromInt(255));
}
