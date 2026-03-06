use crate::domain::account::AccountId;
use crate::domain::event::DomainEvent;
use crate::infrastructure::EventStore;

/// Corresponds to: query GetTransactionHistory : application
///   needs EventStore
pub fn execute(events: &impl EventStore, account_id: &AccountId) -> Result<Vec<DomainEvent>, String> {
    events.load_all(account_id)
}
