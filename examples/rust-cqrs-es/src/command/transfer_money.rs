use crate::domain::account::{AccountId, Money};
use crate::domain::event::DomainEvent;
use crate::infrastructure::{AccountRepository, EventStore};

/// Corresponds to: step TransferMoney : application (flow)
///   needs AccountRepository, EventStore
///   guard sameAccount: from != to
///   guard positiveAmount: amount.amount > 0
///   emit MoneyWithdrawn, MoneyDeposited, TransferCompleted
pub fn execute(
    repo: &mut impl AccountRepository,
    events: &mut impl EventStore,
    from: &AccountId,
    to: &AccountId,
    amount: Money,
) -> Result<(), String> {
    // Guard: sameAccount
    if from == to {
        return Err("cannot transfer to the same account".to_string());
    }
    // Guard: positiveAmount
    if amount.amount <= 0.0 {
        return Err("transfer amount must be positive".to_string());
    }

    // Withdraw from source
    let mut src = repo.load(from)?;
    if src.balance.amount < amount.amount {
        return Err(format!("insufficient funds in {}: {}", from, src.balance));
    }

    let src_balance = Money::new(src.balance.amount - amount.amount, &src.balance.currency);
    let withdraw_event = DomainEvent::MoneyWithdrawn {
        account_id: from.clone(),
        amount: amount.clone(),
        balance: src_balance,
    };
    src.apply(&withdraw_event);

    // Deposit to destination
    let mut dst = repo.load(to)?;
    let dst_balance = Money::new(dst.balance.amount + amount.amount, &dst.balance.currency);
    let deposit_event = DomainEvent::MoneyDeposited {
        account_id: to.clone(),
        amount: amount.clone(),
        balance: dst_balance,
    };
    dst.apply(&deposit_event);

    let transfer_event = DomainEvent::TransferCompleted {
        from: from.clone(),
        to: to.clone(),
        amount,
    };

    // Persist
    events.append(from, vec![withdraw_event, transfer_event.clone()])?;
    events.append(to, vec![deposit_event])?;
    repo.save(src)?;
    repo.save(dst)?;

    Ok(())
}
