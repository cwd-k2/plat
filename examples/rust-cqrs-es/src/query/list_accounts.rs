use crate::domain::account::Account;
use crate::infrastructure::AccountRepository;

/// Corresponds to: query ListAccounts : application
///   needs AccountRepository
pub fn execute(repo: &impl AccountRepository) -> Result<Vec<Account>, String> {
    repo.list_all()
}
