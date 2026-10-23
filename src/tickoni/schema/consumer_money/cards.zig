/// V1.3.S2 Thesis and Money Proposal Cards
///
/// This module defines bounded card schemas, fail-closed builders, a small
/// deterministic store used by the current fixture/runtime path, and a JSON
/// export contract that a UI can render directly.
const std = @import("std");
const basket_mod = @import("basket");
const impact_mod = @import("impact");

// Re-export impact types so card consumers do not import impact separately.
pub const PaymentRail = impact_mod.PaymentRail;
pub const ApprovalState = impact_mod.ApprovalState;

pub const cards_schema_version: u16 = 1;

// ---------------------------------------------------------------------------
// Capacity constants
// ---------------------------------------------------------------------------

/// Maximum linked positions in one ThesisCard (bounded by basket max).
pub const max_linked_positions: usize = basket_mod.max_basket_instruments;
/// Maximum bytes in user_text stored in a ThesisCard.
pub const max_user_text_len: usize = 512;
/// Maximum bytes in the source_event field of a MoneyProposalCard.
pub const max_source_event_len: usize = 64;
/// Maximum bytes in the beneficiary field of a MoneyProposalCard.
pub const max_beneficiary_len: usize = 128;
/// Currency code slot: three-letter ISO code zero-padded to 4 bytes.
pub const currency_len: usize = 4;
pub const bp_denom: u32 = 10_000;

pub const BuildThesisCardError = error{
    ZeroThesisId,
    ZeroBasketId,
    BasketThesisIdMismatch,
    EmptyUserText,
    UserTextTooLong,
    EmptyLinkedPositions,
    TooManyLinkedPositions,
    InvalidTargetExposure,
    InvalidCurrentExposure,
    MissingEvidenceHash,
    InvalidTimestamp,
    InvalidUserText,
};

pub const BuildMoneyProposalCardError = error{
    ZeroProposalId,
    EmptySourceEvent,
    SourceEventTooLong,
    EmptyBeneficiary,
    BeneficiaryTooLong,
    InvalidSourceEvent,
    InvalidBeneficiary,
    InvalidCurrencyCode,
    NonPositiveAmount,
    MissingEvidenceHash,
    InvalidTimestamp,
    ExpiredProposal,
};

pub const DecisionCardsStoreError = error{
    MissingThesisCard,
    MissingMoneyProposalCard,
};

// ---------------------------------------------------------------------------
// ThesisCard (T1)
// ---------------------------------------------------------------------------

/// Health status of a thesis card.
pub const ThesisCardStatus = enum(u8) {
    /// Thesis is active and within bounds at last check.
    active,
    /// At least one drift condition was detected at last check.
    drifted,
    /// Thesis was manually closed or superseded.
    closed,

    pub fn label(self: ThesisCardStatus) []const u8 {
        return switch (self) {
            .active => "active",
            .drifted => "drifted",
            .closed => "closed",
        };
    }
};

/// One position linked to a thesis card, carrying rationale and evidence (T5).
pub const LinkedPosition = struct {
    ticker: [basket_mod.catalog.max_ticker_len]u8,
    ticker_len: u8,
    /// Rationale text copied from the basket instrument at card creation (T5).
    rationale: [basket_mod.max_rationale_len]u8,
    rationale_len: u8,
    /// Content-addressed hash of the evidence packet backing the rationale.
    evidence_hash: u64,
    allocation_cents: i64,

    pub fn tickerSlice(self: *const LinkedPosition) []const u8 {
        return self.ticker[0..self.ticker_len];
    }

    pub fn rationaleSlice(self: *const LinkedPosition) []const u8 {
        return self.rationale[0..self.rationale_len];
    }
};

/// Persisted record for an investment thesis after paper execution (T1).
pub const ThesisCard = struct {
    /// Content hash of the source ThesisInput (computeThesisInputHash()).
    thesis_id: u64,
    user_text: [max_user_text_len]u8,
    user_text_len: u16,
    /// Content hash of the basket produced from the thesis.
    basket_id: u64,
    /// Positions included in the basket, with rationale and evidence (T5).
    linked_positions: [max_linked_positions]LinkedPosition,
    linked_position_count: u8,
    /// Intended exposure in basis points from the proposed basket.
    target_exposure_bp: u32,
    /// Realized/current exposure in basis points at card creation.
    current_exposure_bp: u32,
    status: ThesisCardStatus,
    /// Nanosecond epoch timestamp of card creation.
    created_at_ns: u64,
    /// Nanosecond epoch timestamp of last drift check.
    last_checked_at_ns: u64,

    pub fn userTextSlice(self: *const ThesisCard) []const u8 {
        return self.user_text[0..self.user_text_len];
    }
};

// ---------------------------------------------------------------------------
// MoneyProposalCard (T2)
// ---------------------------------------------------------------------------

/// Lifecycle status of a money proposal card.
pub const MoneyProposalStatus = enum(u8) {
    /// Proposal is open and awaiting action or approval.
    pending,
    /// Proposal was approved and is ready for execution.
    approved,
    /// Proposal was rejected.
    rejected,
    /// Proposal approval window has expired.
    expired,
    /// Proposal was executed (future tkexec path).
    executed,

    pub fn label(self: MoneyProposalStatus) []const u8 {
        return switch (self) {
            .pending => "pending",
            .approved => "approved",
            .rejected => "rejected",
            .expired => "expired",
            .executed => "executed",
        };
    }
};

/// Persisted record for a payment or transfer proposal (T2).
pub const MoneyProposalCard = struct {
    /// Stable proposal identifier matching the source PendingObligation.
    proposal_id: u64,
    /// Financial event that triggered this proposal (e.g. "payment_failed").
    source_event: [max_source_event_len]u8,
    source_event_len: u8,
    /// Human-readable beneficiary label or opaque identifier.
    beneficiary: [max_beneficiary_len]u8,
    beneficiary_len: u8,
    rail: PaymentRail,
    /// ISO 4217 currency code, zero-padded to currency_len bytes.
    currency: [currency_len]u8,
    amount_cents: i64,
    approval_state: ApprovalState,
    /// Nanosecond epoch expiry; nonzero in the current fixture flow.
    expires_at_ns: u64,
    /// Content-addressed hash of the evidence packet that justified this
    /// proposal. Links the card back to auditable rationale (T5).
    evidence_hash: u64,
    status: MoneyProposalStatus,
    created_at_ns: u64,

    pub fn sourceEventSlice(self: *const MoneyProposalCard) []const u8 {
        return self.source_event[0..self.source_event_len];
    }

    pub fn beneficiarySlice(self: *const MoneyProposalCard) []const u8 {
        return self.beneficiary[0..self.beneficiary_len];
    }

    pub fn currencySlice(self: *const MoneyProposalCard) []const u8 {
        var end: usize = currency_len;
        while (end > 0 and self.currency[end - 1] == 0) end -= 1;
        return self.currency[0..end];
    }
};

// ---------------------------------------------------------------------------
// Store and JSON contract
// ---------------------------------------------------------------------------

pub const DecisionCardsContract = struct {
    schema_version: u16 = cards_schema_version,
    thesis_card: ThesisCard,
    money_proposal_card: MoneyProposalCard,
};

/// Minimal deterministic saved-card store for the current fixture/runtime path.
pub const DecisionCardsStore = struct {
    thesis_card: ?ThesisCard = null,
    money_proposal_card: ?MoneyProposalCard = null,

    pub fn saveThesisCard(self: *DecisionCardsStore, card: ThesisCard) void {
        self.thesis_card = card;
    }

    pub fn saveMoneyProposalCard(self: *DecisionCardsStore, card: MoneyProposalCard) void {
        self.money_proposal_card = card;
    }

    pub fn snapshot(self: *const DecisionCardsStore) DecisionCardsStoreError!DecisionCardsContract {
        const thesis_card = self.thesis_card orelse return error.MissingThesisCard;
        const money_proposal_card = self.money_proposal_card orelse return error.MissingMoneyProposalCard;
        return .{
            .thesis_card = thesis_card,
            .money_proposal_card = money_proposal_card,
        };
    }
};

pub fn allocDecisionCardsJson(
    allocator: std.mem.Allocator,
    contract: *const DecisionCardsContract,
) ![]u8 {
    const LinkedPositionView = struct {
        ticker: []const u8,
        rationale: []const u8,
        evidence_hash: u64,
        allocation_cents: i64,
    };
    const ThesisCardView = struct {
        thesis_id: u64,
        user_text: []const u8,
        basket_id: u64,
        linked_positions: []const LinkedPositionView,
        target_exposure_bp: u32,
        current_exposure_bp: u32,
        status: []const u8,
        created_at_ns: u64,
        last_checked_at_ns: u64,
    };
    const MoneyProposalCardView = struct {
        proposal_id: u64,
        source_event: []const u8,
        beneficiary: []const u8,
        rail: []const u8,
        currency: []const u8,
        amount_cents: i64,
        approval_state: []const u8,
        expires_at_ns: u64,
        evidence_hash: u64,
        status: []const u8,
        created_at_ns: u64,
    };

    var linked_position_views: [max_linked_positions]LinkedPositionView = undefined;
    for (contract.thesis_card.linked_positions[0..contract.thesis_card.linked_position_count], 0..) |*position, i| {
        linked_position_views[i] = .{
            .ticker = position.tickerSlice(),
            .rationale = position.rationaleSlice(),
            .evidence_hash = position.evidence_hash,
            .allocation_cents = position.allocation_cents,
        };
    }

    return std.json.Stringify.valueAlloc(allocator, .{
        .schema_version = contract.schema_version,
        .thesis_card = ThesisCardView{
            .thesis_id = contract.thesis_card.thesis_id,
            .user_text = contract.thesis_card.userTextSlice(),
            .basket_id = contract.thesis_card.basket_id,
            .linked_positions = linked_position_views[0..contract.thesis_card.linked_position_count],
            .target_exposure_bp = contract.thesis_card.target_exposure_bp,
            .current_exposure_bp = contract.thesis_card.current_exposure_bp,
            .status = contract.thesis_card.status.label(),
            .created_at_ns = contract.thesis_card.created_at_ns,
            .last_checked_at_ns = contract.thesis_card.last_checked_at_ns,
        },
        .money_proposal_card = MoneyProposalCardView{
            .proposal_id = contract.money_proposal_card.proposal_id,
            .source_event = contract.money_proposal_card.sourceEventSlice(),
            .beneficiary = contract.money_proposal_card.beneficiarySlice(),
            .rail = railLabel(contract.money_proposal_card.rail),
            .currency = contract.money_proposal_card.currencySlice(),
            .amount_cents = contract.money_proposal_card.amount_cents,
            .approval_state = approvalStateLabel(contract.money_proposal_card.approval_state),
            .expires_at_ns = contract.money_proposal_card.expires_at_ns,
            .evidence_hash = contract.money_proposal_card.evidence_hash,
            .status = contract.money_proposal_card.status.label(),
            .created_at_ns = contract.money_proposal_card.created_at_ns,
        },
    }, .{});
}

pub fn writeDecisionCardsJson(
    allocator: std.mem.Allocator,
    writer: anytype,
    contract: *const DecisionCardsContract,
) !void {
    const json = try allocDecisionCardsJson(allocator, contract);
    defer allocator.free(json);
    try writer.writeAll(json);
    try writer.writeAll("\n");
}

// ---------------------------------------------------------------------------
// Build functions (T3, T4)
// ---------------------------------------------------------------------------

/// Construct a ThesisCard after paper execution (T3).
pub fn buildThesisCard(
    thesis_id: u64,
    user_text: []const u8,
    basket: *const basket_mod.Basket,
    target_exposure_bp: u32,
    current_exposure_bp: u32,
    linked_position_evidence_hash: u64,
    now_ns: u64,
) BuildThesisCardError!ThesisCard {
    try validateThesisCardInputs(
        thesis_id,
        user_text,
        basket,
        target_exposure_bp,
        current_exposure_bp,
        linked_position_evidence_hash,
        now_ns,
    );

    var card = std.mem.zeroes(ThesisCard);
    card.thesis_id = thesis_id;
    card.basket_id = basket.basket_id;
    card.target_exposure_bp = target_exposure_bp;
    card.current_exposure_bp = current_exposure_bp;
    card.status = .active;
    card.created_at_ns = now_ns;
    card.last_checked_at_ns = now_ns;

    @memcpy(card.user_text[0..user_text.len], user_text);
    card.user_text_len = @intCast(user_text.len);

    for (basket.instruments[0..basket.instrument_count], 0..) |*instr, i| {
        var pos = std.mem.zeroes(LinkedPosition);

        const ticker_len = @as(usize, instr.ticker_len);
        @memcpy(pos.ticker[0..ticker_len], instr.ticker[0..ticker_len]);
        pos.ticker_len = instr.ticker_len;

        const rationale_len = @as(usize, instr.rationale_len);
        @memcpy(pos.rationale[0..rationale_len], instr.rationale[0..rationale_len]);
        pos.rationale_len = instr.rationale_len;

        pos.evidence_hash = linked_position_evidence_hash;
        pos.allocation_cents = instr.allocation_cents;
        card.linked_positions[i] = pos;
    }
    card.linked_position_count = basket.instrument_count;

    return card;
}

/// Construct a MoneyProposalCard after proposal generation (T4).
pub fn buildMoneyProposalCard(
    obligation: *const impact_mod.PendingObligation,
    source_event: []const u8,
    beneficiary: []const u8,
    currency: []const u8,
    evidence_hash: u64,
    now_ns: u64,
) BuildMoneyProposalCardError!MoneyProposalCard {
    try validateMoneyProposalCardInputs(
        obligation,
        source_event,
        beneficiary,
        currency,
        evidence_hash,
        now_ns,
    );

    var card = std.mem.zeroes(MoneyProposalCard);
    card.proposal_id = obligation.proposal_id;
    card.rail = obligation.rail;
    card.amount_cents = obligation.amount_cents;
    card.approval_state = obligation.approval_state;
    card.expires_at_ns = obligation.expires_at_ns;
    card.evidence_hash = evidence_hash;
    card.created_at_ns = now_ns;

    card.status = switch (obligation.approval_state) {
        .pending => .pending,
        .approved => .approved,
        .rejected => .rejected,
        .expired => .expired,
    };

    @memcpy(card.source_event[0..source_event.len], source_event);
    card.source_event_len = @intCast(source_event.len);

    @memcpy(card.beneficiary[0..beneficiary.len], beneficiary);
    card.beneficiary_len = @intCast(beneficiary.len);

    @memcpy(card.currency[0..currency.len], currency);
    return card;
}

// ---------------------------------------------------------------------------
// Validation helpers
// ---------------------------------------------------------------------------

fn validateThesisCardInputs(
    thesis_id: u64,
    user_text: []const u8,
    basket: *const basket_mod.Basket,
    target_exposure_bp: u32,
    current_exposure_bp: u32,
    linked_position_evidence_hash: u64,
    now_ns: u64,
) BuildThesisCardError!void {
    if (thesis_id == 0) return error.ZeroThesisId;
    if (basket.basket_id == 0) return error.ZeroBasketId;
    if (basket.thesis_id == 0 or basket.thesis_id != thesis_id) return error.BasketThesisIdMismatch;
    if (user_text.len == 0) return error.EmptyUserText;
    if (user_text.len > max_user_text_len) return error.UserTextTooLong;
    if (!isSafeText(user_text)) return error.InvalidUserText;
    if (basket.instrument_count == 0) return error.EmptyLinkedPositions;
    if (basket.instrument_count > max_linked_positions) return error.TooManyLinkedPositions;
    if (target_exposure_bp > bp_denom) return error.InvalidTargetExposure;
    if (current_exposure_bp > bp_denom) return error.InvalidCurrentExposure;
    if (linked_position_evidence_hash == 0) return error.MissingEvidenceHash;
    if (now_ns == 0) return error.InvalidTimestamp;
}

fn validateMoneyProposalCardInputs(
    obligation: *const impact_mod.PendingObligation,
    source_event: []const u8,
    beneficiary: []const u8,
    currency: []const u8,
    evidence_hash: u64,
    now_ns: u64,
) BuildMoneyProposalCardError!void {
    if (obligation.proposal_id == 0) return error.ZeroProposalId;
    if (source_event.len == 0) return error.EmptySourceEvent;
    if (source_event.len > max_source_event_len) return error.SourceEventTooLong;
    if (!isSafeIdentifier(source_event)) return error.InvalidSourceEvent;
    if (beneficiary.len == 0) return error.EmptyBeneficiary;
    if (beneficiary.len > max_beneficiary_len) return error.BeneficiaryTooLong;
    if (!isSafeText(beneficiary)) return error.InvalidBeneficiary;
    if (!isIsoCurrencyCode(currency)) return error.InvalidCurrencyCode;
    if (obligation.amount_cents <= 0) return error.NonPositiveAmount;
    if (evidence_hash == 0) return error.MissingEvidenceHash;
    if (now_ns == 0) return error.InvalidTimestamp;
    if (obligation.expires_at_ns != 0 and obligation.expires_at_ns <= now_ns) return error.ExpiredProposal;
}

fn isSafeText(value: []const u8) bool {
    for (value) |byte| {
        if (byte < 0x20 or byte == 0x7f) return false;
    }
    return true;
}

fn isSafeIdentifier(value: []const u8) bool {
    for (value) |byte| {
        const ok =
            std.ascii.isAlphanumeric(byte) or
            byte == '_' or
            byte == '.' or
            byte == '-' or
            byte == ':';
        if (!ok) return false;
    }
    return true;
}

fn isIsoCurrencyCode(value: []const u8) bool {
    if (value.len != 3) return false;
    for (value) |byte| {
        if (byte < 'A' or byte > 'Z') return false;
    }
    return true;
}

fn railLabel(rail: PaymentRail) []const u8 {
    return switch (rail) {
        .ach => "ach",
        .wire => "wire",
        .card => "card",
        .internal => "internal",
    };
}

fn approvalStateLabel(state: ApprovalState) []const u8 {
    return switch (state) {
        .pending => "pending",
        .approved => "approved",
        .rejected => "rejected",
        .expired => "expired",
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

fn makeMinimalBasket(basket_id: u64, thesis_id: u64) basket_mod.Basket {
    var b = std.mem.zeroes(basket_mod.Basket);
    b.basket_id = basket_id;
    b.thesis_id = thesis_id;
    b.account_id = 1001;
    b.target_notional_cents = 200_000;
    b.total_allocated_cents = 200_000;
    return b;
}

fn addInstrument(
    b: *basket_mod.Basket,
    comptime ticker: []const u8,
    comptime rationale: []const u8,
    allocation_cents: i64,
) void {
    const i = b.instrument_count;
    @memcpy(b.instruments[i].ticker[0..ticker.len], ticker);
    b.instruments[i].ticker_len = @intCast(ticker.len);
    @memcpy(b.instruments[i].rationale[0..rationale.len], rationale);
    b.instruments[i].rationale_len = @intCast(rationale.len);
    b.instruments[i].allocation_cents = allocation_cents;
    b.instruments[i].asset_class = .equity;
    b.instruments[i].instrument_type = .etf;
    b.instruments[i].weight_bp = 5000;
    b.instrument_count += 1;
}

fn makeObligation(
    proposal_id: u64,
    rail: PaymentRail,
    amount_cents: i64,
    approval_state: ApprovalState,
    expires_at_ns: u64,
) impact_mod.PendingObligation {
    return .{
        .proposal_id = proposal_id,
        .rail = rail,
        .destination_id = 42,
        .amount_cents = amount_cents,
        .approval_state = approval_state,
        .expires_at_ns = expires_at_ns,
    };
}

fn hashBytes(bytes: []const u8) u64 {
    return std.hash.Wyhash.hash(0, bytes);
}

test "buildThesisCard preserves ids and exposure fields" {
    var basket = makeMinimalBasket(0xABC, 0xDEF);
    addInstrument(&basket, "SOXX", "AI semiconductor ETF", 100_000);
    addInstrument(&basket, "NVDA", "GPU leader for AI workloads", 100_000);

    const evidence_hash = hashBytes("evidence.ai.thesis");
    const card = try buildThesisCard(
        0xDEF,
        "Buy AI infra",
        &basket,
        3_100,
        2_200,
        evidence_hash,
        1_000_000,
    );

    try testing.expectEqual(@as(u64, 0xDEF), card.thesis_id);
    try testing.expectEqual(@as(u64, 0xABC), card.basket_id);
    try testing.expectEqual(@as(u32, 3_100), card.target_exposure_bp);
    try testing.expectEqual(@as(u32, 2_200), card.current_exposure_bp);
}

test "buildThesisCard links ticker rationale and evidence" {
    var basket = makeMinimalBasket(10, 20);
    addInstrument(&basket, "SOXX", "AI semiconductor ETF for broad exposure", 100_000);
    addInstrument(&basket, "NVDA", "GPU leader enabling AI model training", 100_000);

    const evidence_hash = hashBytes("evidence.ai.positions");
    const card = try buildThesisCard(
        20,
        "AI infra thesis",
        &basket,
        2_200,
        2_100,
        evidence_hash,
        9_999_888_777,
    );

    try testing.expectEqual(@as(u8, 2), card.linked_position_count);
    try testing.expectEqualStrings("SOXX", card.linked_positions[0].tickerSlice());
    try testing.expectEqualStrings("AI semiconductor ETF for broad exposure", card.linked_positions[0].rationaleSlice());
    try testing.expectEqual(evidence_hash, card.linked_positions[0].evidence_hash);
    try testing.expectEqualStrings("NVDA", card.linked_positions[1].tickerSlice());
    try testing.expectEqual(evidence_hash, card.linked_positions[1].evidence_hash);
}

test "buildThesisCard rejects invalid inputs instead of truncating" {
    var basket = makeMinimalBasket(1, 2);
    addInstrument(&basket, "SOXX", "reason", 100_000);

    try testing.expectError(
        error.EmptyUserText,
        buildThesisCard(2, "", &basket, 1_000, 1_000, hashBytes("evidence"), 1),
    );

    var long_text: [max_user_text_len + 1]u8 = undefined;
    @memset(&long_text, 'x');
    try testing.expectError(
        error.UserTextTooLong,
        buildThesisCard(2, &long_text, &basket, 1_000, 1_000, hashBytes("evidence"), 1),
    );

    try testing.expectError(
        error.BasketThesisIdMismatch,
        buildThesisCard(3, "test", &basket, 1_000, 1_000, hashBytes("evidence"), 1),
    );
    try testing.expectError(
        error.MissingEvidenceHash,
        buildThesisCard(2, "test", &basket, 1_000, 1_000, 0, 1),
    );
    try testing.expectError(
        error.InvalidTimestamp,
        buildThesisCard(2, "test", &basket, 1_000, 1_000, hashBytes("evidence"), 0),
    );
}

test "buildMoneyProposalCard preserves proposal fields" {
    const expiry: u64 = 9_999_000_000;
    const now: u64 = 5_000_000_000;
    const ob = makeObligation(101, .ach, 124_000, .pending, expiry);
    const card = try buildMoneyProposalCard(
        &ob,
        "payment_failed",
        "supplier_acme_us",
        "USD",
        hashBytes("evidence.payment"),
        now,
    );

    try testing.expectEqual(@as(u64, 101), card.proposal_id);
    try testing.expectEqual(PaymentRail.ach, card.rail);
    try testing.expectEqual(@as(i64, 124_000), card.amount_cents);
    try testing.expectEqualStrings("payment_failed", card.sourceEventSlice());
    try testing.expectEqualStrings("supplier_acme_us", card.beneficiarySlice());
    try testing.expectEqualStrings("USD", card.currencySlice());
    try testing.expectEqual(MoneyProposalStatus.pending, card.status);
}

test "buildMoneyProposalCard rejects malformed financial inputs" {
    const now: u64 = 5_000_000_000;
    const expiry: u64 = now + 1_000;

    try testing.expectError(
        error.ZeroProposalId,
        buildMoneyProposalCard(
            &makeObligation(0, .ach, 124_000, .pending, expiry),
            "payment_failed",
            "supplier_acme_us",
            "USD",
            hashBytes("evidence"),
            now,
        ),
    );
    try testing.expectError(
        error.NonPositiveAmount,
        buildMoneyProposalCard(
            &makeObligation(1, .ach, 0, .pending, expiry),
            "payment_failed",
            "supplier_acme_us",
            "USD",
            hashBytes("evidence"),
            now,
        ),
    );
    try testing.expectError(
        error.InvalidCurrencyCode,
        buildMoneyProposalCard(
            &makeObligation(1, .ach, 124_000, .pending, expiry),
            "payment_failed",
            "supplier_acme_us",
            "US",
            hashBytes("evidence"),
            now,
        ),
    );
    try testing.expectError(
        error.MissingEvidenceHash,
        buildMoneyProposalCard(
            &makeObligation(1, .ach, 124_000, .pending, expiry),
            "payment_failed",
            "supplier_acme_us",
            "USD",
            0,
            now,
        ),
    );
    try testing.expectError(
        error.ExpiredProposal,
        buildMoneyProposalCard(
            &makeObligation(1, .ach, 124_000, .pending, now),
            "payment_failed",
            "supplier_acme_us",
            "USD",
            hashBytes("evidence"),
            now,
        ),
    );
}

test "decision cards store snapshots only after both cards are saved" {
    var store = DecisionCardsStore{};
    try testing.expectError(error.MissingThesisCard, store.snapshot());

    var basket = makeMinimalBasket(1, 2);
    addInstrument(&basket, "SOXX", "reason", 100_000);
    store.saveThesisCard(try buildThesisCard(
        2,
        "test",
        &basket,
        1_000,
        900,
        hashBytes("evidence.ai"),
        1,
    ));
    try testing.expectError(error.MissingMoneyProposalCard, store.snapshot());

    store.saveMoneyProposalCard(try buildMoneyProposalCard(
        &makeObligation(1, .ach, 124_000, .pending, 2),
        "payment_failed",
        "supplier_acme_us",
        "USD",
        hashBytes("evidence.money"),
        1,
    ));
    const snapshot = try store.snapshot();
    try testing.expectEqual(@as(u16, cards_schema_version), snapshot.schema_version);
}

test "allocDecisionCardsJson exposes a UI-renderable contract" {
    var store = DecisionCardsStore{};
    var basket = makeMinimalBasket(0xAA, 0xBB);
    addInstrument(&basket, "SOXX", "ETF rationale", 200_000);

    store.saveThesisCard(try buildThesisCard(
        0xBB,
        "Buy AI infra",
        &basket,
        1_500,
        1_250,
        hashBytes("evidence.positions"),
        10,
    ));
    store.saveMoneyProposalCard(try buildMoneyProposalCard(
        &makeObligation(404, .ach, 124_000, .pending, 100),
        "payment_failed",
        "supplier_acme_us",
        "USD",
        hashBytes("evidence.money"),
        10,
    ));

    const snapshot = try store.snapshot();
    const json = try allocDecisionCardsJson(testing.allocator, &snapshot);
    defer testing.allocator.free(json);

    const ContractWire = struct {
        schema_version: u16,
        thesis_card: struct {
            thesis_id: u64,
            user_text: []const u8,
            basket_id: u64,
            linked_positions: []const struct {
                ticker: []const u8,
                rationale: []const u8,
                evidence_hash: u64,
                allocation_cents: i64,
            },
            target_exposure_bp: u32,
            current_exposure_bp: u32,
            status: []const u8,
            created_at_ns: u64,
            last_checked_at_ns: u64,
        },
        money_proposal_card: struct {
            proposal_id: u64,
            source_event: []const u8,
            beneficiary: []const u8,
            rail: []const u8,
            currency: []const u8,
            amount_cents: i64,
            approval_state: []const u8,
            expires_at_ns: u64,
            evidence_hash: u64,
            status: []const u8,
            created_at_ns: u64,
        },
    };

    const parsed = try std.json.parseFromSlice(ContractWire, testing.allocator, json, .{});
    defer parsed.deinit();

    try testing.expectEqual(@as(u16, cards_schema_version), parsed.value.schema_version);
    try testing.expectEqualStrings("Buy AI infra", parsed.value.thesis_card.user_text);
    try testing.expectEqual(@as(usize, 1), parsed.value.thesis_card.linked_positions.len);
    try testing.expectEqualStrings("SOXX", parsed.value.thesis_card.linked_positions[0].ticker);
    try testing.expectEqualStrings("supplier_acme_us", parsed.value.money_proposal_card.beneficiary);
    try testing.expectEqualStrings("ach", parsed.value.money_proposal_card.rail);
    try testing.expectEqualStrings("pending", parsed.value.money_proposal_card.approval_state);
}
