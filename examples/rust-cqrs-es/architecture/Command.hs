module Command (openAccount, depositMoney, withdrawMoney, closeAccount, freezeAccount, unfreezeAccount, declareAll) where

import Plat.Core
import Plat.Ext.CQRS
import Plat.Ext.Events

import Layers
import Domain (accountId, money, accountOpened, moneyDeposited, moneyWithdrawn, accountClosed, accountFrozen, accountUnfrozen)
import Port (accountRepo, eventStore)

openAccount :: Decl 'Operation
openAccount = command "OpenAccount" app $ do
  input  "owner"     string
  output "accountId" (ref accountId)
  output "err"       error_
  needs accountRepo
  needs eventStore
  emit accountOpened

depositMoney :: Decl 'Operation
depositMoney = command "DepositMoney" app $ do
  input  "accountId" (ref accountId)
  input  "amount"    (ref money)
  output "balance"   (ref money)
  output "err"       error_
  needs accountRepo
  needs eventStore
  emit moneyDeposited

withdrawMoney :: Decl 'Operation
withdrawMoney = command "WithdrawMoney" app $ do
  input  "accountId" (ref accountId)
  input  "amount"    (ref money)
  output "balance"   (ref money)
  output "err"       error_
  needs accountRepo
  needs eventStore
  emit moneyWithdrawn

closeAccount :: Decl 'Operation
closeAccount = command "CloseAccount" app $ do
  input  "accountId" (ref accountId)
  input  "reason"    string
  output "err"       error_
  needs accountRepo
  needs eventStore
  emit accountClosed

freezeAccount :: Decl 'Operation
freezeAccount = command "FreezeAccount" app $ do
  input  "accountId" (ref accountId)
  input  "reason"    string
  output "err"       error_
  needs accountRepo
  needs eventStore
  emit accountFrozen

unfreezeAccount :: Decl 'Operation
unfreezeAccount = command "UnfreezeAccount" app $ do
  input  "accountId" (ref accountId)
  output "err"       error_
  needs accountRepo
  needs eventStore
  emit accountUnfrozen

declareAll :: ArchBuilder ()
declareAll = do
  declare openAccount
  declare depositMoney
  declare withdrawMoney
  declare closeAccount
  declare freezeAccount
  declare unfreezeAccount
