module Arch.Domain (
  money, accountId, account, withdrawalPolicy,
  accountOpened, moneyDeposited, moneyWithdrawn, transferCompleted,
  accountClosed, accountFrozen, accountUnfrozen, interestAccrued,
  statementEntry, statement,
  declareAll
) where

import Plat.Core
import Plat.Ext.DDD
import Plat.Ext.Events
import Plat.Ext.Flow (policy)

import Arch.Layers

----------------------------------------------------------------------
-- Value Objects
----------------------------------------------------------------------

money :: Decl 'Model
money = value "Money" dom $ do
  field "amount"   decimal
  field "currency" string

accountId :: Decl 'Model
accountId = value "AccountId" dom $ do
  field "value" (customType "Uuid")

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

accountOpened :: Decl 'Model
accountOpened = event "AccountOpened" dom $ do
  field "accountId" (ref accountId)
  field "owner"     string
  field "openedAt"  dateTime

moneyDeposited :: Decl 'Model
moneyDeposited = event "MoneyDeposited" dom $ do
  field "accountId" (ref accountId)
  field "amount"    (ref money)
  field "balance"   (ref money)

moneyWithdrawn :: Decl 'Model
moneyWithdrawn = event "MoneyWithdrawn" dom $ do
  field "accountId" (ref accountId)
  field "amount"    (ref money)
  field "balance"   (ref money)

transferCompleted :: Decl 'Model
transferCompleted = event "TransferCompleted" dom $ do
  field "from"   (ref accountId)
  field "to"     (ref accountId)
  field "amount" (ref money)

accountClosed :: Decl 'Model
accountClosed = event "AccountClosed" dom $ do
  field "accountId" (ref accountId)
  field "closedAt"  dateTime
  field "reason"    string

accountFrozen :: Decl 'Model
accountFrozen = event "AccountFrozen" dom $ do
  field "accountId" (ref accountId)
  field "frozenAt"  dateTime
  field "reason"    string

accountUnfrozen :: Decl 'Model
accountUnfrozen = event "AccountUnfrozen" dom $ do
  field "accountId" (ref accountId)
  field "unfrozenAt" dateTime

interestAccrued :: Decl 'Model
interestAccrued = event "InterestAccrued" dom $ do
  field "accountId" (ref accountId)
  field "amount"    (ref money)
  field "balance"   (ref money)
  field "rate"      decimal

----------------------------------------------------------------------
-- Aggregate
----------------------------------------------------------------------

account :: Decl 'Model
account = aggregate "Account" dom $ do
  field "id"      (ref accountId)
  field "owner"   string
  field "balance" (ref money)
  field "status"  string
  invariant "nonNegativeBalance" "balance.amount >= 0"
  apply_ accountOpened
  apply_ moneyDeposited
  apply_ moneyWithdrawn
  apply_ accountClosed
  apply_ accountFrozen
  apply_ accountUnfrozen
  apply_ interestAccrued

----------------------------------------------------------------------
-- Value Objects (Statements)
----------------------------------------------------------------------

statementEntry :: Decl 'Model
statementEntry = value "StatementEntry" dom $ do
  field "date"           dateTime
  field "description"    string
  field "amount"         (ref money)
  field "runningBalance" (ref money)

statement :: Decl 'Model
statement = value "Statement" dom $ do
  field "accountId"      (ref accountId)
  field "periodStart"    dateTime
  field "periodEnd"      dateTime
  field "openingBalance" (ref money)
  field "closingBalance" (ref money)
  field "entries"        (list (ref statementEntry))

----------------------------------------------------------------------
-- Policies
----------------------------------------------------------------------

withdrawalPolicy :: Decl 'Model
withdrawalPolicy = policy "WithdrawalPolicy" dom $ do
  field "dailyLimit"       (ref money)
  field "singleTxLimit"    (ref money)

----------------------------------------------------------------------
-- declareAll
----------------------------------------------------------------------

declareAll :: ArchBuilder ()
declareAll = do
  declare money
  declare accountId
  declare account
  declare withdrawalPolicy
  declare statementEntry
  declare statement
  declare accountOpened
  declare moneyDeposited
  declare moneyWithdrawn
  declare transferCompleted
  declare accountClosed
  declare accountFrozen
  declare accountUnfrozen
  declare interestAccrued
