use crate::domain::account::{AccountId, Money};
use crate::domain::event::DomainEvent;
use crate::infrastructure::{AccountRepository, EventStore};

/// Corresponds to: command WithdrawMoney : application
///   needs AccountRepository, EventStore
///   emit MoneyWithdrawn
pub fn execute(
    repo: &mut impl AccountRepository,
    events: &mut impl EventStore,
    account_id: &AccountId,
    amount: Money,
) -> Result<Money, String> {
    let account = repo.load(account_id)?;

    if account.balance.amount < amount.amount {
        return Err(format!(
            "insufficient funds: balance={}, requested={}",
            account.balance, amount
        ));
    }

    let new_balance = Money::new(
        account.balance.amount - amount.amount,
        &account.balance.currency,
    );

    let event = DomainEvent::MoneyWithdrawn {
        account_id: account_id.clone(),
        amount,
        balance: new_balance.clone(),
    };

    let mut account = account;
    account.apply(&event);
    account.validate()?;

    events.append(account_id, vec![event])?;
    repo.save(account)?;

    Ok(new_balance)
}
