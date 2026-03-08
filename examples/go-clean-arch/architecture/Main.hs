-- | Example: Go Clean Architecture — Order Management Service
--
-- Demonstrates plat-hs with Ext.CleanArch, Ext.DDD, Ext.Http presets.
-- Target language: Go
module Main where

import Plat.Core
import Plat.Check
import Plat.Ext.CleanArch      (cleanArchLayers, wire)

import Data.Text (Text)
import qualified Data.Text.IO as TIO
import Plat.Verify.Manifest (manifest, renderManifest)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>), takeDirectory)

import qualified Shared
import qualified Order
import qualified Customer
import qualified Catalog
import qualified Payment

-- | アーキテクチャ定義。各モジュールの declareAll を束ねて単一の Architecture を構築する。
--
-- arch は ArchBuilder モナドを走らせて Architecture 値を生成する。
-- useLayers でレイヤー依存方向を定義し、registerType で
-- カスタム型を登録する (W002 未定義型検査で既知型として扱われる)。
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

  -- Manifest (consumed by Rust tools: plat-verify, plat-doc, plat-skeleton, etc.)
  out (dir </> "manifest.json") (renderManifest (manifest architecture))

  putStrLn "done."
