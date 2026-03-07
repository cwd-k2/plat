use crate::domain::account::AccountId;
use crate::domain::event::DomainEvent;
use crate::infrastructure::{AccountRepository, EventStore};

/// Corresponds to: command FreezeAccount : application
///   needs AccountRepository, EventStore
///   emit AccountFrozen
pub fn execute(
    repo: &mut impl AccountRepository,
    events: &mut impl EventStore,
    account_id: &AccountId,
    reason: &str,
) -> Result<(), String> {
    let mut account = repo.load(account_id)?;

    if account.status != "active" {
        return Err(format!("cannot freeze account with status '{}'", account.status));
    }

    let event = DomainEvent::AccountFrozen {
        account_id: account_id.clone(),
        frozen_at: "2026-03-07T00:00:00Z".to_string(),
        reason: reason.to_string(),
    };
    account.apply(&event);

    events.append(account_id, vec![event])?;
    repo.save(account)?;

    Ok(())
}
