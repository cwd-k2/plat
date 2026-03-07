-- | Example: Rust CQRS + Event Sourcing — Bank Account Service
--
-- Demonstrates plat-hs with Ext.CQRS, Ext.Events, Ext.DDD, Ext.Flow.
-- Target language: Rust
module Main where

import Plat.Core
import Plat.Check
import Plat.Verify.Manifest (manifest, renderManifest)
import Plat.Ext.DDD            (dddRules)

import Data.Text (Text)
import qualified Data.Text.IO as TIO
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>), takeDirectory)

import Layers
import qualified Domain
import qualified Port
import qualified Command
import qualified Query
import qualified Flow
import qualified Infra

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------

wiring :: Decl 'Compose
wiring = compose "BankAccountWiring" $ do
  bind Port.accountRepo    Infra.pgAccountRepo
  bind Port.eventStore     Infra.pgEventStore
  bind Port.statementStore Infra.pgStatementStore

  -- Commands
  entry Command.openAccount
  entry Command.depositMoney
  entry Command.withdrawMoney
  entry Command.closeAccount
  entry Command.freezeAccount
  entry Command.unfreezeAccount
  entry Flow.transferMoney

  -- Queries
  entry Query.getBalance
  entry Query.getHistory_
  entry Query.getStatement
  entry Query.listAccounts

  -- Handlers
  entry Flow.onDeposited
  entry Flow.onWithdrawn
  entry Flow.onAccountClosed
  entry Flow.onInterestAccrued

----------------------------------------------------------------------
-- Architecture
----------------------------------------------------------------------

architecture :: Architecture
architecture = arch "bank-account-service" $ do
  useLayers [dom, app, infra]
  registerType "Uuid"
  Domain.declareAll
  Port.declareAll
  Command.declareAll
  Query.declareAll
  Flow.declareAll
  Infra.declareAll
  declare wiring

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------

out :: FilePath -> Text -> IO ()
out fp content = do
  createDirectoryIfMissing True (takeDirectory fp)
  TIO.writeFile fp content
  putStrLn $ "  wrote " ++ fp

main :: IO ()
main = do
  let dir = "examples/rust-cqrs-es/dist"
  putStrLn "=== Rust CQRS + Event Sourcing: Bank Account Service ==="

  out (dir </> "check.txt")         (prettyCheck (checkWith (coreRules ++ dddRules) architecture))
  out (dir </> "manifest.json")     (renderManifest (manifest architecture))

  putStrLn "done."
