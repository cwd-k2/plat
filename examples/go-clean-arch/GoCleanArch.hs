-- | Example: Go Clean Architecture — Order Management Service
--
-- Demonstrates plat-hs with Ext.CleanArch, Ext.DDD, Ext.Http presets.
-- Target language: Go
module Main where

import Plat.Core
import Plat.Check
import Plat.Generate.Mermaid   (renderMermaid)
import Plat.Generate.Markdown  (renderMarkdown)
import Plat.Ext.CleanArch
import Plat.Ext.DDD

import qualified Data.Text
import qualified Data.Text.IO as TIO

import qualified Plat.Target.Go as Go
import Plat.Verify.Manifest (manifest, renderManifest)
import Plat.Verify.DepRules (depPolicy, renderDepMatrix)
import qualified Plat.Ext.Http as Http

----------------------------------------------------------------------
-- Domain layer (enterprise)
----------------------------------------------------------------------

-- Value Objects

money :: Decl 'Model
money = value "Money" enterprise $ do
  field "amount"   decimal
  field "currency" string

address :: Decl 'Model
address = value "Address" enterprise $ do
  field "street"  string
  field "city"    string
  field "country" string

orderStatus :: Decl 'Model
orderStatus = enum_ "OrderStatus" enterprise
  ["Pending", "Confirmed", "Shipped", "Delivered", "Cancelled"]

-- Aggregate Roots

order :: Decl 'Model
order = aggregate "Order" enterprise $ do
  field "id"        (customType "UUID")
  field "customer"  string
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

customer :: Decl 'Model
customer = aggregate "Customer" enterprise $ do
  field "id"        (customType "UUID")
  field "name"      string
  field "email"     string
  field "phone"     string
  field "address"   (ref address)
  field "createdAt" dateTime

customerStatus :: Decl 'Model
customerStatus = enum_ "CustomerStatus" enterprise
  ["Active", "Suspended", "Deleted"]

-- Domain Models

product_ :: Decl 'Model
product_ = model "Product" enterprise $ do
  field "id"          (customType "UUID")
  field "name"        string
  field "description" string
  field "price"       (ref money)
  field "categoryId"  string
  field "stock"       int

category :: Decl 'Model
category = model "Category" enterprise $ do
  field "id"          string
  field "name"        string
  field "description" string

paymentRecord :: Decl 'Model
paymentRecord = model "PaymentRecord" enterprise $ do
  field "id"            (customType "UUID")
  field "orderId"       (customType "UUID")
  field "amount"        (ref money)
  field "method"        string
  field "status"        string
  field "transactionId" string

----------------------------------------------------------------------
-- Interface layer (ports)
----------------------------------------------------------------------

orderRepo :: Decl 'Boundary
orderRepo = port "OrderRepository" interface $ do
  op "save"      ["order" .: ref order] ["err" .: error_]
  op "findById"  ["id" .: customType "UUID"] ["order" .: ref order, "err" .: error_]
  op "findAll"   [] ["orders" .: list (ref order), "err" .: error_]
  op "delete"    ["id" .: customType "UUID"] ["err" .: error_]

paymentGateway :: Decl 'Boundary
paymentGateway = port "PaymentGateway" interface $ do
  op "charge" ["amount" .: ref money, "token" .: string] ["txId" .: string, "err" .: error_]
  op "refund" ["txId" .: string] ["err" .: error_]

notifier :: Decl 'Boundary
notifier = port "OrderNotifier" interface $ do
  op "orderConfirmed" ["order" .: ref order] ["err" .: error_]

customerRepo :: Decl 'Boundary
customerRepo = port "CustomerRepository" interface $ do
  op "save"        ["customer" .: ref customer] ["err" .: error_]
  op "findById"    ["id" .: customType "UUID"] ["customer" .: ref customer, "err" .: error_]
  op "findByEmail" ["email" .: string] ["customer" .: ref customer, "err" .: error_]
  op "delete"      ["id" .: customType "UUID"] ["err" .: error_]

productRepo :: Decl 'Boundary
productRepo = port "ProductRepository" interface $ do
  op "save"     ["product" .: ref product_] ["err" .: error_]
  op "findById" ["id" .: customType "UUID"] ["product" .: ref product_, "err" .: error_]
  op "findAll"  [] ["products" .: list (ref product_), "err" .: error_]
  op "search"   ["query" .: string] ["products" .: list (ref product_), "err" .: error_]
  op "delete"   ["id" .: customType "UUID"] ["err" .: error_]

inventoryChecker :: Decl 'Boundary
inventoryChecker = port "InventoryChecker" interface $ do
  op "check" ["productId" .: customType "UUID", "quantity" .: int] ["available" .: bool, "err" .: error_]

----------------------------------------------------------------------
-- Application layer (use cases)
----------------------------------------------------------------------

placeOrder :: Decl 'Operation
placeOrder = usecase "PlaceOrder" application $ do
  input  "order"       (ref order)
  input  "paymentToken" string
  output "orderId"     (customType "UUID")
  output "err"         error_
  needs orderRepo
  needs paymentGateway
  needs notifier

cancelOrder :: Decl 'Operation
cancelOrder = usecase "CancelOrder" application $ do
  input  "orderId" (customType "UUID")
  output "err"     error_
  needs orderRepo
  needs paymentGateway

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

createCustomer :: Decl 'Operation
createCustomer = usecase "CreateCustomer" application $ do
  input  "customer" (ref customer)
  output "err"      error_
  needs customerRepo

getCustomer :: Decl 'Operation
getCustomer = usecase "GetCustomer" application $ do
  input  "customerId" (customType "UUID")
  output "customer"   (ref customer)
  output "err"        error_
  needs customerRepo

updateCustomerAddress :: Decl 'Operation
updateCustomerAddress = usecase "UpdateCustomerAddress" application $ do
  input  "customerId" (customType "UUID")
  input  "address"    (ref address)
  output "err"        error_
  needs customerRepo

createProduct :: Decl 'Operation
createProduct = usecase "CreateProduct" application $ do
  input  "product" (ref product_)
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
  needs productRepo

----------------------------------------------------------------------
-- Framework layer (adapters)
----------------------------------------------------------------------

pgOrderRepo :: Decl 'Adapter
pgOrderRepo = impl_ "PostgresOrderRepo" framework orderRepo $ do
  inject "db" (ext "*sql.DB")

stripePayment :: Decl 'Adapter
stripePayment = impl_ "StripePayment" framework paymentGateway $ do
  inject "client" (ext "*stripe.Client")

emailNotifier :: Decl 'Adapter
emailNotifier = impl_ "EmailNotifier" framework notifier $ do
  inject "mailer" (ext "smtp.Sender")

pgCustomerRepo :: Decl 'Adapter
pgCustomerRepo = impl_ "PostgresCustomerRepo" framework customerRepo $ do
  inject "db" (ext "*sql.DB")

pgProductRepo :: Decl 'Adapter
pgProductRepo = impl_ "PostgresProductRepo" framework productRepo $ do
  inject "db" (ext "*sql.DB")

stubInventory :: Decl 'Adapter
stubInventory = impl_ "StubInventory" framework inventoryChecker $ do
  inject "db" (ext "*sql.DB")

orderController :: Decl 'Adapter
orderController = Http.controller "OrderController" framework $ do
  Http.route Http.POST "/orders"     placeOrder
  Http.route Http.GET  "/orders"     listOrders
  Http.route Http.GET  "/orders/:id" getOrder
  Http.route Http.DELETE "/orders/:id" cancelOrder

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------

wiring :: Decl 'Compose
wiring = wire "OrderServiceWiring" $ do
  bind orderRepo         pgOrderRepo
  bind paymentGateway    stripePayment
  bind notifier          emailNotifier
  bind customerRepo      pgCustomerRepo
  bind productRepo       pgProductRepo
  bind inventoryChecker  stubInventory
  entry orderController

----------------------------------------------------------------------
-- Architecture
----------------------------------------------------------------------

architecture :: Architecture
architecture = arch "order-service" $ do
  useLayers cleanArchLayers
  registerType "UUID"

  -- Domain
  declare money
  declare address
  declare orderStatus
  declare order
  declare orderItem
  declare customer
  declare customerStatus
  declare product_
  declare category
  declare paymentRecord

  -- Ports
  declare orderRepo
  declare paymentGateway
  declare notifier
  declare customerRepo
  declare productRepo
  declare inventoryChecker

  -- Use cases
  declare placeOrder
  declare cancelOrder
  declare getOrder
  declare listOrders
  declare createCustomer
  declare getCustomer
  declare updateCustomerAddress
  declare createProduct
  declare getProduct
  declare searchProducts

  -- Adapters
  declare pgOrderRepo
  declare stripePayment
  declare emailNotifier
  declare pgCustomerRepo
  declare pgProductRepo
  declare stubInventory
  declare orderController

  -- Wiring
  declare wiring

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
