const std = @import("std");
const audit = @import("audit_tile");
const basket = @import("basket");
const drift = @import("drift");
const model = @import("model");
const portfolio = @import("portfolio");
const replay = @import("replay");
const thesis = @import("thesis");
const trade_ticket = @import("trade_ticket");

pub const allowed_trade_event_count: usize = 15;
pub const oversized_trade_blocked_event_count: usize = 12;
pub const restricted_instrument_blocked_event_count: usize = 7;

pub const AllowedTradeAuditChain = struct {
    events: [allowed_trade_event_count]audit.AuditEvent,

    pub fn slice(self: *const AllowedTradeAuditChain) []const audit.AuditEvent {
        return &self.events;
    }
};

pub const OversizedTradeBlockedAuditChain = struct {
    events: [oversized_trade_blocked_event_count]audit.AuditEvent,

    pub fn slice(self: *const OversizedTradeBlockedAuditChain) []const audit.AuditEvent {
        return &self.events;
    }
};

pub const RestrictedInstrumentBlockedAuditChain = struct {
    events: [restricted_instrument_blocked_event_count]audit.AuditEvent,

    pub fn slice(self: *const RestrictedInstrumentBlockedAuditChain) []const audit.AuditEvent {
        return &self.events;
    }
};

const policy_version = "tickoni.v1";
const source_system = "tkapi";
const source_event_type = "investment_intent";
const canonical_event_type = "investment.intent";
const model_backend_id = "fixture.ai_infra";
const proposal_type = "trading_order.propose";
const rebalance_proposal_type = "trading_rebalance.propose";
const payment_update_proposal_type = "payment_retry.propose";
const replay_capsule_id = "replay_capsule_ai_infra";

fn parseFixedAsciiBytes(comptime N: usize, value: []const u8) [N]u8 {
    if (value.len > N) @panic("fixed ASCII field too long");
    var out = std.mem.zeroes([N]u8);
    for (value, 0..) |byte, idx| {
        if (byte < 0x20 or byte > 0x7e) @panic("non-ASCII byte in fixed field");
        out[idx] = byte;
    }
    return out;
}

// Quote/affordability/ticket/paper-result hashing reuses replay's canonical
// helpers (src/tickoni/tiles/replay/mod.zig) instead of reimplementing the
// same field-by-field Wyhash mixing here, so demo audit traces and replay
// checks can never silently diverge on what a proposal/result hash covers.
const hashBytes = replay.hashBytes;
const hashQuoteSnapshot = replay.hashQuoteSnapshot;
const hashAffordability = replay.hashAffordability;
const hashTicket = replay.hashTicket;
const hashPaperResult = replay.hashPaperResult;

fn capabilityEnvelopeId(thesis_input: *const thesis.ThesisInput, proposed_basket: *const basket.Basket) u128 {
    return (@as(u128, thesis.computeThesisInputHash(thesis_input.*)) << 64) | @as(u128, proposed_basket.basket_id);
}

fn header(
    seq: u64,
    tile_id: []const u8,
    logical_actor_id: u64,
    capability_envelope_id: u128,
    run_id: u64,
    prev_hash: u64,
) audit.Header {
    var hdr = std.mem.zeroes(audit.Header);
    hdr.schema_version = audit.audit_schema_version;
    hdr.run_id = run_id;
    hdr.seq = seq;
    hdr.source_offset = seq + 1;
    hdr.tile_id = parseFixedAsciiBytes(6, tile_id);
    hdr.logical_actor_id = logical_actor_id;
    hdr.policy_version = parseFixedAsciiBytes(32, policy_version);
    hdr.capability_envelope_id = capability_envelope_id;
    hdr.timestamp_ns = 0;
    hdr.prev_hash = prev_hash;
    hdr.record_hash = 0;
    return hdr;
}

pub fn buildAllowedTradeChain(
    run_id: u64,
    actor_role: []const u8,
    workflow: []const u8,
    thesis_input: *const thesis.ThesisInput,
    proposed_basket: *const basket.Basket,
    quote_snapshot: *const trade_ticket.QuoteSnapshot,
    affordability: portfolio.AffordabilityResult,
    model_response: *const model.ModelResponse,
    ticket: *const trade_ticket.TradeTicket,
    paper_result: *const trade_ticket.PaperExecutionResult,
    drift_contract: *const drift.DriftContract,
    replay_result: *const replay.ReplayVerification,
) AllowedTradeAuditChain {
    const raw_hash = thesis.computeThesisInputHash(thesis_input.*);
    const normalized_hash = proposed_basket.basket_id;
    const model_response_hash = hashBytes(model_response.content);
    const capability_id = capabilityEnvelopeId(thesis_input, proposed_basket);
    const quote_response_hash = hashQuoteSnapshot(quote_snapshot);
    const proposal_hash = hashTicket(ticket);
    const paper_response_hash = hashPaperResult(paper_result);
    const rebalance_hash = drift.hashRebalanceSuggestion(&drift_contract.rebalance_suggestion);
    const payment_update_hash = drift.hashPaymentProposalUpdate(&drift_contract.payment_proposal_update);

    var events: [allowed_trade_event_count]audit.AuditEvent = undefined;
    var prev_hash: u64 = 0;

    events[0] = audit.buildEvent(header(0, "tkings", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .source_event = .{
            .source_system = parseFixedAsciiBytes(16, source_system),
            .event_type = parseFixedAsciiBytes(32, source_event_type),
            .raw_hash = raw_hash,
        },
    });
    prev_hash = events[0].header.record_hash;

    events[1] = audit.buildEvent(header(1, "tknorm", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .normalization = .{
            .source_event_hash = raw_hash,
            .normalized_hash = normalized_hash,
            .canonical_event_type = parseFixedAsciiBytes(32, canonical_event_type),
        },
    });
    prev_hash = events[1].header.record_hash;

    events[2] = audit.buildEvent(header(2, "tkdedu", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .deduplication = .{
            .idempotency_key = raw_hash,
            .is_duplicate = false,
        },
    });
    prev_hash = events[2].header.record_hash;

    events[3] = audit.buildEvent(header(3, "tkcase", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .case_creation = .{
            .basket_id = proposed_basket.basket_id,
            .instrument_count = proposed_basket.instrument_count,
            .rejected_count = proposed_basket.rejected_count,
            .total_allocated_cents = proposed_basket.total_allocated_cents,
        },
    });
    prev_hash = events[3].header.record_hash;

    events[4] = audit.buildEvent(header(4, "tkpoly", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .policy_decision = .{
            .outcome = if (ticket.policy_outcome == .allow) .allow else .deny,
            .rule_id = 1101,
            .failed_scope_dim = parseFixedAsciiBytes(32, if (ticket.policy_outcome == .allow) "" else "per_order_notional"),
            .source_event_hash = normalized_hash,
            .catalog_schema_version = proposed_basket.catalog_schema_version,
            .taxonomy_id = std.mem.zeroes([32]u8),
            .taxonomy_version = 0,
            .classification_code = std.mem.zeroes([32]u8),
        },
    });
    prev_hash = events[4].header.record_hash;

    events[5] = audit.buildEvent(header(5, "tkmodl", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .model_call = .{
            .model_id = parseFixedAsciiBytes(32, model_backend_id),
            .prompt_hash = raw_hash,
            .response_hash = model_response_hash,
            .token_estimate = model_response.token_usage.total_tokens,
            .retry_count = 0,
            .actor_role = parseFixedAsciiBytes(16, actor_role),
            .workflow = parseFixedAsciiBytes(16, workflow),
            .policy_decision_id = 0,
            .replay_substitution_id = 0,
        },
    });
    prev_hash = events[5].header.record_hash;

    events[6] = audit.buildEvent(header(6, "tkadpt", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .financial_adapter_call = .{
            .adapter_id = parseFixedAsciiBytes(16, "portfolio"),
            .request_hash = hashBytes("portfolio.read"),
            .response_hash = hashAffordability(affordability),
            .replay_substitution_id = 1,
        },
    });
    prev_hash = events[6].header.record_hash;

    events[7] = audit.buildEvent(header(7, "tkadpt", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .financial_adapter_call = .{
            .adapter_id = parseFixedAsciiBytes(16, "quotes"),
            .request_hash = normalized_hash,
            .response_hash = quote_response_hash,
            .replay_substitution_id = 2,
        },
    });
    prev_hash = events[7].header.record_hash;

    events[8] = audit.buildEvent(header(8, "tkagnt", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .proposal = .{
            .proposal_type = parseFixedAsciiBytes(32, proposal_type),
            .proposal_hash = proposal_hash,
            .approval_state = 0,
        },
    });
    prev_hash = events[8].header.record_hash;

    events[9] = audit.buildEvent(header(9, "tkadpt", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .financial_adapter_call = .{
            .adapter_id = parseFixedAsciiBytes(16, "paper_fill"),
            .request_hash = proposal_hash,
            .response_hash = paper_response_hash,
            .replay_substitution_id = 3,
        },
    });
    prev_hash = events[9].header.record_hash;

    events[10] = audit.buildEvent(header(10, "tkpoly", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .policy_decision = .{
            .outcome = if (drift_contract.payment_proposal_update.requires_user_action) .require_approval else .allow,
            .rule_id = 1303,
            .failed_scope_dim = parseFixedAsciiBytes(32, firstPaymentScopeDim(&drift_contract.payment_drift)),
            .source_event_hash = payment_update_hash,
            .catalog_schema_version = 0,
            .taxonomy_id = std.mem.zeroes([32]u8),
            .taxonomy_version = 0,
            .classification_code = std.mem.zeroes([32]u8),
        },
    });
    prev_hash = events[10].header.record_hash;

    events[11] = audit.buildEvent(header(11, "tkagnt", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .proposal = .{
            .proposal_type = parseFixedAsciiBytes(32, rebalance_proposal_type),
            .proposal_hash = rebalance_hash,
            .approval_state = 0,
        },
    });
    prev_hash = events[11].header.record_hash;

    events[12] = audit.buildEvent(header(12, "tkpoly", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .approval_required = .{
            .action_class = parseFixedAsciiBytes(32, drift_contract.payment_proposal_update.actionClassSlice()),
            .approval_path = parseFixedAsciiBytes(32, drift_contract.payment_proposal_update.approvalPathSlice()),
            .proposal_hash = payment_update_hash,
        },
    });
    prev_hash = events[12].header.record_hash;

    events[13] = audit.buildEvent(header(13, "tkagnt", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .proposal = .{
            .proposal_type = parseFixedAsciiBytes(32, payment_update_proposal_type),
            .proposal_hash = payment_update_hash,
            .approval_state = @intFromEnum(drift_contract.payment_proposal_update.approval_state),
        },
    });
    prev_hash = events[13].header.record_hash;

    events[14] = audit.buildEvent(header(14, "tkrepl", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .replay_result = .{
            .capsule_id = hashBytes(replay_capsule_id),
            .divergences = replay_result.divergence_count,
            .first_divergent_seq = replay_result.first_divergent_seq,
        },
    });

    return .{ .events = events };
}

fn firstPaymentScopeDim(result: *const drift.PaymentDriftResult) []const u8 {
    if (result.condition_count == 0) return "";
    return result.active_conditions[0].label();
}

pub fn buildOversizedTradeBlockedChain(
    run_id: u64,
    actor_role: []const u8,
    workflow: []const u8,
    thesis_input: *const thesis.ThesisInput,
    proposed_basket: *const basket.Basket,
    quote_snapshot: *const trade_ticket.QuoteSnapshot,
    affordability: portfolio.AffordabilityResult,
    model_response: *const model.ModelResponse,
    ticket: *const trade_ticket.TradeTicket,
    replay_result: *const replay.ReplayVerification,
) OversizedTradeBlockedAuditChain {
    const raw_hash = thesis.computeThesisInputHash(thesis_input.*);
    const normalized_hash = proposed_basket.basket_id;
    const model_response_hash = hashBytes(model_response.content);
    const capability_id = capabilityEnvelopeId(thesis_input, proposed_basket);
    const quote_response_hash = hashQuoteSnapshot(quote_snapshot);
    const proposal_hash = hashTicket(ticket);
    const blocked_reason = ticket.blocked_reasons[0];

    var events: [oversized_trade_blocked_event_count]audit.AuditEvent = undefined;
    var prev_hash: u64 = 0;

    events[0] = audit.buildEvent(header(0, "tkings", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .source_event = .{
            .source_system = parseFixedAsciiBytes(16, source_system),
            .event_type = parseFixedAsciiBytes(32, source_event_type),
            .raw_hash = raw_hash,
        },
    });
    prev_hash = events[0].header.record_hash;

    events[1] = audit.buildEvent(header(1, "tknorm", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .normalization = .{
            .source_event_hash = raw_hash,
            .normalized_hash = normalized_hash,
            .canonical_event_type = parseFixedAsciiBytes(32, canonical_event_type),
        },
    });
    prev_hash = events[1].header.record_hash;

    events[2] = audit.buildEvent(header(2, "tkdedu", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .deduplication = .{
            .idempotency_key = raw_hash,
            .is_duplicate = false,
        },
    });
    prev_hash = events[2].header.record_hash;

    events[3] = audit.buildEvent(header(3, "tkcase", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .case_creation = .{
            .basket_id = proposed_basket.basket_id,
            .instrument_count = proposed_basket.instrument_count,
            .rejected_count = proposed_basket.rejected_count,
            .total_allocated_cents = proposed_basket.total_allocated_cents,
        },
    });
    prev_hash = events[3].header.record_hash;

    events[4] = audit.buildEvent(header(4, "tkpoly", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .policy_decision = .{
            .outcome = .deny,
            .rule_id = 1101,
            .failed_scope_dim = parseFixedAsciiBytes(32, blocked_reason.failed_scope_dim.label()),
            .source_event_hash = normalized_hash,
            .catalog_schema_version = proposed_basket.catalog_schema_version,
            .taxonomy_id = std.mem.zeroes([32]u8),
            .taxonomy_version = 0,
            .classification_code = std.mem.zeroes([32]u8),
        },
    });
    prev_hash = events[4].header.record_hash;

    events[5] = audit.buildEvent(header(5, "tkmodl", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .model_call = .{
            .model_id = parseFixedAsciiBytes(32, model_backend_id),
            .prompt_hash = raw_hash,
            .response_hash = model_response_hash,
            .token_estimate = model_response.token_usage.total_tokens,
            .retry_count = 0,
            .actor_role = parseFixedAsciiBytes(16, actor_role),
            .workflow = parseFixedAsciiBytes(16, workflow),
            .policy_decision_id = 0,
            .replay_substitution_id = 0,
        },
    });
    prev_hash = events[5].header.record_hash;

    events[6] = audit.buildEvent(header(6, "tkadpt", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .financial_adapter_call = .{
            .adapter_id = parseFixedAsciiBytes(16, "portfolio"),
            .request_hash = hashBytes("portfolio.read"),
            .response_hash = hashAffordability(affordability),
            .replay_substitution_id = 1,
        },
    });
    prev_hash = events[6].header.record_hash;

    events[7] = audit.buildEvent(header(7, "tkadpt", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .financial_adapter_call = .{
            .adapter_id = parseFixedAsciiBytes(16, "quotes"),
            .request_hash = normalized_hash,
            .response_hash = quote_response_hash,
            .replay_substitution_id = 2,
        },
    });
    prev_hash = events[7].header.record_hash;

    events[8] = audit.buildEvent(header(8, "tkagnt", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .proposal = .{
            .proposal_type = parseFixedAsciiBytes(32, proposal_type),
            .proposal_hash = proposal_hash,
            .approval_state = 0,
        },
    });
    prev_hash = events[8].header.record_hash;

    events[9] = audit.buildEvent(header(9, "tkpoly", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .limit_check = .{
            .limit_type = .amount,
            .value = blocked_reason.requested_cents,
            .limit = blocked_reason.limit_cents,
            .outcome = .deny,
        },
    });
    prev_hash = events[9].header.record_hash;

    events[10] = audit.buildEvent(header(10, "tkpoly", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .denial = .{
            .action_class = parseFixedAsciiBytes(32, "trading_order.place"),
            .reason_code = @intFromEnum(blocked_reason.code),
            .failed_scope_dim = parseFixedAsciiBytes(32, blocked_reason.failed_scope_dim.label()),
            .catalog_schema_version = proposed_basket.catalog_schema_version,
            .taxonomy_id = std.mem.zeroes([32]u8),
            .taxonomy_version = 0,
            .classification_code = std.mem.zeroes([32]u8),
        },
    });
    prev_hash = events[10].header.record_hash;

    events[11] = audit.buildEvent(header(11, "tkrepl", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .replay_result = .{
            .capsule_id = hashBytes("replay_capsule_ai_infra_oversized_25000"),
            .divergences = replay_result.divergence_count,
            .first_divergent_seq = replay_result.first_divergent_seq,
        },
    });

    return .{ .events = events };
}

pub fn buildRestrictedInstrumentBlockedChain(
    run_id: u64,
    actor_role: []const u8,
    workflow: []const u8,
    thesis_input: *const thesis.ThesisInput,
    proposed_basket: *const basket.Basket,
    replay_result: *const replay.ReplayVerification,
) RestrictedInstrumentBlockedAuditChain {
    const raw_hash = thesis.computeThesisInputHash(thesis_input.*);
    const normalized_hash = proposed_basket.basket_id;
    const capability_id = capabilityEnvelopeId(thesis_input, proposed_basket);

    var events: [restricted_instrument_blocked_event_count]audit.AuditEvent = undefined;
    var prev_hash: u64 = 0;

    events[0] = audit.buildEvent(header(0, "tkings", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .source_event = .{
            .source_system = parseFixedAsciiBytes(16, source_system),
            .event_type = parseFixedAsciiBytes(32, source_event_type),
            .raw_hash = raw_hash,
        },
    });
    prev_hash = events[0].header.record_hash;

    events[1] = audit.buildEvent(header(1, "tknorm", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .normalization = .{
            .source_event_hash = raw_hash,
            .normalized_hash = normalized_hash,
            .canonical_event_type = parseFixedAsciiBytes(32, canonical_event_type),
        },
    });
    prev_hash = events[1].header.record_hash;

    events[2] = audit.buildEvent(header(2, "tkdedu", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .deduplication = .{
            .idempotency_key = raw_hash,
            .is_duplicate = false,
        },
    });
    prev_hash = events[2].header.record_hash;

    events[3] = audit.buildEvent(header(3, "tkcase", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .case_creation = .{
            .basket_id = proposed_basket.basket_id,
            .instrument_count = proposed_basket.instrument_count,
            .rejected_count = proposed_basket.rejected_count,
            .total_allocated_cents = proposed_basket.total_allocated_cents,
        },
    });
    prev_hash = events[3].header.record_hash;

    events[4] = audit.buildEvent(header(4, "tkpoly", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .policy_decision = .{
            .outcome = .deny,
            .rule_id = 1101,
            .failed_scope_dim = parseFixedAsciiBytes(32, "restricted_instrument"),
            .source_event_hash = normalized_hash,
            .catalog_schema_version = proposed_basket.catalog_schema_version,
            .taxonomy_id = std.mem.zeroes([32]u8),
            .taxonomy_version = 0,
            .classification_code = std.mem.zeroes([32]u8),
        },
    });
    prev_hash = events[4].header.record_hash;

    _ = actor_role;
    _ = workflow;

    events[5] = audit.buildEvent(header(5, "tkpoly", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .denial = .{
            .action_class = parseFixedAsciiBytes(32, proposal_type),
            .reason_code = @intFromEnum(basket.RejectionReason.restricted_instrument),
            .failed_scope_dim = parseFixedAsciiBytes(32, "restricted_instrument"),
            .catalog_schema_version = proposed_basket.catalog_schema_version,
            .taxonomy_id = std.mem.zeroes([32]u8),
            .taxonomy_version = 0,
            .classification_code = std.mem.zeroes([32]u8),
        },
    });
    prev_hash = events[5].header.record_hash;

    events[6] = audit.buildEvent(header(6, "tkrepl", thesis_input.account_id, capability_id, run_id, prev_hash), .{
        .replay_result = .{
            .capsule_id = hashBytes("replay_capsule_ai_infra_restricted_soxl"),
            .divergences = replay_result.divergence_count,
            .first_divergent_seq = replay_result.first_divergent_seq,
        },
    });

    return .{ .events = events };
}
