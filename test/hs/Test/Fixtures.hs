module Test.Fixtures
  ( -- * Layers
    core, application, interface, infra
    -- * Type helpers
  , uuid, money
    -- * Declarations
  , orderStatus, orderItem, order
  , orderRepo, paymentGateway
  , placeOrder, cancelOrder, getOrder
  , postgresOrderRepo, stripePayment, httpHandler
  , appRoot
    -- * Architecture
  , coreArch
  ) where

import Plat.Core
import Plat.Ext.Http

----------------------------------------------------------------------
-- Shared definitions
----------------------------------------------------------------------

core, application, interface, infra :: LayerDef
core        = layer "core"
interface   = layer "interface"   `depends` [core]
application = layer "application" `depends` [core, interface]
infra       = layer "infra"       `depends` [core, application, interface]

uuid :: TypeExpr
uuid = customType "UUID"

money :: TypeAlias
money = "Money" =: decimal

----------------------------------------------------------------------
-- Test architecture (Core eDSL)
----------------------------------------------------------------------

orderStatus :: Decl 'Model
orderStatus = model "OrderStatus" core $
  meta "kind" "enum"

orderItem :: Decl 'Model
orderItem = model "OrderItem" core $ do
  field "productId" uuid
  field "quantity"  int
  field "unitPrice" (alias money)

order :: Decl 'Model
order = model "Order" core $ do
  path "domain/order.go"
  field "id"         uuid
  field "customerId" uuid
  field "items"      (list (ref orderItem))
  field "status"     (ref orderStatus)
  field "total"      (alias money)
  field "createdAt"  dateTime
  field "updatedAt"  dateTime

orderRepo :: Decl 'Boundary
orderRepo = boundary "OrderRepository" interface $ do
  path "usecase/port/order_repo.go"
  op "save"
    ["order" .: ref order]
    ["err"   .: error_]
  op "findById"
    ["id" .: uuid]
    ["order" .: ref order, "err" .: error_]

paymentGateway :: Decl 'Boundary
paymentGateway = boundary "PaymentGateway" interface $ do
  op "charge"
    ["amount" .: alias money, "cardToken" .: string]
    ["chargeId" .: string, "err" .: error_]

placeOrder :: Decl 'Operation
placeOrder = operation "PlaceOrder" application $ do
  path "usecase/place_order.go"
  input  "customerId" uuid
  input  "items"      (list (ref orderItem))
  output "order"      (ref order)
  output "err"        error_
  needs orderRepo
  needs paymentGateway

cancelOrder :: Decl 'Operation
cancelOrder = operation "CancelOrder" application $ do
  input  "orderId" uuid
  output "err"     error_
  needs orderRepo

getOrder :: Decl 'Operation
getOrder = operation "GetOrder" application $ do
  input  "id"    uuid
  output "order" (ref order)
  output "err"   error_
  needs orderRepo

postgresOrderRepo :: Decl 'Adapter
postgresOrderRepo = adapter "PostgresOrderRepo" infra $ do
  implements orderRepo
  path "adapter/postgres/order_repo.go"
  inject "db" (ext "*sql.DB")

stripePayment :: Decl 'Adapter
stripePayment = adapter "StripePayment" infra $ do
  implements paymentGateway
  inject "client" (ext "*stripe.Client")

httpHandler :: Decl 'Adapter
httpHandler = adapter "OrderHttpHandler" infra $ do
  path "adapter/http/handler.go"
  inject "placeOrder" (ref placeOrder)
  inject "router"     (ext "chi.Router")

appRoot :: Decl 'Compose
appRoot = compose "AppRoot" $ do
  bind orderRepo       postgresOrderRepo
  bind paymentGateway  stripePayment
  entry httpHandler

coreArch :: Architecture
coreArch = arch "order-service" $ do
  useLayers [core, application, interface, infra]
  useTypes  [money]
  registerType "UUID"
  declare orderStatus
  declare orderItem
  declare order
  declare orderRepo
  declare paymentGateway
  declare placeOrder
  declare cancelOrder
  declare getOrder
  declare postgresOrderRepo
  declare stripePayment
  declare httpHandler
  declare appRoot
