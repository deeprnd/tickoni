/// Shared capability-envelope identifier vocabulary for the investment
/// trading workflow (doc/knowledge/architecture.md's Example Flow: actor
/// role `trading_ops_reviewer`, workflow `trading_control`, capability
/// `trading_order.propose`). Single source of truth so agent/model tile code
/// and fixture/replay code cannot drift on these identifiers by retyping them.
pub const investment_actor_role = "trading_ops_reviewer";
pub const investment_workflow = "trading_control";
pub const investment_capability = "trading_order.propose";
