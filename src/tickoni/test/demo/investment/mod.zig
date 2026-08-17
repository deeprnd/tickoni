const std = @import("std");
const adapter = @import("adapter");
const basket_mod = @import("basket");
pub const cards = @import("cards");
pub const drift = @import("drift");
const impact = @import("impact");
const model = @import("model");
const portfolio = @import("portfolio");
const replay = @import("replay");
const thesis = @import("thesis");
const support = @import("investment_support");
const tkpoly = @import("tkpoly");
const tool = @import("tool");
const trade_ticket = @import("trade_ticket");

pub const default_endpoint = "http://127.0.0.1:8080/v1";
pub const default_model_id = "unsloth/gemma-4-E2B-it-qat-GGUF:UD-Q4_K_XL";

const system_prompt =
    "You are a structured financial research assistant. " ++
    "Summarize the thesis and recommend only US-listed large-cap equities and ETFs. " ++
    "Respond with JSON only using keys thesis_summary, recommended_tickers, and rationale. " ++
    "Do not recommend leveraged ETFs, inverse ETFs, options, futures, or crypto.";

const live_actor_role = "trading_ops_reviewer";
const live_workflow = "trading_control";
const live_capability = "trading_order.propose";
const live_capability_envelope_id = "capenv.trading_order.propose.demo";
const live_policy_version = "v1";
const live_budget_id = "budget.demo_paper.live";
const decision_cards_now_ns: u64 = 1_765_792_800_000_000_000;
const supplier_payout_proposal_id: u64 = 1_240_001;
const supplier_payout_amount_cents: i64 = 124_000;
const supplier_payout_beneficiary = "supplier_acme_us";
const supplier_payout_source_event = "payment_failed";
const supplier_payout_currency = "USD";
const supplier_payout_expires_at_ns: u64 = 1_765_879_200_000_000_000;
const demo_cash_buffer_threshold_cents: i64 = 500_000;
const drift_check_now_ns: u64 = supplier_payout_expires_at_ns + 1;
const drift_retry_window_expiry_ns: u64 = decision_cards_now_ns - 1;
const drift_evidence_expiry_ns: u64 = decision_cards_now_ns - 86_400_000_000_000;
const drift_market_exposure_bp: u32 = 1_800;
const drift_market_max_sector_bp: u32 = 6_000;
const drift_market_max_single_name_bp: u32 = 3_500;
const drift_market_buying_power_cents: i64 = 100_000;
const drift_payment_available_cash_cents: i64 = 300_000;
const drift_payment_daily_limit_cents: i64 = 100_000;
const drift_payment_monthly_limit_cents: i64 = 500_000;
const drift_rebalance_policy = drift.ThesisDriftPolicy{
    .allocation_breach_threshold_bp = 800,
    .max_sector_exposure_bp = 5_000,
    .max_single_name_bp = 3_000,
    .min_buying_power_to_rebalance_cents = 200_000,
};
const drift_payment_policy = drift.PaymentDriftPolicy{
    .cash_buffer_threshold_cents = demo_cash_buffer_threshold_cents,
    .daily_limit_cents_at_proposal = 200_000,
    .monthly_limit_cents_at_proposal = 1_000_000,
};
const drift_payment_governance = drift.PaymentProposalGovernance{
    .action_class = "payment_retry.propose",
    .approval_path = "maker_checker",
    .policy_version = "tickoni.v1",
};

const restricted_tickers = [_][]const u8{
    "SOXL", "SOXS", "TQQQ", "SQQQ", "UPRO", "SPXS",
    "UVXY", "SVXY", "LABU", "LABD", "FAS",  "FAZ",
};

pub const DemoScenario = enum {
    allowed,
    oversized_blocked,
    restricted_instrument,

    pub fn label(self: DemoScenario) []const u8 {
        return switch (self) {
            .allowed => "allowed",
            .oversized_blocked => "oversized_blocked",
            .restricted_instrument => "restricted_instrument",
        };
    }
};

pub const LiveConfig = struct {
    endpoint: []const u8,
    model_id: []const u8,
    use_fixture: bool = false,
};

pub const ParsedDemoRequest = struct {
    input: thesis.ThesisInput,
    scenario: DemoScenario,
};

pub const LiveModelEvidence = struct {
    model_id: []u8,
    excerpt: []u8,
    matched_ticker: []u8,

    pub fn deinit(self: *LiveModelEvidence, allocator: std.mem.Allocator) void {
        allocator.free(self.model_id);
        allocator.free(self.excerpt);
        allocator.free(self.matched_ticker);
    }
};

pub const AllowedTradeScenarioResult = struct {
    basket: basket_mod.Basket,
    ticket: trade_ticket.TradeTicket,
    portfolio_impact: impact.PortfolioImpact,
    decision_cards: cards.DecisionCardsContract,
    drift_contract: drift.DriftContract,
    replay_result: replay.ReplayVerification,
};

pub const BlockedTradeScenarioResult = struct {
    ticket: trade_ticket.TradeTicket,
    replay_result: replay.ReplayVerification,
};

pub const RestrictedInstrumentScenarioResult = struct {
    requested_ticker: []const u8,
    replay_result: replay.ReplayVerification,
};

pub const CliReport = struct {
    scenario: []const u8,
    model_id: []u8,
    matched_ticker: []u8,
    excerpt: []u8,
    target_notional_cents: i64,
    policy_outcome: []const u8,
    ticket_id: ?[]u8 = null,
    blocked_reason: ?[]const u8 = null,
    failed_scope_dim: ?[]const u8 = null,
    replay_match: bool,
    external_effects_disabled: bool,
    divergence_count: u64,

    pub fn deinit(self: *CliReport, allocator: std.mem.Allocator) void {
        allocator.free(self.model_id);
        allocator.free(self.matched_ticker);
        allocator.free(self.excerpt);
        if (self.ticket_id) |ticket_id| allocator.free(ticket_id);
    }
};

pub const AllowedTradeInterfaceContract = struct {
    schema_version: u16 = 1,
    portfolio_impact: impact.PortfolioImpact,
    decision_cards: cards.DecisionCardsContract,
    drift_contract: drift.DriftContract,
    replay_summary: struct {
        replay_match: bool,
        external_effects_disabled: bool,
        divergence_count: u64,
    },
};

fn boolLabel(value: bool) []const u8 {
    return if (value) "true" else "false";
}

pub fn allocAllowedTradeInterfaceJson(
    allocator: std.mem.Allocator,
    result: *const AllowedTradeScenarioResult,
) ![]u8 {
    const portfolio_impact_json = try impact.allocPortfolioImpactJson(allocator, &result.portfolio_impact);
    defer allocator.free(portfolio_impact_json);
    const decision_cards_json = try cards.allocDecisionCardsJson(allocator, &result.decision_cards);
    defer allocator.free(decision_cards_json);
    const drift_json = try drift.allocDriftContractJson(allocator, &result.drift_contract);
    defer allocator.free(drift_json);

    return std.fmt.allocPrint(
        allocator,
        "{{\"schema_version\":1,\"portfolio_impact\":{s},\"decision_cards\":{s},\"drift_contract\":{s},\"replay_summary\":{{\"replay_match\":{s},\"external_effects_disabled\":{s},\"divergence_count\":{d}}}}}",
        .{
            portfolio_impact_json,
            decision_cards_json,
            drift_json,
            boolLabel(result.replay_result.replay_match),
            boolLabel(result.replay_result.external_effects_disabled),
            result.replay_result.divergence_count,
        },
    );
}

pub fn envOrDefault(
    allocator: std.mem.Allocator,
    name: []const u8,
    fallback: []const u8,
) ![]u8 {
    if (std.process.getEnvVarOwned(allocator, name)) |owned| return owned;
    return allocator.dupe(u8, fallback);
}

fn makeLiveConfig(allowed_model_id: []const u8) model.TkModlConfig {
    var config = model.TkModlConfig{
        .live_provider_enabled = true,
        .hard_max_context_tokens = 16384,
        .hard_max_output_tokens = 8192,
        .hard_max_retry_count = 1,
        .hard_timeout_ms = 30_000,
        .per_run_token_budget = 16384,
    };
    config.allowed_model_ids[0] = allowed_model_id;
    config.allowed_model_id_count = 1;
    return config;
}

fn buildUserPrompt(
    allocator: std.mem.Allocator,
    input: thesis.ThesisInput,
) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "Thesis: {s}\n" ++
            "Target notional: USD {d}\n" ++
            "Asset classes: equity, etf\n" ++
            "Market: US\n" ++
            "Sector theme: ai_infrastructure\n" ++
            "Risk preference: moderate\n" ++
            "Max single-name weight: {d}%",
        .{
            input.text(),
            @divTrunc(input.target_notional_cents, 100),
            input.max_single_name_pct,
        },
    );
}

fn excerptForPrint(allocator: std.mem.Allocator, content: []const u8) ![]u8 {
    const excerpt_len = @min(content.len, 160);
    var buf = try allocator.alloc(u8, excerpt_len);
    for (content[0..excerpt_len], 0..) |c, i| {
        buf[i] = switch (c) {
            '\n', '\r', '\t' => ' ',
            else => c,
        };
    }
    return buf;
}

fn emptyLiveEvidence(allocator: std.mem.Allocator) !LiveModelEvidence {
    return .{
        .model_id = try allocator.dupe(u8, ""),
        .excerpt = try allocator.dupe(u8, ""),
        .matched_ticker = try allocator.dupe(u8, ""),
    };
}

fn assertLiveModelResponse(
    allocator: std.mem.Allocator,
    response: *const model.ModelResponse,
) !LiveModelEvidence {
    if (response.content.len == 0) return error.EmptyModelResponse;
    if (response.token_usage.total_tokens == 0) return error.EmptyTokenUsage;
    if (response.finish_reason.len == 0) return error.EmptyFinishReason;

    const allowed_tickers = [_][]const u8{
        "NVDA", "AMD", "AVGO", "MSFT", "AMZN", "GOOGL", "SOXX", "SMH", "QQQ", "VGT",
    };
    var matched_ticker: ?[]const u8 = null;
    for (allowed_tickers) |ticker| {
        if (std.mem.indexOf(u8, response.content, ticker) != null) {
            matched_ticker = ticker;
            break;
        }
    }
    if (matched_ticker == null) return error.NoAllowedTickerMatched;

    for (restricted_tickers) |restricted| {
        if (std.mem.indexOf(u8, response.content, restricted) != null) {
            return error.RestrictedTickerReturned;
        }
    }

    if (std.mem.indexOf(u8, response.content, "<|channel>thought") != null) {
        const guidance_markers = [_][]const u8{
            "AI infrastructure",
            "single-name concentration",
            "US-listed",
        };
        for (guidance_markers) |marker| {
            if (std.mem.indexOf(u8, response.content, marker) == null) {
                return error.MissingGuidanceMarker;
            }
        }
    }

    return .{
        .model_id = try allocator.dupe(u8, response.model_id),
        .excerpt = try excerptForPrint(allocator, response.content),
        .matched_ticker = try allocator.dupe(u8, matched_ticker.?),
    };
}

pub fn runLiveModel(
    allocator: std.mem.Allocator,
    io: std.Io,
    live_config: LiveConfig,
    input: thesis.ThesisInput,
) !LiveModelEvidence {
    std.debug.print("=== runLiveModel BEGIN ===\nendpoint={s}\nmodel={s}\n", .{ live_config.endpoint, live_config.model_id });

    const user_prompt = try buildUserPrompt(allocator, input);
    defer allocator.free(user_prompt);

    const messages = [_]model.Message{
        .{ .role = "system", .content = system_prompt },
        .{ .role = "user", .content = user_prompt },
    };
    const request = model.TkModlRequest{
        .request_id = 1,
        .run_id = 1,
        .actor_id = input.account_id,
        .actor_role = live_actor_role,
        .workflow = live_workflow,
        .account_id = input.account_id,
        .capability = live_capability,
        .capability_envelope_id = live_capability_envelope_id,
        .policy_version = live_policy_version,
        .policy_decision_id = 0,
        .budget_id = live_budget_id,
        .model_id = live_config.model_id,
        .messages = &messages,
        .sampling = .{
            .temperature = 0,
            .top_p = 1.0,
            .max_output_tokens = 4096,
            .seed = 42,
        },
        .max_context_tokens = 8192,
        .max_output_tokens = 4096,
        .retry_limit = 0,
        .timeout_ms = 30_000,
        .replay_mode = .live,
    };

    var live_model_backend_impl = model.HttpBackend{
        .endpoint = live_config.endpoint,
        .io = io,
    };
    var live_model_backend = live_model_backend_impl.asBackend();
    var tkmodl_result = try model.runTkModlRequest(
        allocator,
        makeLiveConfig(live_config.model_id),
        &live_model_backend,
        request,
    );
    defer tkmodl_result.deinit(allocator);

    switch (tkmodl_result.outcome) {
        .allow_live => {},
        else => return error.TkModlLiveDenied,
    }

    const response = tkmodl_result.response orelse return error.MissingLiveResponse;
    tkmodl_result.response = null;
    defer response.deinit(allocator);

    const result = try assertLiveModelResponse(allocator, &response);
    std.debug.print("=== runLiveModel END ===\nmodel_id={s}\nticker={s}\n", .{ result.model_id, result.matched_ticker });
    return result;
}

pub fn runFixtureModel(
    allocator: std.mem.Allocator,
    input: thesis.ThesisInput,
) !LiveModelEvidence {
    std.debug.print("=== runFixtureModel BEGIN ===\n", .{});

    const user_prompt = try buildUserPrompt(allocator, input);
    defer allocator.free(user_prompt);

    const messages = [_]model.Message{
        .{ .role = "system", .content = system_prompt },
        .{ .role = "user", .content = user_prompt },
    };
    const request = model.TkModlRequest{
        .request_id = 1,
        .run_id = 1,
        .actor_id = input.account_id,
        .actor_role = live_actor_role,
        .workflow = live_workflow,
        .account_id = input.account_id,
        .capability = live_capability,
        .capability_envelope_id = live_capability_envelope_id,
        .policy_version = live_policy_version,
        .policy_decision_id = 0,
        .budget_id = live_budget_id,
        .model_id = default_model_id,
        .messages = &messages,
        .sampling = .{
            .temperature = 0,
            .top_p = 1.0,
            .max_output_tokens = 4096,
            .seed = 42,
        },
        .max_context_tokens = 8192,
        .max_output_tokens = 4096,
        .retry_limit = 0,
        .timeout_ms = 30_000,
        .replay_mode = .live,
    };

    var fixture_backend_impl = model.FixtureBackend{};
    var fixture_backend = fixture_backend_impl.asBackend();
    var tkmodl_result = try model.runTkModlRequest(
        allocator,
        makeLiveConfig(default_model_id),
        &fixture_backend,
        request,
    );
    defer tkmodl_result.deinit(allocator);

    switch (tkmodl_result.outcome) {
        .allow_live => {},
        else => return error.TkModlFixtureDenied,
    }

    const response = tkmodl_result.response orelse return error.MissingFixtureResponse;
    tkmodl_result.response = null;
    defer response.deinit(allocator);

    const result = try assertLiveModelResponse(allocator, &response);
    std.debug.print("=== runFixtureModel END ===\nmodel_id={s}\nticker={s}\n", .{ result.model_id, result.matched_ticker });
    return result;
}

pub fn runAllowedTradeScenario(
    allocator: std.mem.Allocator,
    io: std.Io,
    input: thesis.ThesisInput,
) !AllowedTradeScenarioResult {
    if (input.target_notional_cents != support.target_notional_cents) {
        return error.UnsupportedDemoAmount;
    }

    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const basket = try tkpoly.buildBasket(intent, thesis_id);
    if (!support.basketRejects(&basket, "SOXL")) return error.MissingRestrictedLeverageGuardrail;
    if (!support.basketRejects(&basket, "BULZ")) return error.MissingRestrictedLeverageGuardrail;

    var adapter_backend_impl = adapter.FixtureBackend{};
    var adapter_backend = adapter_backend_impl.asBackend();
    const portfolio_result = try adapter_backend.call(tool.normalizePortfolioRead(input.account_id));
    const account = switch (portfolio_result) {
        .portfolio_snapshot => |snapshot| snapshot,
        else => return error.UnexpectedPortfolioResponse,
    };
    const affordability = try portfolio.checkBasketAffordability(&account, &basket);
    if (affordability.outcome != .allow) return error.UnexpectedAffordabilityOutcome;

    const quote_result = try adapter_backend.call(tool.normalizeQuoteRead(&basket));
    const quote_snapshot = switch (quote_result) {
        .quote_snapshot => |snapshot| snapshot,
        else => return error.UnexpectedQuoteResponse,
    };
    var ticket = try trade_ticket.buildMarketBuyTicket(
        &basket,
        &quote_snapshot,
        affordability,
        support.expected_ticket_id,
    );
    tkpoly.applyTradeGuardrails(&ticket, affordability, support.policy_max_notional_per_order_cents);
    if (ticket.policy_outcome != .allow) return error.UnexpectedPolicyOutcome;

    const paper_result = try adapter_backend.call(tool.normalizePaperOrder(&ticket));
    const execution = switch (paper_result) {
        .paper_order => |value| value,
        else => return error.UnexpectedPaperResponse,
    };
    if (execution.status != .filled) return error.UnexpectedExecutionStatus;
    if (execution.total_filled_cents != support.target_notional_cents) return error.UnexpectedFilledAmount;

    const contracts = try buildAllowedTradeContracts(
        input,
        &account,
        &basket,
        &execution,
    );

    var replay_model_backend_impl = model.FixtureBackend{};
    var replay_model_backend = replay_model_backend_impl.asBackend();
    var replay_adapter_backend_impl = adapter.FixtureBackend{};
    var replay_adapter_backend = replay_adapter_backend_impl.asBackend();
    const replay_result = try replay.verifyAllowedTrade(
        allocator,
        io,
        &replay_model_backend,
        &replay_adapter_backend,
        &basket,
        &ticket,
        &contracts.drift_contract,
    );
    if (!replay_result.external_effects_disabled) return error.ReplayExternalEffectsEnabled;
    if (!replay_result.replay_match) return error.ReplayMismatch;

    return .{
        .basket = basket,
        .ticket = ticket,
        .portfolio_impact = contracts.portfolio_impact,
        .decision_cards = contracts.decision_cards,
        .drift_contract = contracts.drift_contract,
        .replay_result = replay_result,
    };
}

pub fn runOversizedTradeScenario(
    allocator: std.mem.Allocator,
    io: std.Io,
    input: thesis.ThesisInput,
) !BlockedTradeScenarioResult {
    if (input.target_notional_cents != support.oversized_target_notional_cents) {
        return error.UnsupportedDemoAmount;
    }

    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const basket = try tkpoly.buildBasket(intent, thesis_id);

    var adapter_backend_impl = adapter.FixtureBackend{};
    var adapter_backend = adapter_backend_impl.asBackend();
    const portfolio_result = try adapter_backend.call(tool.normalizePortfolioRead(input.account_id));
    const account = switch (portfolio_result) {
        .portfolio_snapshot => |snapshot| snapshot,
        else => return error.UnexpectedPortfolioResponse,
    };
    const affordability = try portfolio.checkBasketAffordability(&account, &basket);
    const quote_result = try adapter_backend.call(tool.normalizeQuoteRead(&basket));
    const quote_snapshot = switch (quote_result) {
        .quote_snapshot => |snapshot| snapshot,
        else => return error.UnexpectedQuoteResponse,
    };
    var ticket = try trade_ticket.buildMarketBuyTicket(
        &basket,
        &quote_snapshot,
        affordability,
        support.expected_blocked_ticket_id,
    );
    tkpoly.applyTradeGuardrails(&ticket, affordability, support.policy_max_notional_per_order_cents);
    if (ticket.policy_outcome != .deny) return error.ExpectedBlockedPolicyOutcome;
    if (ticket.blocked_reason_count != 1) return error.UnexpectedBlockedReasonCount;
    if (ticket.blocked_reasons[0].code != .per_order_notional_exceeded) {
        return error.UnexpectedBlockedReason;
    }
    if (ticket.affordability_result.effective_max_paper_trade_cents != 250_000) {
        return error.UnexpectedEffectiveMaxTrade;
    }

    var replay_model_backend_impl = model.FixtureBackend{};
    var replay_model_backend = replay_model_backend_impl.asBackend();
    var replay_adapter_backend_impl = adapter.FixtureBackend{};
    var replay_adapter_backend = replay_adapter_backend_impl.asBackend();
    const replay_result = try replay.verifyOversizedTradeBlock(
        allocator,
        io,
        &replay_model_backend,
        &replay_adapter_backend,
        &basket,
        &ticket,
    );
    if (!replay_result.external_effects_disabled) return error.ReplayExternalEffectsEnabled;
    if (!replay_result.replay_match) return error.ReplayMismatch;

    return .{
        .ticket = ticket,
        .replay_result = replay_result,
    };
}

pub fn runRestrictedScenario(
    allocator: std.mem.Allocator,
    io: std.Io,
    input: thesis.ThesisInput,
) !RestrictedInstrumentScenarioResult {
    if (input.requested_ticker_count != 1) return error.MissingRestrictedTicker;
    if (!std.mem.eql(u8, input.requested_tickers[0][0..support.restricted_ticker.len], support.restricted_ticker)) {
        return error.UnsupportedRestrictedTicker;
    }

    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const basket = try tkpoly.buildBasket(intent, thesis_id);
    const rejected = support.findRejectedCandidate(&basket, support.restricted_ticker) orelse {
        return error.MissingRestrictedRejection;
    };
    if (!basket.hasRestrictedRejections()) return error.MissingRestrictedRejection;
    if (rejected.reason_code != .restricted_instrument) return error.UnexpectedRestrictedReason;

    const replay_result = try replay.verifyRestrictedInstrumentBlock(
        allocator,
        io,
        &basket,
        support.restricted_ticker,
    );
    if (!replay_result.external_effects_disabled) return error.ReplayExternalEffectsEnabled;
    if (!replay_result.replay_match) return error.ReplayMismatch;

    return .{
        .requested_ticker = support.restricted_ticker,
        .replay_result = replay_result,
    };
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0 or needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

fn copyUserText(input: *thesis.ThesisInput, user_text: []const u8) !void {
    if (user_text.len == 0) return error.EmptyUserText;
    if (user_text.len > thesis.max_user_text_len) return error.UserTextTooLong;
    @memset(&input.user_text, 0);
    @memcpy(input.user_text[0..user_text.len], user_text);
    input.user_text_len = @intCast(user_text.len);
}

fn setRequestedTicker(input: *thesis.ThesisInput, ticker: []const u8) !void {
    if (ticker.len > thesis.max_ticker_len) return error.TickerTooLong;
    input.requested_ticker_count = 1;
    @memset(&input.requested_tickers[0], 0);
    @memcpy(input.requested_tickers[0][0..ticker.len], ticker);
}

fn parseUsdAmountCents(user_text: []const u8) !i64 {
    var i: usize = 0;
    while (i < user_text.len) : (i += 1) {
        var start_after_marker: ?usize = null;
        if (user_text[i] == '$') {
            start_after_marker = i + 1;
        } else if (i + 3 <= user_text.len and std.ascii.eqlIgnoreCase(user_text[i .. i + 3], "USD")) {
            var j = i + 3;
            while (j < user_text.len and (user_text[j] == ' ' or user_text[j] == '\t' or user_text[j] == ':')) : (j += 1) {}
            if (j < user_text.len and user_text[j] == '$') j += 1;
            start_after_marker = j;
        }

        if (start_after_marker) |start| {
            var end = start;
            var saw_digit = false;
            while (end < user_text.len) : (end += 1) {
                const c = user_text[end];
                if (std.ascii.isDigit(c)) {
                    saw_digit = true;
                    continue;
                }
                if (c == ',' or c == '.') continue;
                break;
            }
            if (!saw_digit) continue;
            return parseUsdNumericSlice(user_text[start..end]);
        }
    }
    return error.MissingTargetAmount;
}

fn parseUsdNumericSlice(raw: []const u8) !i64 {
    var buf: [32]u8 = undefined;
    var len: usize = 0;
    var dot_index: ?usize = null;
    for (raw) |c| {
        switch (c) {
            '0'...'9' => {
                if (len >= buf.len) return error.InvalidTargetAmount;
                buf[len] = c;
                len += 1;
            },
            ',' => {},
            '.' => {
                if (dot_index != null) return error.InvalidTargetAmount;
                dot_index = len;
            },
            else => return error.InvalidTargetAmount,
        }
    }
    if (len == 0) return error.InvalidTargetAmount;

    const digits = buf[0..len];
    if (dot_index) |dot| {
        const whole = if (dot == 0) 0 else try std.fmt.parseInt(i64, digits[0..dot], 10);
        const frac_digits = digits[dot..];
        var cents: i64 = 0;
        if (frac_digits.len >= 1) cents += @as(i64, frac_digits[0] - '0') * 10;
        if (frac_digits.len >= 2) cents += @as(i64, frac_digits[1] - '0');
        return whole * 100 + cents;
    }

    const whole = try std.fmt.parseInt(i64, digits, 10);
    return whole * 100;
}

pub fn parseCliDemoRequest(user_text: []const u8) !ParsedDemoRequest {
    var input = support.operationsThesisInput();
    try copyUserText(&input, user_text);
    input.target_notional_cents = try parseUsdAmountCents(user_text);

    const restricted_requested = containsIgnoreCase(user_text, support.restricted_ticker);
    if (restricted_requested) {
        try setRequestedTicker(&input, support.restricted_ticker);
        if (input.target_notional_cents != support.target_notional_cents) {
            return error.UnsupportedDemoAmount;
        }
        return .{
            .input = input,
            .scenario = .restricted_instrument,
        };
    }

    if (input.target_notional_cents == support.target_notional_cents) {
        return .{
            .input = input,
            .scenario = .allowed,
        };
    }
    if (input.target_notional_cents == support.oversized_target_notional_cents) {
        return .{
            .input = input,
            .scenario = .oversized_blocked,
        };
    }
    return error.UnsupportedDemoAmount;
}

pub fn runCliDemo(
    allocator: std.mem.Allocator,
    io: std.Io,
    live_config: LiveConfig,
    user_text: []const u8,
) !CliReport {
    const parsed = try parseCliDemoRequest(user_text);
    var live_evidence = if (parsed.scenario == .restricted_instrument)
        try emptyLiveEvidence(allocator)
    else if (live_config.use_fixture)
        try runFixtureModel(allocator, parsed.input)
    else
        try runLiveModel(allocator, io, live_config, parsed.input);
    errdefer live_evidence.deinit(allocator);

    // Replay scenario functions use the canonical fixture inputs so their
    // thesis hashes match the stored capsule hashes.  The live model call
    // above already used parsed.input (with the user's CLI text).
    switch (parsed.scenario) {
        .allowed => {
            const result = try runAllowedTradeScenario(allocator, io, support.operationsThesisInput());
            return .{
                .scenario = parsed.scenario.label(),
                .model_id = live_evidence.model_id,
                .matched_ticker = live_evidence.matched_ticker,
                .excerpt = live_evidence.excerpt,
                .target_notional_cents = parsed.input.target_notional_cents,
                .policy_outcome = "allow",
                .ticket_id = try allocator.dupe(u8, result.ticket.ticketIdSlice()),
                .replay_match = result.replay_result.replay_match,
                .external_effects_disabled = result.replay_result.external_effects_disabled,
                .divergence_count = result.replay_result.divergence_count,
            };
        },
        .oversized_blocked => {
            const result = try runOversizedTradeScenario(
                allocator,
                io,
                support.operationsThesisInputWithTarget(support.oversized_target_notional_cents),
            );
            return .{
                .scenario = parsed.scenario.label(),
                .model_id = live_evidence.model_id,
                .matched_ticker = live_evidence.matched_ticker,
                .excerpt = live_evidence.excerpt,
                .target_notional_cents = parsed.input.target_notional_cents,
                .policy_outcome = "deny",
                .ticket_id = try allocator.dupe(u8, result.ticket.ticketIdSlice()),
                .blocked_reason = result.ticket.blocked_reasons[0].code.label(),
                .failed_scope_dim = result.ticket.blocked_reasons[0].failed_scope_dim.label(),
                .replay_match = result.replay_result.replay_match,
                .external_effects_disabled = result.replay_result.external_effects_disabled,
                .divergence_count = result.replay_result.divergence_count,
            };
        },
        .restricted_instrument => {
            const result = try runRestrictedScenario(allocator, io, support.operationsRestrictedTickerInput());
            return .{
                .scenario = parsed.scenario.label(),
                .model_id = live_evidence.model_id,
                .matched_ticker = live_evidence.matched_ticker,
                .excerpt = live_evidence.excerpt,
                .target_notional_cents = parsed.input.target_notional_cents,
                .policy_outcome = "deny",
                .blocked_reason = "restricted_instrument",
                .failed_scope_dim = "restricted_instrument",
                .replay_match = result.replay_result.replay_match,
                .external_effects_disabled = result.replay_result.external_effects_disabled,
                .divergence_count = result.replay_result.divergence_count,
            };
        },
    }
}

pub fn writeCliReportJson(
    allocator: std.mem.Allocator,
    writer: anytype,
    report: CliReport,
) !void {
    const json = try std.json.Stringify.valueAlloc(allocator, .{
        .scenario = report.scenario,
        .model_id = report.model_id,
        .matched_ticker = report.matched_ticker,
        .excerpt = report.excerpt,
        .target_notional_cents = report.target_notional_cents,
        .policy_outcome = report.policy_outcome,
        .ticket_id = report.ticket_id,
        .blocked_reason = report.blocked_reason,
        .failed_scope_dim = report.failed_scope_dim,
        .replay_match = report.replay_match,
        .external_effects_disabled = report.external_effects_disabled,
        .divergence_count = report.divergence_count,
    }, .{});
    defer allocator.free(json);
    try writer.writeAll(json);
    try writer.writeAll("\n");
}

pub fn writeCliReportText(writer: anytype, report: CliReport) !void {
    try writer.print(
        "scenario: {s}\nmodel: {s}\nmatched_ticker: {s}\npolicy_outcome: {s}\n",
        .{ report.scenario, report.model_id, report.matched_ticker, report.policy_outcome },
    );
    if (report.ticket_id) |ticket_id| {
        try writer.print("ticket_id: {s}\n", .{ticket_id});
    }
    if (report.blocked_reason) |blocked_reason| {
        try writer.print("blocked_reason: {s}\n", .{blocked_reason});
    }
    if (report.failed_scope_dim) |failed_scope_dim| {
        try writer.print("failed_scope_dim: {s}\n", .{failed_scope_dim});
    }
    try writer.print(
        "target_notional_cents: {d}\nreplay_match: {s}\nexternal_effects_disabled: {s}\nexcerpt: {s}\n",
        .{
            report.target_notional_cents,
            if (report.replay_match) "true" else "false",
            if (report.external_effects_disabled) "true" else "false",
            report.excerpt,
        },
    );
}

pub fn runSystemSuite(
    allocator: std.mem.Allocator,
    io: std.Io,
    live_config: LiveConfig,
) !void {
    const input = support.operationsThesisInput();
    var live_result = if (live_config.use_fixture)
        try runFixtureModel(allocator, input)
    else
        try runLiveModel(allocator, io, live_config, input);
    std.debug.print("=== runSystemSuite: model path={s} ===\n", .{
        if (live_config.use_fixture) "fixture" else "live",
    });
    defer live_result.deinit(allocator);
    std.debug.print(
        "=== Live tkmodl ===\nendpoint={s}\nmodel={s}\nmatched_ticker={s}\nexcerpt={s}\n",
        .{ live_config.endpoint, live_result.model_id, live_result.matched_ticker, live_result.excerpt },
    );

    const allowed = try runAllowedTradeScenario(allocator, io, input);
    std.debug.print(
        "=== Allowed USD 2,000 ===\naccount={d} ticket={s} cost_cents={d}\n",
        .{ allowed.ticket.account_id, allowed.ticket.ticketIdSlice(), allowed.ticket.estimated_cost_cents },
    );
    std.debug.print(
        "=== Replay ===\nmatch={s} external_effects_disabled={s}\n",
        .{
            if (allowed.replay_result.replay_match) "true" else "false",
            if (allowed.replay_result.external_effects_disabled) "true" else "false",
        },
    );
    const decision_payload_json = try allocAllowedTradeInterfaceJson(allocator, &allowed);
    defer allocator.free(decision_payload_json);
    std.debug.print("=== Decision Payload ===\n{s}\n", .{decision_payload_json});

    const blocked = try runOversizedTradeScenario(
        allocator,
        io,
        support.operationsThesisInputWithTarget(support.oversized_target_notional_cents),
    );
    std.debug.print(
        "=== Blocked USD 25,000 ===\nticket={s} reason={s} effective_max_cents={d}\n",
        .{
            blocked.ticket.ticketIdSlice(),
            blocked.ticket.blocked_reasons[0].code.label(),
            blocked.ticket.affordability_result.effective_max_paper_trade_cents,
        },
    );

    const restricted = try runRestrictedScenario(allocator, io, support.operationsRestrictedTickerInput());
    std.debug.print(
        "=== Restricted Instrument ===\nrequested={s} replay_match={s}\n",
        .{
            restricted.requested_ticker,
            if (restricted.replay_result.replay_match) "true" else "false",
        },
    );
}

test "parseCliDemoRequest: allowed thesis maps to allowed scenario" {
    const parsed = try parseCliDemoRequest(
        "I want to invest USD 2,000 in AI infrastructure through US-listed ETFs and equities.",
    );
    try std.testing.expectEqual(DemoScenario.allowed, parsed.scenario);
    try std.testing.expectEqual(support.target_notional_cents, parsed.input.target_notional_cents);
    try std.testing.expectEqual(@as(u8, 0), parsed.input.requested_ticker_count);
}

test "parseCliDemoRequest: oversized thesis maps to blocked scenario" {
    const parsed = try parseCliDemoRequest(
        "I want to invest USD 25,000 in AI infrastructure through US-listed ETFs and equities.",
    );
    try std.testing.expectEqual(DemoScenario.oversized_blocked, parsed.scenario);
    try std.testing.expectEqual(support.oversized_target_notional_cents, parsed.input.target_notional_cents);
}

test "parseCliDemoRequest: SOXL thesis maps to restricted scenario" {
    const parsed = try parseCliDemoRequest(
        "Buy SOXL in an AI infrastructure basket with USD 2,000.",
    );
    try std.testing.expectEqual(DemoScenario.restricted_instrument, parsed.scenario);
    try std.testing.expectEqual(@as(u8, 1), parsed.input.requested_ticker_count);
    try std.testing.expectEqualStrings(
        support.restricted_ticker,
        parsed.input.requested_tickers[0][0..support.restricted_ticker.len],
    );
}

test "parseCliDemoRequest: unsupported amount fails closed" {
    try std.testing.expectError(
        error.UnsupportedDemoAmount,
        parseCliDemoRequest("I want to invest USD 5,000 in AI infrastructure."),
    );
}

test "runAllowedTradeScenario persists and exposes decision cards and drift contract" {
    const result = try runAllowedTradeScenario(std.testing.allocator, std.testing.io, support.operationsThesisInput());

    try std.testing.expectEqual(result.basket.basket_id, result.decision_cards.thesis_card.basket_id);
    try std.testing.expectEqual(
        thesis.computeThesisInputHash(support.operationsThesisInput()),
        result.decision_cards.thesis_card.thesis_id,
    );
    try std.testing.expectEqualStrings(supplier_payout_beneficiary, result.decision_cards.money_proposal_card.beneficiarySlice());
    try std.testing.expectEqualStrings(supplier_payout_source_event, result.decision_cards.money_proposal_card.sourceEventSlice());
    try std.testing.expectEqualStrings(supplier_payout_currency, result.decision_cards.money_proposal_card.currencySlice());
    try std.testing.expect(result.drift_contract.thesis_drift.has_drift);
    try std.testing.expect(result.drift_contract.payment_drift.has_drift);

    // The supplier payout is a pending obligation in the same combined
    // impact payload as the trade, and it stays approval-required.
    try std.testing.expectEqual(supplier_payout_amount_cents, result.portfolio_impact.pending_obligations_after_cents);
    try std.testing.expect(result.portfolio_impact.any_approval_required);
    try std.testing.expect(result.portfolio_impact.explanation_count > 0);

    const json = try allocAllowedTradeInterfaceJson(std.testing.allocator, &result);
    defer std.testing.allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"portfolio_impact\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"explanations\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"decision_cards\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"drift_contract\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"rebalance_suggestion\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"payment_proposal_update\"") != null);
}

const AllowedTradeContracts = struct {
    portfolio_impact: impact.PortfolioImpact,
    decision_cards: cards.DecisionCardsContract,
    drift_contract: drift.DriftContract,
};

fn buildAllowedTradeContracts(
    input: thesis.ThesisInput,
    account_before: *const portfolio.BrokerageAccount,
    basket: *const basket_mod.Basket,
    execution: *const trade_ticket.PaperExecutionResult,
) !AllowedTradeContracts {
    // The supplier payout is part of the same decision payload as the trade
    // (V1.3.S4.T3), so it is included as a pending obligation in the
    // combined portfolio/cash impact even though the trade itself does not
    // change its approval or cash state.
    const payout_obligation = impact.PendingObligation{
        .proposal_id = supplier_payout_proposal_id,
        .rail = .ach,
        .destination_id = 9001,
        .amount_cents = supplier_payout_amount_cents,
        .approval_state = .pending,
        .expires_at_ns = supplier_payout_expires_at_ns,
    };
    const pending_obligations = [_]impact.PendingObligation{payout_obligation};

    const target_impact = impact.computePreTradeImpact(
        account_before,
        basket,
        &pending_obligations,
        demo_cash_buffer_threshold_cents,
        decision_cards_now_ns,
    );
    var realized_impact = impact.computeRealizedTradeImpact(
        account_before,
        basket,
        execution.total_filled_cents,
        &pending_obligations,
        demo_cash_buffer_threshold_cents,
        decision_cards_now_ns,
    );
    const policy_max_single_name_bp: u32 = @as(u32, input.max_single_name_pct) * 100;
    impact.generateExplanations(&realized_impact, policy_max_single_name_bp);

    var store = cards.DecisionCardsStore{};
    store.saveThesisCard(try cards.buildThesisCard(
        thesis.computeThesisInputHash(input),
        input.text(),
        basket,
        target_impact.thesis_after_bp,
        realized_impact.thesis_after_bp,
        replay.hashBytes("evidence.ai_infrastructure.positions.v1"),
        decision_cards_now_ns,
    ));

    store.saveMoneyProposalCard(try cards.buildMoneyProposalCard(
        &payout_obligation,
        supplier_payout_source_event,
        supplier_payout_beneficiary,
        supplier_payout_currency,
        replay.hashBytes("evidence.payment_retry.supplier_acme_us.v1"),
        decision_cards_now_ns,
    ));

    const decision_cards = try store.snapshot();
    const thesis_drift = try drift.assessThesisDrift(
        &decision_cards.thesis_card,
        drift_market_exposure_bp,
        drift_market_max_sector_bp,
        drift_market_max_single_name_bp,
        drift_market_buying_power_cents,
        null,
        drift_rebalance_policy,
    );
    const rebalance = try drift.generateRebalanceSuggestion(
        &decision_cards.thesis_card,
        thesis_drift,
        drift_market_buying_power_cents,
    );
    const payment_drift = try drift.assessPaymentDrift(
        &decision_cards.money_proposal_card,
        drift_check_now_ns,
        drift_retry_window_expiry_ns,
        drift_evidence_expiry_ns,
        cards.ApprovalState.approved,
        drift_payment_available_cash_cents,
        drift_payment_daily_limit_cents,
        drift_payment_monthly_limit_cents,
        drift_payment_policy,
    );
    const payment_update = try drift.generateGovernedPaymentProposalUpdate(
        &decision_cards.money_proposal_card,
        payment_drift,
        drift_payment_governance,
    );

    return .{
        .portfolio_impact = realized_impact,
        .decision_cards = decision_cards,
        .drift_contract = .{
            .thesis_drift = thesis_drift,
            .rebalance_suggestion = rebalance,
            .payment_drift = payment_drift,
            .payment_proposal_update = payment_update,
        },
    };
}
