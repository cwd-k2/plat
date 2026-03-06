use crate::domain::account::{AccountId, Money};
use crate::infrastructure::AccountRepository;

/// Corresponds to: query GetBalance : application
///   needs AccountRepository
pub fn execute(repo: &impl AccountRepository, account_id: &AccountId) -> Result<Money, String> {
    let account = repo.load(account_id)?;
    Ok(account.balance.clone())
}
