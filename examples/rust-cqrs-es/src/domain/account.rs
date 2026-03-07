use std::fmt;

use super::event::DomainEvent;

/// Value object: monetary amount.
#[derive(Debug, Clone, PartialEq)]
pub struct Money {
    pub amount: f64,
    pub currency: String,
}

impl Money {
    pub fn new(amount: f64, currency: &str) -> Self {
        Self {
            amount,
            currency: currency.to_string(),
        }
    }

    pub fn zero(currency: &str) -> Self {
        Self::new(0.0, currency)
    }
}

impl fmt::Display for Money {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:.2} {}", self.amount, self.currency)
    }
}

/// Value object: account identifier.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct AccountId(pub String);

impl fmt::Display for AccountId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// Aggregate root.
/// Invariant: nonNegativeBalance — balance.amount >= 0
#[derive(Debug, Clone)]
pub struct Account {
    pub id: AccountId,
    pub owner: String,
    pub balance: Money,
    pub status: String,
    version: u64,
}

impl Account {
    pub fn new(id: AccountId, owner: &str, currency: &str) -> Self {
        Self {
            id,
            owner: owner.to_string(),
            balance: Money::zero(currency),
            status: "active".to_string(),
            version: 0,
        }
    }

    pub fn version(&self) -> u64 {
        self.version
    }

    /// Apply a domain event to update state.
    pub fn apply(&mut self, event: &DomainEvent) {
        match event {
            DomainEvent::AccountOpened { owner, .. } => {
                self.owner = owner.clone();
                self.status = "active".to_string();
            }
            DomainEvent::MoneyDeposited { amount, .. } => {
                self.balance.amount += amount.amount;
            }
            DomainEvent::MoneyWithdrawn { amount, .. } => {
                self.balance.amount -= amount.amount;
            }
            DomainEvent::TransferCompleted { .. } => {
                // Transfer events are applied to individual accounts
                // via MoneyDeposited/MoneyWithdrawn.
            }
            DomainEvent::AccountClosed { .. } => {
                self.status = "closed".to_string();
            }
            DomainEvent::AccountFrozen { .. } => {
                self.status = "frozen".to_string();
            }
            DomainEvent::AccountUnfrozen { .. } => {
                self.status = "active".to_string();
            }
            DomainEvent::InterestAccrued { amount, .. } => {
                self.balance.amount += amount.amount;
            }
        }
        self.version += 1;
    }

    /// Validate aggregate invariants.
    pub fn validate(&self) -> Result<(), String> {
        if self.balance.amount < 0.0 {
            return Err(format!(
                "invariant violated: balance must be non-negative, got {}",
                self.balance
            ));
        }
        Ok(())
    }
}
