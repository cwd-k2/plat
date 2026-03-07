use crate::domain::account::AccountId;
use crate::domain::statement::Statement;
use crate::infrastructure::{EventStore, StatementStore};

/// Corresponds to: query GetStatement : application
///   needs EventStore, StatementStore
pub fn execute(
    _events: &impl EventStore,
    statements: &impl StatementStore,
    account_id: &AccountId,
) -> Result<Vec<Statement>, String> {
    statements.find_by_account(account_id)
}
