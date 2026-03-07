-- | Example: Rust CQRS + Event Sourcing — Bank Account Service
--
-- Demonstrates plat-hs with Ext.CQRS, Ext.Events, Ext.DDD, Ext.Flow.
-- Target language: Rust
module Main where

import Plat.Core
import Plat.Check
import Plat.Generate.Mermaid   (renderMermaid)
import Plat.Generate.Markdown  (renderMarkdown)
import Plat.Ext.DDD            (dddRules)

import qualified Data.Text.IO as TIO

import Arch.Layers
import qualified Arch.Domain
import qualified Arch.Port
import qualified Arch.Command
import qualified Arch.Query
import qualified Arch.Flow
import qualified Arch.Infra

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------

wiring :: Decl 'Compose
wiring = compose "BankAccountWiring" $ do
  bind Arch.Port.accountRepo    Arch.Infra.pgAccountRepo
  bind Arch.Port.eventStore     Arch.Infra.pgEventStore
  bind Arch.Port.statementStore Arch.Infra.pgStatementStore

  -- Commands
  entry Arch.Command.openAccount
  entry Arch.Command.depositMoney
  entry Arch.Command.withdrawMoney
  entry Arch.Command.closeAccount
  entry Arch.Command.freezeAccount
  entry Arch.Command.unfreezeAccount
  entry Arch.Flow.transferMoney

  -- Queries
  entry Arch.Query.getBalance
  entry Arch.Query.getHistory_
  entry Arch.Query.getStatement
  entry Arch.Query.listAccounts

  -- Handlers
  entry Arch.Flow.onDeposited
  entry Arch.Flow.onWithdrawn
  entry Arch.Flow.onAccountClosed
  entry Arch.Flow.onInterestAccrued

----------------------------------------------------------------------
-- Architecture
----------------------------------------------------------------------

architecture :: Architecture
architecture = arch "bank-account-service" $ do
  useLayers [dom, app, infra]
  registerType "Uuid"
  Arch.Domain.declareAll
  Arch.Port.declareAll
  Arch.Command.declareAll
  Arch.Query.declareAll
  Arch.Flow.declareAll
  Arch.Infra.declareAll
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
