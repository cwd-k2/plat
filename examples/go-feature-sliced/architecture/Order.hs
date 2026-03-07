module Order (
  orderStatus, order, orderItem,
  orderRepo,
  placeOrder, cancelOrder, getOrder, listOrders,
  memOrderRepo,
  orderModule,
  declareAll
) where

import Plat.Core
import Plat.Ext.CleanArch
import Plat.Ext.DDD
import Plat.Ext.Modules
import Shared (money, address)
import Payment (paymentGateway, paymentModule)

----------------------------------------------------------------------
-- Feature: Order
----------------------------------------------------------------------

-- Domain

orderStatus :: Decl 'Model
orderStatus = enum "OrderStatus" enterprise
  ["Pending", "Confirmed", "Shipped", "Delivered", "Cancelled"]

order :: Decl 'Model
order = aggregate "Order" enterprise $ do
  field "id"        (customType "UUID")
  field "customerId" (customType "UUID")
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

-- Port

orderRepo :: Decl 'Boundary
orderRepo = port "OrderRepository" interface $ do
  op "save"     ["order" .: ref order] ["err" .: error_]
  op "findById" ["id" .: customType "UUID"] ["order" .: ref order, "err" .: error_]
  op "findAll"  [] ["orders" .: listOf order, "err" .: error_]
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
  output "orders" (listOf order)
  output "err"    error_
  needs orderRepo

-- Adapter

memOrderRepo :: Decl 'Adapter
memOrderRepo = impl "InMemoryOrderRepo" framework orderRepo $ do
  inject "store" (ext "sync.Map")

-- Module

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

declareAll :: ArchBuilder ()
declareAll = declares
  [ decl orderStatus
  , decl order
  , decl orderItem
  , decl orderRepo
  , decl placeOrder
  , decl cancelOrder
  , decl getOrder
  , decl listOrders
  , decl memOrderRepo
  , decl orderModule
  ]
