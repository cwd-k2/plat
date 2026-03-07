-- | Example: Go Feature-Sliced Clean Architecture — E-Commerce Platform
--
-- Demonstrates plat-hs with Ext.CleanArch + Ext.Modules.
-- Same CA layer constraints, but source code organized by feature.
--
-- Directory layout (feature-first):
--   shared/domain/    — shared value objects
--   order/domain/     — order models
--   order/port/       — order ports
--   order/usecase/    — order use cases
--   order/adapter/    — order adapters
--   catalog/domain/   — catalog models
--   ...
module Main where

import Plat.Core
import Plat.Check
import Plat.Ext.CleanArch      (cleanArchLayers, wire)

import Data.Text (Text)
import qualified Data.Text.IO as TIO
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>), takeDirectory)

import Plat.Verify.Manifest (manifest, renderManifest)

import qualified Shared
import qualified Order
import qualified Catalog
import qualified Payment

architecture :: Architecture
architecture = arch "ecommerce-platform" $ do
  useLayers cleanArchLayers
  registerType "UUID"
  Shared.declareAll
  Order.declareAll
  Catalog.declareAll
  Payment.declareAll
  declare wiring

wiring :: Decl 'Compose
wiring = wire "ECommerceWiring" $ do
  bind Order.orderRepo       Order.memOrderRepo
  bind Catalog.productRepo   Catalog.memProductRepo
  bind Catalog.productSearch  Catalog.memProductSearch
  bind Payment.paymentGateway Payment.stubPaymentGateway
  bind Payment.paymentRepo    Payment.memPaymentRepo
  entry Order.placeOrder
  entry Order.cancelOrder
  entry Order.getOrder
  entry Order.listOrders
  entry Catalog.createProduct
  entry Catalog.getProduct
  entry Catalog.searchProducts
  entry Payment.processPayment
  entry Payment.getPayment

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
  let dir = "examples/go-feature-sliced/dist"
  putStrLn "=== Go Feature-Sliced CA: E-Commerce Platform ==="

  out (dir </> "check.txt")         (prettyCheck (check architecture))
  out (dir </> "manifest.json")     (renderManifest (manifest architecture))

  putStrLn "done."
