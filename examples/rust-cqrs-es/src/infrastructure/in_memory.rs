use std::collections::HashMap;

use crate::domain::account::{Account, AccountId};
use crate::domain::event::DomainEvent;

use super::{AccountRepository, EventStore};

/// In-memory stub for concept verification.
/// Corresponds to: adapter PostgresAccountRepo : infrastructure implements AccountRepository
#[derive(Default, Clone)]
pub struct InMemoryAccountRepo {
    accounts: HashMap<AccountId, Account>,
}

impl AccountRepository for InMemoryAccountRepo {
    fn load(&self, id: &AccountId) -> Result<Account, String> {
        self.accounts
            .get(id)
            .cloned()
            .ok_or_else(|| format!("account {} not found", id))
    }

    fn save(&mut self, account: Account) -> Result<(), String> {
        self.accounts.insert(account.id.clone(), account);
        Ok(())
    }

    fn count(&self) -> usize {
        self.accounts.len()
    }
}

/// In-memory stub for concept verification.
/// Corresponds to: adapter PostgresEventStore : infrastructure implements EventStore
#[derive(Default, Clone)]
pub struct InMemoryEventStore {
    streams: HashMap<AccountId, Vec<DomainEvent>>,
}

impl EventStore for InMemoryEventStore {
    fn append(&mut self, id: &AccountId, events: Vec<DomainEvent>) -> Result<(), String> {
        self.streams
            .entry(id.clone())
            .or_default()
            .extend(events);
        Ok(())
    }

    fn load_all(&self, id: &AccountId) -> Result<Vec<DomainEvent>, String> {
        Ok(self.streams.get(id).cloned().unwrap_or_default())
    }
}
