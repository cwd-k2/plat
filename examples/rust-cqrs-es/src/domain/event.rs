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

    /// Corresponds to: model AccountClosed (event)
    AccountClosed {
        account_id: AccountId,
        closed_at: String,
        reason: String,
    },

    /// Corresponds to: model AccountFrozen (event)
    AccountFrozen {
        account_id: AccountId,
        frozen_at: String,
        reason: String,
    },

    /// Corresponds to: model AccountUnfrozen (event)
    AccountUnfrozen {
        account_id: AccountId,
        unfrozen_at: String,
    },

    /// Corresponds to: model InterestAccrued (event)
    InterestAccrued {
        account_id: AccountId,
        amount: Money,
        balance: Money,
        rate: f64,
    },
}

impl DomainEvent {
    pub fn event_type(&self) -> &'static str {
        match self {
            Self::AccountOpened { .. } => "AccountOpened",
            Self::MoneyDeposited { .. } => "MoneyDeposited",
            Self::MoneyWithdrawn { .. } => "MoneyWithdrawn",
            Self::TransferCompleted { .. } => "TransferCompleted",
            Self::AccountClosed { .. } => "AccountClosed",
            Self::AccountFrozen { .. } => "AccountFrozen",
            Self::AccountUnfrozen { .. } => "AccountUnfrozen",
            Self::InterestAccrued { .. } => "InterestAccrued",
        }
    }
}
