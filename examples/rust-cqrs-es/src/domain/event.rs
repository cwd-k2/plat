use super::account::{AccountId, Money};

/// Domain events for the bank account aggregate.
#[derive(Debug, Clone)]
pub enum DomainEvent {
    /// Corresponds to: model AccountOpened (event)
    AccountOpened {
        account_id: AccountId,
        owner: String,
        opened_at: String,
    },

    /// Corresponds to: model MoneyDeposited (event)
    MoneyDeposited {
        account_id: AccountId,
        amount: Money,
        balance: Money,
    },

    /// Corresponds to: model MoneyWithdrawn (event)
    MoneyWithdrawn {
        account_id: AccountId,
        amount: Money,
        balance: Money,
    },

    /// Corresponds to: model TransferCompleted (event)
    TransferCompleted {
        from: AccountId,
        to: AccountId,
        amount: Money,
    },
}

impl DomainEvent {
    pub fn event_type(&self) -> &'static str {
        match self {
            Self::AccountOpened { .. } => "AccountOpened",
            Self::MoneyDeposited { .. } => "MoneyDeposited",
            Self::MoneyWithdrawn { .. } => "MoneyWithdrawn",
            Self::TransferCompleted { .. } => "TransferCompleted",
        }
    }
}
