module Order (
  orderStatus, order, orderItem,
  orderRepo, notifier,
  placeOrder, cancelOrder, getOrder, listOrders,
  pgOrderRepo, emailNotifier, orderController,
  declareAll
) where

import Plat.Core
import Plat.Ext.CleanArch
import Plat.Ext.DDD
import qualified Plat.Ext.Http as Http

import Shared (money, address)
import Payment (paymentGateway)

orderStatus :: Decl 'Model
orderStatus = enum "OrderStatus" enterprise
  ["Pending", "Confirmed", "Shipped", "Delivered", "Cancelled"]

order :: Decl 'Model
order = aggregate "Order" enterprise $ do
  field "id"        (customType "UUID")
  field "customer"  string
  field "items"     (listOf orderItem)
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

orderRepo :: Decl 'Boundary
orderRepo = port "OrderRepository" interface $ do
  op "save"      ["order" .: ref order] ["err" .: error_]
  op "findById"  ["id" .: customType "UUID"] ["order" .: ref order, "err" .: error_]
  op "findAll"   [] ["orders" .: listOf order, "err" .: error_]
  op "delete"    ["id" .: customType "UUID"] ["err" .: error_]

notifier :: Decl 'Boundary
notifier = port "OrderNotifier" interface $ do
  op "orderConfirmed" ["order" .: ref order] ["err" .: error_]

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
  output "orders" (listOf order)
  output "err"    error_
  needs orderRepo

pgOrderRepo :: Decl 'Adapter
pgOrderRepo = impl "PostgresOrderRepo" framework orderRepo $ do
  inject "db" (ext "*sql.DB")

emailNotifier :: Decl 'Adapter
emailNotifier = impl "EmailNotifier" framework notifier $ do
  inject "mailer" (ext "smtp.Sender")

orderController :: Decl 'Adapter
orderController = Http.controller "OrderController" framework $ do
  Http.route Http.POST "/orders"     placeOrder
  Http.route Http.GET  "/orders"     listOrders
  Http.route Http.GET  "/orders/:id" getOrder
  Http.route Http.DELETE "/orders/:id" cancelOrder

declareAll :: ArchBuilder ()
declareAll = declares
  [ decl orderStatus
  , decl order
  , decl orderItem
  , decl orderRepo
  , decl notifier
  , decl placeOrder
  , decl cancelOrder
  , decl getOrder
  , decl listOrders
  , decl pgOrderRepo
  , decl emailNotifier
  , decl orderController
  ]
