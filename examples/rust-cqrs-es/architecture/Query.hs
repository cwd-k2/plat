module Query (getBalance, getHistory_, getStatement, listAccounts, declareAll) where

import Plat.Core
import Plat.Ext.CQRS

import Layers
import Domain (accountId, money, account, statement)
import Port (accountRepo, eventStore, statementStore)

getBalance :: Decl 'Operation
getBalance = query "GetBalance" app $ do
  input  "accountId" (ref accountId)
  output "balance"   (ref money)
  output "err"       error_
  needs accountRepo

getHistory_ :: Decl 'Operation
getHistory_ = query "GetTransactionHistory" app $ do
  input  "accountId" (ref accountId)
  output "events"    (list any_)
  output "err"       error_
  needs eventStore

getStatement :: Decl 'Operation
getStatement = query "GetStatement" app $ do
  input  "accountId"   (ref accountId)
  input  "periodStart" dateTime
  input  "periodEnd"   dateTime
  output "statement"   (ref statement)
  output "err"         error_
  needs eventStore
  needs statementStore

listAccounts :: Decl 'Operation
listAccounts = query "ListAccounts" app $ do
  output "accounts" (listOf account)
  output "err"      error_
  needs accountRepo

declareAll :: ArchBuilder ()
declareAll = declares
  [ decl getBalance
  , decl getHistory_
  , decl getStatement
  , decl listAccounts
  ]
