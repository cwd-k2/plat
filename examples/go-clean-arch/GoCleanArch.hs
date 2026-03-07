-- | Example: Go Clean Architecture — Order Management Service
--
-- Demonstrates plat-hs with Ext.CleanArch, Ext.DDD, Ext.Http presets.
-- Target language: Go
module Main where

import Plat.Core
import Plat.Check
import Plat.Generate.Mermaid   (renderMermaid)
import Plat.Generate.Markdown  (renderMarkdown)
import Plat.Ext.CleanArch      (cleanArchLayers, wire)

import qualified Data.Text
import qualified Data.Text.IO as TIO
import qualified Plat.Target.Go as Go
import Plat.Verify.Manifest (manifest, renderManifest)
import Plat.Verify.DepRules (depPolicy, renderDepMatrix)

import qualified Arch.Shared
import qualified Arch.Order
import qualified Arch.Customer
import qualified Arch.Catalog
import qualified Arch.Payment

architecture :: Architecture
architecture = arch "order-service" $ do
  useLayers cleanArchLayers
  registerType "UUID"
  Arch.Shared.declareAll
  Arch.Order.declareAll
  Arch.Customer.declareAll
  Arch.Catalog.declareAll
  Arch.Payment.declareAll
  declare wiring

wiring :: Decl 'Compose
wiring = wire "OrderServiceWiring" $ do
  bind Arch.Order.orderRepo       Arch.Order.pgOrderRepo
  bind Arch.Payment.paymentGateway Arch.Payment.stripePayment
  bind Arch.Order.notifier        Arch.Order.emailNotifier
  bind Arch.Customer.customerRepo Arch.Customer.pgCustomerRepo
  bind Arch.Catalog.productRepo   Arch.Catalog.pgProductRepo
  bind Arch.Catalog.inventoryChecker Arch.Catalog.stubInventory
  entry Arch.Order.orderController

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------

main :: IO ()
main = do
  putStrLn "=== Go Clean Architecture: Order Service ==="
  putStrLn ""

  -- Validation
  let checkResult = check architecture
  TIO.putStrLn $ prettyCheck checkResult
  putStrLn ""

  -- Markdown
  putStrLn "--- Markdown ---"
  TIO.putStrLn $ renderMarkdown architecture
  putStrLn ""

  -- Mermaid
  putStrLn "--- Mermaid ---"
  TIO.putStrLn $ renderMermaid architecture
  putStrLn ""

  -- Go skeleton
  let goCfg = (Go.defaultConfig "github.com/example/order-service")
        { Go.goLayerPkg = mempty  -- use layer names as-is
        , Go.goTypeMap  = mempty
        }
  putStrLn "--- Go Skeleton ---"
  mapM_ (\(fp, content) -> do
    putStrLn $ ">> " ++ fp
    TIO.putStrLn content
    ) (Go.skeleton goCfg architecture)

  -- Go verify
  putStrLn "--- Go Verify ---"
  mapM_ (\(fp, content) -> do
    putStrLn $ ">> " ++ fp
    TIO.putStrLn content
    ) (Go.verify goCfg architecture)

  -- Dependency matrix
  putStrLn "--- Dependency Matrix ---"
  TIO.putStrLn $ renderDepMatrix (depPolicy architecture)

  -- Manifest (first 30 lines)
  putStrLn "--- Manifest (excerpt) ---"
  let mText = renderManifest (manifest architecture)
  mapM_ TIO.putStrLn (take 30 (Data.Text.lines mText))
  putStrLn "..."
