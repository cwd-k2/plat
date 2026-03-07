use super::account::{AccountId, Money};

/// Corresponds to: value StatementEntry : domain
#[derive(Debug, Clone)]
pub struct StatementEntry {
    pub date: String,
    pub description: String,
    pub amount: Money,
    pub running_balance: Money,
}

/// Corresponds to: value Statement : domain
#[derive(Debug, Clone)]
pub struct Statement {
    pub account_id: AccountId,
    pub period_start: String,
    pub period_end: String,
    pub opening_balance: Money,
    pub closing_balance: Money,
    pub entries: Vec<StatementEntry>,
}
