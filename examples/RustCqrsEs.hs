-- | Example: Rust CQRS + Event Sourcing — Bank Account Service
--
-- Demonstrates plat-hs with Ext.CQRS, Ext.Events, Ext.DDD, Ext.Flow.
-- Target language: Rust
module Main where

import qualified Data.Text.IO as TIO

import Plat.Core
import Plat.Check
import Plat.Generate.Plat    (render)
import Plat.Generate.Mermaid (renderMermaid)
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
  meta "plat-flow:kind" "projection"

onWithdrawn :: Decl 'Operation
onWithdrawn = on_ "OnMoneyWithdrawn" moneyWithdrawn app $ do
  output "err" error_
  meta "plat-flow:kind" "projection"

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

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------

wiring :: Decl 'Compose
wiring = compose "BankAccountWiring" $ do
  bind accountRepo pgAccountRepo
  bind eventStore  pgEventStore

  -- Commands
  entry openAccount
  entry depositMoney
  entry withdrawMoney
  entry transferMoney

  -- Queries
  entry getBalance
  entry getHistory_

  -- Handlers
  entry onDeposited
  entry onWithdrawn

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

  -- Events
  declare accountOpened
  declare moneyDeposited
  declare moneyWithdrawn
  declare transferCompleted

  -- Ports
  declare accountRepo
  declare eventStore

  -- Commands
  declare openAccount
  declare depositMoney
  declare withdrawMoney

  -- Queries
  declare getBalance
  declare getHistory_

  -- Flow
  declare transferMoney

  -- Event handlers
  declare onDeposited
  declare onWithdrawn

  -- Infrastructure
  declare pgEventStore
  declare pgAccountRepo

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

  -- .plat output
  putStrLn "--- .plat ---"
  TIO.putStrLn $ render architecture
  putStrLn ""

  -- Mermaid
  putStrLn "--- Mermaid ---"
  TIO.putStrLn $ renderMermaid architecture
