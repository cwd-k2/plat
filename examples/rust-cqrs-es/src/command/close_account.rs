use crate::domain::account::AccountId;
use crate::domain::event::DomainEvent;
use crate::infrastructure::{AccountRepository, EventStore};

/// Corresponds to: command CloseAccount : application
///   needs AccountRepository, EventStore
///   emit AccountClosed
pub fn execute(
    repo: &mut impl AccountRepository,
    events: &mut impl EventStore,
    account_id: &AccountId,
    reason: &str,
) -> Result<(), String> {
    let mut account = repo.load(account_id)?;

    if account.status == "closed" {
        return Err("account is already closed".to_string());
    }

    let event = DomainEvent::AccountClosed {
        account_id: account_id.clone(),
        closed_at: "2026-03-07T00:00:00Z".to_string(),
        reason: reason.to_string(),
    };
    account.apply(&event);

    events.append(account_id, vec![event])?;
    repo.save(account)?;

    Ok(())
}
