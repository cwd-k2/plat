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
import Plat.Ext.CleanArch
import Plat.Ext.DDD
import Plat.Ext.Modules

import qualified Data.Text.IO as TIO

import Plat.Verify.Manifest (manifest, renderManifest)

----------------------------------------------------------------------
-- Shared kernel (enterprise layer)
----------------------------------------------------------------------

money :: Decl 'Model
money = value "Money" enterprise $ do
  field "amount"   decimal
  field "currency" string

address :: Decl 'Model
address = value "Address" enterprise $ do
  field "street"  string
  field "city"    string
  field "country" string
  field "zip"     string

----------------------------------------------------------------------
-- Feature: Order
----------------------------------------------------------------------

-- Domain

orderStatus :: Decl 'Model
orderStatus = enum_ "OrderStatus" enterprise
  ["Pending", "Confirmed", "Shipped", "Delivered", "Cancelled"]

order :: Decl 'Model
order = aggregate "Order" enterprise $ do
  field "id"        (customType "UUID")
  field "customerId" (customType "UUID")
  field "items"     (list (ref orderItem))
  field "total"     (ref money)
  field "shipping"  (ref address)
  field "status"    (ref orderStatus)
  invariant "positiveTotal" "total.amount > 0"

orderItem :: Decl 'Model
orderItem = value "OrderItem" enterprise $ do
  field "productId" (customType "UUID")
  field "name"      string
  field "quantity"  int
  field "price"     (ref money)

-- Port

orderRepo :: Decl 'Boundary
orderRepo = port "OrderRepository" interface $ do
  op "save"     ["order" .: ref order] ["err" .: error_]
  op "findById" ["id" .: customType "UUID"] ["order" .: ref order, "err" .: error_]
  op "findAll"  [] ["orders" .: list (ref order), "err" .: error_]
  op "delete"   ["id" .: customType "UUID"] ["err" .: error_]

-- Use cases

placeOrder :: Decl 'Operation
placeOrder = usecase "PlaceOrder" application $ do
  input  "order"       (ref order)
  input  "paymentToken" string
  output "orderId"     (customType "UUID")
  output "err"         error_
  needs orderRepo
  needs paymentGateway

cancelOrder :: Decl 'Operation
cancelOrder = usecase "CancelOrder" application $ do
  input  "orderId" (customType "UUID")
  output "err"     error_
  needs orderRepo

getOrder :: Decl 'Operation
getOrder = usecase "GetOrder" application $ do
  input  "orderId" (customType "UUID")
  output "order"   (ref order)
  output "err"     error_
  needs orderRepo

listOrders :: Decl 'Operation
listOrders = usecase "ListOrders" application $ do
  output "orders" (list (ref order))
  output "err"    error_
  needs orderRepo

-- Adapter

memOrderRepo :: Decl 'Adapter
memOrderRepo = impl_ "InMemoryOrderRepo" framework orderRepo $ do
  inject "store" (ext "sync.Map")

----------------------------------------------------------------------
-- Feature: Catalog
----------------------------------------------------------------------

-- Domain

category :: Decl 'Model
category = model "Category" enterprise $ do
  field "id"          string
  field "name"        string
  field "description" string

product_ :: Decl 'Model
product_ = model "Product" enterprise $ do
  field "id"          (customType "UUID")
  field "name"        string
  field "description" string
  field "price"       (ref money)
  field "categoryId"  string
  field "stock"       int

-- Ports

productRepo :: Decl 'Boundary
productRepo = port "ProductRepository" interface $ do
  op "save"     ["product" .: ref product_] ["err" .: error_]
  op "findById" ["id" .: customType "UUID"] ["product" .: ref product_, "err" .: error_]
  op "findAll"  [] ["products" .: list (ref product_), "err" .: error_]
  op "delete"   ["id" .: customType "UUID"] ["err" .: error_]

productSearch :: Decl 'Boundary
productSearch = port "ProductSearch" interface $ do
  op "search" ["query" .: string] ["products" .: list (ref product_), "err" .: error_]

-- Use cases

createProduct :: Decl 'Operation
createProduct = usecase "CreateProduct" application $ do
  input  "product" (ref product_)
  output "id"      (customType "UUID")
  output "err"     error_
  needs productRepo

getProduct :: Decl 'Operation
getProduct = usecase "GetProduct" application $ do
  input  "productId" (customType "UUID")
  output "product"   (ref product_)
  output "err"       error_
  needs productRepo

searchProducts :: Decl 'Operation
searchProducts = usecase "SearchProducts" application $ do
  input  "query"    string
  output "products" (list (ref product_))
  output "err"      error_
  needs productSearch

-- Adapters

memProductRepo :: Decl 'Adapter
memProductRepo = impl_ "InMemoryProductRepo" framework productRepo $ do
  inject "store" (ext "sync.Map")

memProductSearch :: Decl 'Adapter
memProductSearch = impl_ "InMemoryProductSearch" framework productSearch $ do
  inject "store" (ext "sync.Map")

----------------------------------------------------------------------
-- Feature: Payment
----------------------------------------------------------------------

-- Domain

paymentStatus :: Decl 'Model
paymentStatus = enum_ "PaymentStatus" enterprise
  ["Pending", "Completed", "Failed", "Refunded"]

payment :: Decl 'Model
payment = model "Payment" enterprise $ do
  field "id"            (customType "UUID")
  field "orderId"       (customType "UUID")
  field "amount"        (ref money)
  field "status"        (ref paymentStatus)
  field "transactionId" string

-- Ports

paymentGateway :: Decl 'Boundary
paymentGateway = port "PaymentGateway" interface $ do
  op "charge" ["amount" .: ref money, "token" .: string] ["txId" .: string, "err" .: error_]
  op "refund" ["txId" .: string] ["err" .: error_]

paymentRepo :: Decl 'Boundary
paymentRepo = port "PaymentRepository" interface $ do
  op "save"         ["payment" .: ref payment] ["err" .: error_]
  op "findByOrder"  ["orderId" .: customType "UUID"] ["payment" .: ref payment, "err" .: error_]

-- Use cases

processPayment :: Decl 'Operation
processPayment = usecase "ProcessPayment" application $ do
  input  "orderId"      (customType "UUID")
  input  "amount"       (ref money)
  input  "paymentToken" string
  output "paymentId"    (customType "UUID")
  output "err"          error_
  needs paymentGateway
  needs paymentRepo

getPayment :: Decl 'Operation
getPayment = usecase "GetPayment" application $ do
  input  "orderId"  (customType "UUID")
  output "payment"  (ref payment)
  output "err"      error_
  needs paymentRepo

-- Adapters

memPaymentRepo :: Decl 'Adapter
memPaymentRepo = impl_ "InMemoryPaymentRepo" framework paymentRepo $ do
  inject "store" (ext "sync.Map")

stubPaymentGateway :: Decl 'Adapter
stubPaymentGateway = impl_ "StubPaymentGateway" framework paymentGateway $ do
  inject "logger" (ext "log.Logger")

----------------------------------------------------------------------
-- Feature modules (Ext.Modules)
----------------------------------------------------------------------

sharedModule :: Decl 'Compose
sharedModule = domain "SharedKernel" $ do
  expose money
  expose address

orderModule :: Decl 'Compose
orderModule = domain "OrderFeature" $ do
  import_ paymentModule paymentGateway
  expose order
  expose orderItem
  expose orderStatus
  expose orderRepo
  expose placeOrder
  expose cancelOrder
  expose getOrder
  expose listOrders
  expose memOrderRepo

catalogModule :: Decl 'Compose
catalogModule = domain "CatalogFeature" $ do
  expose category
  expose product_
  expose productRepo
  expose productSearch
  expose createProduct
  expose getProduct
  expose searchProducts
  expose memProductRepo
  expose memProductSearch

paymentModule :: Decl 'Compose
paymentModule = domain "PaymentFeature" $ do
  expose payment
  expose paymentStatus
  expose paymentGateway
  expose paymentRepo
  expose processPayment
  expose getPayment
  expose memPaymentRepo
  expose stubPaymentGateway

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------

wiring :: Decl 'Compose
wiring = wire "ECommerceWiring" $ do
  bind orderRepo       memOrderRepo
  bind productRepo     memProductRepo
  bind productSearch   memProductSearch
  bind paymentGateway  stubPaymentGateway
  bind paymentRepo     memPaymentRepo

  entry placeOrder
  entry cancelOrder
  entry getOrder
  entry listOrders
  entry createProduct
  entry getProduct
  entry searchProducts
  entry processPayment
  entry getPayment

----------------------------------------------------------------------
-- Architecture
----------------------------------------------------------------------

architecture :: Architecture
architecture = arch "ecommerce-platform" $ do
  useLayers cleanArchLayers
  registerType "UUID"

  -- Shared kernel
  declare money
  declare address

  -- Order feature
  declare orderStatus
  declare order
  declare orderItem
  declare orderRepo
  declare placeOrder
  declare cancelOrder
  declare getOrder
  declare listOrders
  declare memOrderRepo

  -- Catalog feature
  declare category
  declare product_
  declare productRepo
  declare productSearch
  declare createProduct
  declare getProduct
  declare searchProducts
  declare memProductRepo
  declare memProductSearch

  -- Payment feature
  declare paymentStatus
  declare payment
  declare paymentGateway
  declare paymentRepo
  declare processPayment
  declare getPayment
  declare memPaymentRepo
  declare stubPaymentGateway

  -- Feature modules
  declare sharedModule
  declare orderModule
  declare catalogModule
  declare paymentModule

  -- Wiring
  declare wiring

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------

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
