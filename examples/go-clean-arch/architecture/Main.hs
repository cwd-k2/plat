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

import qualified Shared
import qualified Order
import qualified Customer
import qualified Catalog
import qualified Payment

architecture :: Architecture
architecture = arch "order-service" $ do
  useLayers cleanArchLayers
  registerType "UUID"
  Shared.declareAll
  Order.declareAll
  Customer.declareAll
  Catalog.declareAll
  Payment.declareAll
  declare wiring

wiring :: Decl 'Compose
wiring = wire "OrderServiceWiring" $ do
  bind Order.orderRepo       Order.pgOrderRepo
  bind Payment.paymentGateway Payment.stripePayment
  bind Order.notifier        Order.emailNotifier
  bind Customer.customerRepo Customer.pgCustomerRepo
  bind Catalog.productRepo   Catalog.pgProductRepo
  bind Catalog.inventoryChecker Catalog.stubInventory
  entry Order.orderController

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
  let dir = "examples/go-clean-arch/dist"
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
