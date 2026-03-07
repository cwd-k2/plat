-- | Example: Rust CQRS + Event Sourcing — Bank Account Service
--
-- Demonstrates plat-hs with Ext.CQRS, Ext.Events, Ext.DDD, Ext.Flow.
-- Target language: Rust
module Main where

import qualified Data.Text.IO as TIO

import Plat.Core
import Plat.Check
import Plat.Generate.Mermaid   (renderMermaid)
import Plat.Generate.Markdown  (renderMarkdown)
import Plat.Ext.DDD
import Plat.Ext.CQRS
import Plat.Ext.Events
import Plat.Ext.Flow

----------------------------------------------------------------------
-- Layers
----------------------------------------------------------------------

dom :: LayerDef
dom = layer "domain"

app :: LayerDef
app = layer "application" `depends` [dom]

infra :: LayerDef
infra = layer "infrastructure" `depends` [dom, app]

----------------------------------------------------------------------
-- Domain: Value Objects
----------------------------------------------------------------------

money :: Decl 'Model
money = value "Money" dom $ do
  field "amount"   decimal
  field "currency" string

accountId :: Decl 'Model
accountId = value "AccountId" dom $ do
  field "value" (customType "Uuid")

----------------------------------------------------------------------
-- Domain: Events
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
-- Domain: Aggregate
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
-- Domain: Value Objects (Statements)
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
-- Domain: Policies
----------------------------------------------------------------------

withdrawalPolicy :: Decl 'Model
withdrawalPolicy = policy "WithdrawalPolicy" dom $ do
  field "dailyLimit"       (ref money)
  field "singleTxLimit"    (ref money)

----------------------------------------------------------------------
-- Ports
----------------------------------------------------------------------

accountRepo :: Decl 'Boundary
accountRepo = boundary "AccountRepository" dom $ do
  op "load"  ["id" .: ref accountId] ["account" .: ref account, "err" .: error_]
  op "save"  ["account" .: ref account] ["err" .: error_]

eventStore :: Decl 'Boundary
eventStore = boundary "EventStore" dom $ do
  op "append"  ["id" .: ref accountId, "events" .: list any_]  ["err" .: error_]
  op "loadAll" ["id" .: ref accountId] ["events" .: list any_, "err" .: error_]

statementStore :: Decl 'Boundary
statementStore = boundary "StatementStore" dom $ do
  op "save"          ["statement" .: ref statement]   ["err" .: error_]
  op "findByAccount" ["accountId" .: ref accountId]   ["statements" .: list (ref statement), "err" .: error_]

----------------------------------------------------------------------
-- Commands (write side)
----------------------------------------------------------------------

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

----------------------------------------------------------------------
-- Queries (read side)
----------------------------------------------------------------------

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
  output "accounts" (list (ref account))
  output "err"      error_
  needs accountRepo

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
-- Infrastructure Adapters
----------------------------------------------------------------------

pgEventStore :: Decl 'Adapter
pgEventStore = adapter "PostgresEventStore" infra $ do
  implements eventStore
  inject "pool" (ext "sqlx::PgPool")

pgAccountRepo :: Decl 'Adapter
pgAccountRepo = adapter "PostgresAccountRepo" infra $ do
  implements accountRepo
  inject "pool" (ext "sqlx::PgPool")

pgStatementStore :: Decl 'Adapter
pgStatementStore = adapter "PostgresStatementStore" infra $ do
  implements statementStore
  inject "pool" (ext "sqlx::PgPool")

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------

wiring :: Decl 'Compose
wiring = compose "BankAccountWiring" $ do
  bind accountRepo    pgAccountRepo
  bind eventStore     pgEventStore
  bind statementStore pgStatementStore

  -- Commands
  entry openAccount
  entry depositMoney
  entry withdrawMoney
  entry closeAccount
  entry freezeAccount
  entry unfreezeAccount
  entry transferMoney

  -- Queries
  entry getBalance
  entry getHistory_
  entry getStatement
  entry listAccounts

  -- Handlers
  entry onDeposited
  entry onWithdrawn
  entry onAccountClosed
  entry onInterestAccrued

----------------------------------------------------------------------
-- Architecture
----------------------------------------------------------------------

architecture :: Architecture
architecture = arch "bank-account-service" $ do
  useLayers [dom, app, infra]
  registerType "Uuid"

  -- Domain models
  declare money
  declare accountId
  declare account
  declare withdrawalPolicy
  declare statementEntry
  declare statement

  -- Events
  declare accountOpened
  declare moneyDeposited
  declare moneyWithdrawn
  declare transferCompleted
  declare accountClosed
  declare accountFrozen
  declare accountUnfrozen
  declare interestAccrued

  -- Ports
  declare accountRepo
  declare eventStore
  declare statementStore

  -- Commands
  declare openAccount
  declare depositMoney
  declare withdrawMoney
  declare closeAccount
  declare freezeAccount
  declare unfreezeAccount

  -- Queries
  declare getBalance
  declare getHistory_
  declare getStatement
  declare listAccounts

  -- Flow
  declare transferMoney

  -- Event handlers
  declare onDeposited
  declare onWithdrawn
  declare onAccountClosed
  declare onInterestAccrued

  -- Infrastructure
  declare pgEventStore
  declare pgAccountRepo
  declare pgStatementStore

  -- Wiring
  declare wiring

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------

main :: IO ()
main = do
  putStrLn "=== Rust CQRS + Event Sourcing: Bank Account Service ==="
  putStrLn ""

  -- Validation (core + DDD rules)
  let checkResult = checkWith (coreRules ++ dddRules) architecture
  TIO.putStrLn $ prettyCheck checkResult
  putStrLn ""

  -- Markdown
  putStrLn "--- Markdown ---"
  TIO.putStrLn $ renderMarkdown architecture
  putStrLn ""

  -- Mermaid
  putStrLn "--- Mermaid ---"
  TIO.putStrLn $ renderMermaid architecture
