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
import Plat.Generate.Mermaid   (renderMermaid)
import Plat.Generate.Markdown  (renderMarkdown)
import Plat.Ext.CleanArch      (cleanArchLayers, wire)

import qualified Data.Text.IO as TIO

import Plat.Verify.Manifest (manifest, renderManifest)

import qualified Arch.Shared
import qualified Arch.Order
import qualified Arch.Catalog
import qualified Arch.Payment

architecture :: Architecture
architecture = arch "ecommerce-platform" $ do
  useLayers cleanArchLayers
  registerType "UUID"
  Arch.Shared.declareAll
  Arch.Order.declareAll
  Arch.Catalog.declareAll
  Arch.Payment.declareAll
  declare wiring

wiring :: Decl 'Compose
wiring = wire "ECommerceWiring" $ do
  bind Arch.Order.orderRepo       Arch.Order.memOrderRepo
  bind Arch.Catalog.productRepo   Arch.Catalog.memProductRepo
  bind Arch.Catalog.productSearch  Arch.Catalog.memProductSearch
  bind Arch.Payment.paymentGateway Arch.Payment.stubPaymentGateway
  bind Arch.Payment.paymentRepo    Arch.Payment.memPaymentRepo
  entry Arch.Order.placeOrder
  entry Arch.Order.cancelOrder
  entry Arch.Order.getOrder
  entry Arch.Order.listOrders
  entry Arch.Catalog.createProduct
  entry Arch.Catalog.getProduct
  entry Arch.Catalog.searchProducts
  entry Arch.Payment.processPayment
  entry Arch.Payment.getPayment

main :: IO ()
main = do
  putStrLn "=== Go Feature-Sliced CA: E-Commerce Platform ==="
  putStrLn ""

  let checkResult = check architecture
  TIO.putStrLn $ prettyCheck checkResult
  putStrLn ""

  putStrLn "--- Mermaid ---"
  TIO.putStrLn $ renderMermaid architecture
  putStrLn ""

  putStrLn "--- Markdown ---"
  TIO.putStrLn $ renderMarkdown architecture

  -- Manifest (for plat-verify)
  TIO.putStrLn $ renderManifest (manifest architecture)
