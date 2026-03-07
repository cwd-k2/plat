use crate::domain::account::AccountId;
use crate::domain::event::DomainEvent;
use crate::infrastructure::{AccountRepository, EventStore};

/// Corresponds to: command UnfreezeAccount : application
///   needs AccountRepository, EventStore
///   emit AccountUnfrozen
pub fn execute(
    repo: &mut impl AccountRepository,
    events: &mut impl EventStore,
    account_id: &AccountId,
) -> Result<(), String> {
    let mut account = repo.load(account_id)?;

    if account.status != "frozen" {
        return Err(format!("cannot unfreeze account with status '{}'", account.status));
    }

    let event = DomainEvent::AccountUnfrozen {
        account_id: account_id.clone(),
        unfrozen_at: "2026-03-07T00:00:00Z".to_string(),
    };
    account.apply(&event);

    events.append(account_id, vec![event])?;
    repo.save(account)?;

    Ok(())
}
