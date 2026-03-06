use crate::domain::account::{AccountId, Money};
use crate::domain::event::DomainEvent;
use crate::infrastructure::{AccountRepository, EventStore};

/// Corresponds to: command DepositMoney : application
///   needs AccountRepository, EventStore
///   emit MoneyDeposited
pub fn execute(
    repo: &mut impl AccountRepository,
    events: &mut impl EventStore,
    account_id: &AccountId,
    amount: Money,
) -> Result<Money, String> {
    let mut account = repo.load(account_id)?;

    let new_balance = Money::new(
        account.balance.amount + amount.amount,
        &account.balance.currency,
    );

    let event = DomainEvent::MoneyDeposited {
        account_id: account_id.clone(),
        amount,
        balance: new_balance.clone(),
    };
    account.apply(&event);
    account.validate()?;

    events.append(account_id, vec![event])?;
    repo.save(account)?;

    Ok(new_balance)
}
