-- | Order サービスのアーキテクチャ宣言。
--
-- Clean Architecture の4責務（Model, Boundary, Operation, Adapter）を
-- それぞれ phantom-tagged な @Decl k@ として定義する。
-- phantom tag @k@ がコンビネータの誤用をコンパイル時に防ぐ:
--   - @field@ は @Decl ''Model'@ 内でのみ使用可能
--   - @op@ は @Decl ''Boundary'@ 内でのみ使用可能
--   - @needs@ は @Decl ''Operation'@ 内でのみ使用可能
--
-- 型式は関数合成で構築する:
--   - @ref x@       — 宣言 x への参照を TypeExpr に持ち上げる
--   - @list@, @option@, @set@ — TypeExpr の自己準同型
--   - @list (ref x)@ — これらを合成するだけで、専用コンビネータは不要
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

----------------------------------------------------------------------
-- Domain Models (enterprise layer)
--
-- aggregate / value / enum は DDD 拡張のスマートコンストラクタ。
-- 内部で model + tagAs dddAggregate のように core + meta タグに展開される。
----------------------------------------------------------------------

orderStatus :: Decl 'Model
orderStatus = enum "OrderStatus" enterprise
  ["Pending", "Confirmed", "Shipped", "Delivered", "Cancelled"]

order :: Decl 'Model
order = aggregate "Order" enterprise $ do
  field "id"        (customType "UUID")
  field "customer"  string
  field "items"     (list (ref orderItem))  -- list . ref: 型コンストラクタの合成
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
-- Boundaries / Ports (interface layer)
--
-- port は CleanArch 拡張のスマートコンストラクタ。
-- op の引数は [Param] — "name" .: TypeExpr でパラメータを構築する。
----------------------------------------------------------------------

orderRepo :: Decl 'Boundary
orderRepo = port "OrderRepository" interface $ do
  op "save"      ["order" .: ref order] ["err" .: error_]
  op "findById"  ["id" .: customType "UUID"] ["order" .: ref order, "err" .: error_]
  op "findAll"   [] ["orders" .: list (ref order), "err" .: error_]
  op "delete"    ["id" .: customType "UUID"] ["err" .: error_]

notifier :: Decl 'Boundary
notifier = port "OrderNotifier" interface $ do
  op "orderConfirmed" ["order" .: ref order] ["err" .: error_]

----------------------------------------------------------------------
-- Operations / Use Cases (application layer)
--
-- usecase は CleanArch 拡張のスマートコンストラクタ。
-- needs で依存する Boundary を宣言すると、
-- plat-verify が実コードの DI 整合性を検査できる。
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
-- Adapters / Implementations (framework layer)
--
-- impl は boundary を自動 implements する CleanArch コンストラクタ。
-- ext は言語固有の外部型 — W002 (未定義型) 検査から免除される。
----------------------------------------------------------------------

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

----------------------------------------------------------------------
-- Registration
--
-- declare :: Decl k -> ArchBuilder () はモナディックアクション。
-- mapM_ declare で同じ kind の宣言をまとめて登録できる。
-- 異なる kind (Model と Boundary 等) は同じリストに入らない —
-- phantom tag が型レベルでグルーピングを強制する。
----------------------------------------------------------------------

declareAll :: ArchBuilder ()
declareAll = do
  mapM_ declare [orderStatus, order, orderItem]
  mapM_ declare [orderRepo, notifier]
  mapM_ declare [placeOrder, cancelOrder, getOrder, listOrders]
  mapM_ declare [pgOrderRepo, emailNotifier, orderController]
