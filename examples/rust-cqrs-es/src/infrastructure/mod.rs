mod in_memory;

pub use in_memory::{InMemoryAccountRepo, InMemoryEventStore, InMemoryStatementStore};

use crate::domain::account::{Account, AccountId};
use crate::domain::event::DomainEvent;
use crate::domain::statement::Statement;

/// Corresponds to: boundary AccountRepository : domain
///   op load: AccountId -> (Account, Error)
///   op save: Account -> Error
pub trait AccountRepository {
    fn load(&self, id: &AccountId) -> Result<Account, String>;
    fn save(&mut self, account: Account) -> Result<(), String>;
    fn count(&self) -> usize;
    fn list_all(&self) -> Result<Vec<Account>, String>;
}

/// Corresponds to: boundary EventStore : domain
///   op append:  (AccountId, List<Event>) -> Error
///   op loadAll: AccountId -> (List<Event>, Error)
pub trait EventStore {
    fn append(&mut self, id: &AccountId, events: Vec<DomainEvent>) -> Result<(), String>;
    fn load_all(&self, id: &AccountId) -> Result<Vec<DomainEvent>, String>;
}

/// Corresponds to: boundary StatementStore : domain
///   op save:          Statement -> Error
///   op findByAccount: AccountId -> (List<Statement>, Error)
pub trait StatementStore {
    fn save(&mut self, statement: Statement) -> Result<(), String>;
    fn find_by_account(&self, account_id: &AccountId) -> Result<Vec<Statement>, String>;
}
