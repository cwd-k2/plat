use std::collections::HashMap;

use crate::domain::account::{Account, AccountId};
use crate::domain::event::DomainEvent;
use crate::domain::statement::Statement;

use super::{AccountRepository, EventStore, StatementStore};

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

    fn list_all(&self) -> Result<Vec<Account>, String> {
        Ok(self.accounts.values().cloned().collect())
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

/// In-memory stub for concept verification.
/// Corresponds to: adapter PostgresStatementStore : infrastructure implements StatementStore
#[derive(Default, Clone)]
pub struct InMemoryStatementStore {
    statements: HashMap<AccountId, Vec<Statement>>,
}

impl StatementStore for InMemoryStatementStore {
    fn save(&mut self, statement: Statement) -> Result<(), String> {
        self.statements
            .entry(statement.account_id.clone())
            .or_default()
            .push(statement);
        Ok(())
    }

    fn find_by_account(&self, account_id: &AccountId) -> Result<Vec<Statement>, String> {
        Ok(self.statements.get(account_id).cloned().unwrap_or_default())
    }
}
