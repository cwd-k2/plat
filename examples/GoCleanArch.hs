-- | Example: Go Clean Architecture — Order Management Service
--
-- Demonstrates plat-hs with Ext.CleanArch, Ext.DDD, Ext.Http presets.
-- Target language: Go
module Main where

import Plat.Core
import Plat.Check
import Plat.Generate.Plat    (render)
import Plat.Generate.Mermaid (renderMermaid)
import Plat.Ext.CleanArch
import Plat.Ext.DDD

import qualified Data.Text.IO as TIO

import qualified Plat.Target.Go as Go
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

-- Aggregate Root

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
  bind orderRepo       pgOrderRepo
  bind paymentGateway  stripePayment
  bind notifier        emailNotifier
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

  -- Ports
  declare orderRepo
  declare paymentGateway
  declare notifier

  -- Use cases
  declare placeOrder
  declare cancelOrder
  declare getOrder
  declare listOrders

  -- Adapters
  declare pgOrderRepo
  declare stripePayment
  declare emailNotifier
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

  -- .plat output
  putStrLn "--- .plat ---"
  TIO.putStrLn $ render architecture
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
