module Test.Ext
  ( testDDD
  , testCQRS
  , testCleanArch
  , testHttp
  , testDBC
  , testFlow
  , testEvents
  , testModules
  ) where

import Plat.Core
import Plat.Check
import Plat.Ext.DDD
import Plat.Ext.CQRS
import Plat.Ext.CleanArch (cleanArchLayers, enterprise, framework, entity, port, impl)
import qualified Plat.Ext.CleanArch as CA
import Plat.Ext.Http
import Plat.Ext.DBC
import Plat.Ext.Flow
import Plat.Ext.Events
import Plat.Ext.Modules

import qualified Data.Text.IO as T

import Test.Harness
import Test.Fixtures

----------------------------------------------------------------------
-- DDD extension test definitions
----------------------------------------------------------------------

dddMoney :: Decl 'Model
dddMoney = value "Money" core $ do
  field "amount"   int
  field "currency" string
  invariant "nonNegative" "amount >= 0"

dddBadValue :: Decl 'Model
dddBadValue = value "BadValue" core $
  field "id" uuid  -- DDD-V001: value with id field

dddOrder :: Decl 'Model
dddOrder = aggregate "Order" core $ do
  field "id"     uuid
  field "status" string

dddOrderNoId :: Decl 'Model
dddOrderNoId = aggregate "OrderNoId" core $
  field "status" string  -- DDD-V002: aggregate without id

dddStatus :: Decl 'Model
dddStatus = enum "OrderStatus" core
  ["draft", "placed", "paid", "shipped"]

----------------------------------------------------------------------
-- CQRS extension test definitions
----------------------------------------------------------------------

placeOrderCmd :: Decl 'Operation
placeOrderCmd = command "PlaceOrderCmd" application $ do
  input  "customerId" uuid
  output "orderId"    uuid
  needs orderRepo

getOrderQuery :: Decl 'Operation
getOrderQuery = query "GetOrderQuery" application $ do
  input  "id"    uuid
  output "order" (ref order)
  needs orderRepo

----------------------------------------------------------------------
-- CleanArch extension test definitions
----------------------------------------------------------------------

caEntity :: Decl 'Model
caEntity = entity "Product" enterprise $ do
  field "id"   uuid
  field "name" string

caPort :: Decl 'Boundary
caPort = port "ProductRepository" CA.interface $ do
  op "save" ["p" .: ref caEntity] ["err" .: error_]

caImpl :: Decl 'Adapter
caImpl = impl "PostgresProductRepo" framework caPort $
  inject "db" (ext "*sql.DB")

----------------------------------------------------------------------
-- Http extension test definition
----------------------------------------------------------------------

httpCtrl :: Decl 'Adapter
httpCtrl = controller "OrderController" infra $ do
  path "adapter/http/handler.go"
  route POST   "/orders"       placeOrder
  route DELETE "/orders/{id}"  cancelOrder
  route GET    "/orders/{id}"  getOrder

----------------------------------------------------------------------
-- Tests
----------------------------------------------------------------------

testDDD :: TestResult
testDDD = do
  let dddArch = arch "ddd-test" $ do
        useLayers [core]
        registerType "UUID"
        declare dddMoney
        declare dddBadValue
        declare dddOrder
        declare dddOrderNoId
        declare dddStatus
      r = checkWith (coreRules ++ dddRules) dddArch
  T.putStrLn (prettyCheck r)
  runTests
    [ ("value is Model",              declKind (decl dddMoney) == Model)
    , ("value has meta",              isValue (decl dddMoney))
    , ("aggregate has meta",          isAggregate (decl dddOrder))
    , ("enum has meta",               isEnum (decl dddStatus))
    , ("enum has variants",           lookupMeta "plat-ddd:variant:draft" (decl dddStatus) == Just "draft")
    , ("invariant in meta",
        lookupMeta "plat-ddd:invariant:nonNegative" (decl dddMoney) == Just "amount >= 0")
    , ("DDD-V001: value with id",     any (\d -> dCode d == "DDD-V001") (violations r))
    , ("DDD-V002: aggregate no id",   any (\d -> dCode d == "DDD-V002") (warnings r))
    ]

testCQRS :: TestResult
testCQRS = runTests
  [ ("command is Operation",   declKind (decl placeOrderCmd) == Operation)
  , ("command has meta",       isCommand (decl placeOrderCmd))
  , ("query is Operation",     declKind (decl getOrderQuery) == Operation)
  , ("query has meta",         isQuery (decl getOrderQuery))
  , ("command is not query",   not (isQuery (decl placeOrderCmd)))
  ]

testCleanArch :: TestResult
testCleanArch = do
  let caArch = arch "ca-test" $ do
        useLayers cleanArchLayers
        registerType "UUID"
        declare caEntity
        declare caPort
        declare caImpl
      r = check caArch
  T.putStrLn (prettyCheck r)
  runTests
    [ ("cleanArchLayers has 4",     length cleanArchLayers == 4)
    , ("entity is Model",           declKind (decl caEntity) == Model)
    , ("port is Boundary",          declKind (decl caPort) == Boundary)
    , ("impl is Adapter",           declKind (decl caImpl) == Adapter)
    , ("impl implements port",
        findImplements (declBody (decl caImpl)) == Just "ProductRepository")
    , ("no violations",             not (hasViolations r))
    ]

testHttp :: TestResult
testHttp = do
  let ctrlDecl = decl httpCtrl
  runTests
    [ ("controller is Adapter",     declKind ctrlDecl == Adapter)
    , ("controller has meta",
        lookupMeta "plat-http:kind" ctrlDecl == Just "controller")
    , ("route records PlaceOrder",
        lookupMeta "plat-http:route:PlaceOrder" ctrlDecl == Just "POST /orders")
    , ("route records CancelOrder",
        lookupMeta "plat-http:route:CancelOrder" ctrlDecl == Just "DELETE /orders/{id}")
    , ("route records GetOrder",
        lookupMeta "plat-http:route:GetOrder" ctrlDecl == Just "GET /orders/{id}")
    , ("route injects operations",
        length [() | Inject _ _ <- declBody ctrlDecl] == 3)
    ]

testDBC :: TestResult
testDBC = do
  let opWithContracts = operation "Transfer" application $ do
        pre "positive" "amount > 0"
        post "balanced" "from.balance + to.balance == total"
        input "amount" decimal
        output "err" error_
        needs orderRepo

      opNoNeeds = operation "Check" application $ do
        pre "valid" "x > 0"
        output "ok" bool

      dbcArch = arch "dbc-test" $ do
        useLayers [core, application, interface]
        declare orderRepo
        declare opWithContracts
        declare opNoNeeds
      r = checkWith (coreRules ++ dbcRules) dbcArch
  T.putStrLn (prettyCheck r)
  let d = decl opWithContracts
  runTests
    [ ("pre in meta",
        lookupMeta "plat-dbc:pre:positive" d == Just "amount > 0")
    , ("post in meta",
        lookupMeta "plat-dbc:post:balanced" d == Just "from.balance + to.balance == total")
    , ("DBC-W001: no needs with contract",
        any (\diag -> dCode diag == "DBC-W001") (warnings r))
    ]

testFlow :: TestResult
testFlow = do
  let validateOrder = step "ValidateOrder" application $ do
        guard_ "hasItems" "order.items.length > 0"
        guard_ "hasCustomer" "order.customerId != null"
        input "order" (ref order)
        output "valid" bool
        needs orderRepo

      orderPolicy = policy "OrderPolicy" core $ do
        field "maxItems" int
        field "minAmount" decimal

      d = decl validateOrder
  runTests
    [ ("step is Operation",      declKind d == Operation)
    , ("step has meta",          lookupMeta "plat-flow:kind" d == Just "step")
    , ("guard in meta",
        lookupMeta "plat-flow:guard:hasItems" d == Just "order.items.length > 0")
    , ("policy is Model",        declKind (decl orderPolicy) == Model)
    , ("policy has meta",
        lookupMeta "plat-flow:kind" (decl orderPolicy) == Just "policy")
    ]

testEvents :: TestResult
testEvents = do
  let orderPlaced = event "OrderPlaced" core $ do
        field "orderId" uuid
        field "total" decimal

      orderShipped = event "OrderShipped" core $ do
        field "orderId" uuid
        field "trackingNo" string

      placeOrderWithEvent = operation "PlaceOrderEvt" application $ do
        input "order" (ref order)
        output "err" error_
        needs orderRepo
        emit orderPlaced

      onOrderPlaced = on_ "HandleOrderPlaced" orderPlaced application $ do
        output "err" error_
        needs orderRepo

      orderAgg = model "OrderAggregate" core $ do
        field "id" uuid
        field "status" string
        apply orderPlaced
        apply orderShipped

      evtD  = decl orderPlaced
      opD   = decl placeOrderWithEvent
      hdlD  = decl onOrderPlaced
      aggD  = decl orderAgg
  runTests
    [ ("event is Model",             declKind evtD == Model)
    , ("event has meta",             lookupMeta "plat-events:kind" evtD == Just "event")
    , ("event has fields",           length (declFields evtD) == 2)
    , ("emit in op meta",
        lookupMeta "plat-events:emit:OrderPlaced" opD == Just "OrderPlaced")
    , ("handler is Operation",       declKind hdlD == Operation)
    , ("handler has on meta",
        lookupMeta "plat-events:on" hdlD == Just "OrderPlaced")
    , ("handler kind is handler",
        lookupMeta "plat-events:kind" hdlD == Just "handler")
    , ("apply in aggregate",
        lookupMeta "plat-events:apply:OrderPlaced" aggD == Just "OrderPlaced")
    , ("apply OrderShipped",
        lookupMeta "plat-events:apply:OrderShipped" aggD == Just "OrderShipped")
    ]

testModules :: TestResult
testModules = do
  let orderDomain = domain "OrderDomain" $ do
        expose order
        expose orderRepo
        expose placeOrder

      paymentDomain = domain "PaymentDomain" $ do
        import_ orderDomain order
        expose paymentGateway

      domD = decl orderDomain
      payD = decl paymentDomain
  runTests
    [ ("domain is Compose",          declKind domD == Compose)
    , ("domain has meta",
        lookupMeta "plat-modules:kind" domD == Just "domain")
    , ("expose Order",
        lookupMeta "plat-modules:expose:Order" domD == Just "Order")
    , ("expose PlaceOrder",
        lookupMeta "plat-modules:expose:PlaceOrder" domD == Just "PlaceOrder")
    , ("entries match exposes",
        length [() | Entry _ <- declBody domD] == 3)
    , ("import in payment",
        lookupMeta "plat-modules:import:Order" payD == Just "OrderDomain")
    , ("payment exposes gateway",
        lookupMeta "plat-modules:expose:PaymentGateway" payD == Just "PaymentGateway")
    ]
