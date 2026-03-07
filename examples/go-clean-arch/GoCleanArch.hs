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

import Data.Text (Text)
import qualified Data.Text.IO as TIO
import qualified Plat.Target.Go as Go
import Plat.Verify.Manifest (manifest, renderManifest)
import Plat.Verify.DepRules (depPolicy, renderDepMatrix)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>), takeDirectory)

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

out :: FilePath -> Text -> IO ()
out fp content = do
  createDirectoryIfMissing True (takeDirectory fp)
  TIO.writeFile fp content
  putStrLn $ "  wrote " ++ fp

main :: IO ()
main = do
  let dir = "dist"
  putStrLn "=== Go Clean Architecture: Order Service ==="

  -- Validation
  let checkResult = check architecture
  out (dir </> "check.txt") (prettyCheck checkResult)

  -- Markdown
  out (dir </> "architecture.md") (renderMarkdown architecture)

  -- Mermaid
  out (dir </> "architecture.mmd") (renderMermaid architecture)

  -- Dependency matrix
  out (dir </> "dep-matrix.txt") (renderDepMatrix (depPolicy architecture))

  -- Manifest
  out (dir </> "manifest.toml") (renderManifest (manifest architecture))

  -- Go skeleton
  let goCfg = (Go.defaultConfig "github.com/example/order-service")
        { Go.goLayerPkg = mempty
        , Go.goTypeMap  = mempty
        }
  mapM_ (\(fp, content) -> out (dir </> "skeleton" </> fp) content)
        (Go.skeleton goCfg architecture)

  -- Go verify
  mapM_ (\(fp, content) -> out (dir </> "verify" </> fp) content)
        (Go.verify goCfg architecture)

  putStrLn "done."
