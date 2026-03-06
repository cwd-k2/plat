use crate::domain::account::{Account, AccountId};
use crate::domain::event::DomainEvent;
use crate::infrastructure::{AccountRepository, EventStore};

/// Corresponds to: command OpenAccount : application
///   needs AccountRepository, EventStore
///   emit AccountOpened
pub fn execute(
    repo: &mut impl AccountRepository,
    events: &mut impl EventStore,
    owner: &str,
) -> Result<AccountId, String> {
    let id = AccountId(format!("acc-{:04}", repo.count() + 1));
    let mut account = Account::new(id.clone(), owner, "USD");

    let event = DomainEvent::AccountOpened {
        account_id: id.clone(),
        owner: owner.to_string(),
        opened_at: "2026-03-06T00:00:00Z".to_string(),
    };
    account.apply(&event);
    events.append(&id, vec![event])?;
    repo.save(account)?;

    Ok(id)
}
