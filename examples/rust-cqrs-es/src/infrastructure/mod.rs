mod in_memory;

pub use in_memory::{InMemoryAccountRepo, InMemoryEventStore};

use crate::domain::account::{Account, AccountId};
use crate::domain::event::DomainEvent;

/// Corresponds to: boundary AccountRepository : domain
///   op load: AccountId -> (Account, Error)
///   op save: Account -> Error
pub trait AccountRepository {
    fn load(&self, id: &AccountId) -> Result<Account, String>;
    fn save(&mut self, account: Account) -> Result<(), String>;
    fn count(&self) -> usize;
}

/// Corresponds to: boundary EventStore : domain
///   op append:  (AccountId, List<Event>) -> Error
///   op loadAll: AccountId -> (List<Event>, Error)
pub trait EventStore {
    fn append(&mut self, id: &AccountId, events: Vec<DomainEvent>) -> Result<(), String>;
    fn load_all(&self, id: &AccountId) -> Result<Vec<DomainEvent>, String>;
}
