module Flow (transferMoney, onDeposited, onWithdrawn, onAccountClosed, onInterestAccrued, declareAll) where

import Plat.Core
import Plat.Ext.Events
import Plat.Ext.Flow

import Layers
import Domain (accountId, money, moneyDeposited, moneyWithdrawn, accountClosed, interestAccrued, transferCompleted)
import Port (accountRepo, eventStore)

----------------------------------------------------------------------
-- Flow: Transfer (saga / orchestration)
----------------------------------------------------------------------

transferMoney :: Decl 'Operation
transferMoney = step "TransferMoney" app $ do
  input  "from"   (ref accountId)
  input  "to"     (ref accountId)
  input  "amount" (ref money)
  output "err"    error_
  needs accountRepo
  needs eventStore
  guard_ "sameAccount"   "from != to"
  guard_ "positiveAmount" "amount.amount > 0"
  emit moneyWithdrawn
  emit moneyDeposited
  emit transferCompleted

----------------------------------------------------------------------
-- Event Handlers (projections / reactions)
----------------------------------------------------------------------

onDeposited :: Decl 'Operation
onDeposited = on_ "OnMoneyDeposited" moneyDeposited app $ do
  output "err" error_
  tagAs flowProjection

onWithdrawn :: Decl 'Operation
onWithdrawn = on_ "OnMoneyWithdrawn" moneyWithdrawn app $ do
  output "err" error_
  tagAs flowProjection

onAccountClosed :: Decl 'Operation
onAccountClosed = on_ "OnAccountClosed" accountClosed app $ do
  output "err" error_
  tagAs flowProjection

onInterestAccrued :: Decl 'Operation
onInterestAccrued = on_ "OnInterestAccrued" interestAccrued app $ do
  output "err" error_
  tagAs flowProjection

----------------------------------------------------------------------
-- declareAll
----------------------------------------------------------------------

declareAll :: ArchBuilder ()
declareAll = declares
  [ decl transferMoney
  , decl onDeposited
  , decl onWithdrawn
  , decl onAccountClosed
  , decl onInterestAccrued
  ]
