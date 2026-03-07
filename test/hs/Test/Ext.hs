module Test.Ext
  ( testDDD
  , testCQRS
  , testCleanArch
  , testHttp
  , testDBC
  , testFlow
  , testEvents
  , testModules
  , testMultiService
  ) where

import Plat.Core
import Plat.Check
import Plat.Ext.DDD
import Plat.Ext.CQRS
import Plat.Ext.CleanArch (cleanArchLayers, cleanArchRules, enterprise, framework, entity, port, impl, wire)
import qualified Plat.Ext.CleanArch as CA
import Plat.Ext.Http
import Plat.Ext.DBC
import Plat.Ext.Flow
import Plat.Ext.Events
import Plat.Ext.Modules
import Plat.Ext.MultiService

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
testCQRS = do
  -- CQRS-W001: query shares boundary with command
  let cqrsArch = arch "cqrs-test" $ do
        useLayers [core, application, interface]
        registerType "UUID"
        declare order
        declare orderRepo
        declare placeOrderCmd
        declare getOrderQuery
      r = checkWith (coreRules ++ cqrsRules) cqrsArch
  T.putStrLn (prettyCheck r)
  runTests
    [ ("command is Operation",   declKind (decl placeOrderCmd) == Operation)
    , ("command has meta",       isCommand (decl placeOrderCmd))
    , ("query is Operation",     declKind (decl getOrderQuery) == Operation)
    , ("query has meta",         isQuery (decl getOrderQuery))
    , ("command is not query",   not (isQuery (decl placeOrderCmd)))
    , ("CQRS-W001: shared boundary",
        any (\d -> dCode d == "CQRS-W001") (warnings r))
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

  -- CA-V001: impl without implements
  let badImpl = adapter "BareImpl" framework $ do
        tagAs CA.caImpl
        inject "db" (ext "*sql.DB")
      badArch = arch "ca-bad" $ do
        useLayers cleanArchLayers
        declare badImpl
      r2 = checkWith (coreRules ++ cleanArchRules) badArch
  T.putStrLn (prettyCheck r2)

  -- CA-W001: wire with no bindings
  let emptyWire = wire "EmptyWire" $ pure ()
      wireArch = arch "ca-wire" $ do
        useLayers cleanArchLayers
        declare emptyWire
      r3 = checkWith (coreRules ++ cleanArchRules) wireArch
  T.putStrLn (prettyCheck r3)

  runTests
    [ ("cleanArchLayers has 4",     length cleanArchLayers == 4)
    , ("entity is Model",           declKind (decl caEntity) == Model)
    , ("port is Boundary",          declKind (decl caPort) == Boundary)
    , ("impl is Adapter",           declKind (decl caImpl) == Adapter)
    , ("impl implements port",
        findImplements (declBody (decl caImpl)) == Just "ProductRepository")
    , ("no violations",             not (hasViolations r))
    , ("CA-V001: impl without implements",
        any (\d -> dCode d == "CA-V001") (violations r2))
    , ("CA-W001: wire no bindings",
        any (\d -> dCode d == "CA-W001") (warnings r3))
    ]

testHttp :: TestResult
testHttp = do
  let ctrlDecl = decl httpCtrl

  -- HTTP-W001: controller with no routes
  let emptyCtrl = controller "EmptyController" infra $ pure ()
      httpArch = arch "http-test" $ do
        useLayers [core, application, interface, infra]
        declare emptyCtrl
      r = checkWith (coreRules ++ httpRules) httpArch
  T.putStrLn (prettyCheck r)

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
    , ("HTTP-W001: controller no routes",
        any (\d -> dCode d == "HTTP-W001") (warnings r))
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

  -- EVT-V001: emit unknown event
  let badEmitOp = operation "BadEmit" application $ do
        output "err" error_
        needs orderRepo
        emit orderPlaced  -- orderPlaced not in arch
      evtBadArch = arch "evt-bad" $ do
        useLayers [core, application, interface]
        declare order
        declare orderRepo
        declare badEmitOp
      r1 = checkWith (coreRules ++ eventsRules) evtBadArch
  T.putStrLn (prettyCheck r1)

  -- EVT-W001: handler targets unknown event
  let badHandler = on_ "HandleMissing" orderPlaced application $ do
        output "err" error_
      evtBadArch2 = arch "evt-bad2" $ do
        useLayers [core, application]
        declare badHandler  -- orderPlaced not declared
      r2 = checkWith (coreRules ++ eventsRules) evtBadArch2
  T.putStrLn (prettyCheck r2)

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
    , ("EVT-V001: emit unknown event",
        any (\d -> dCode d == "EVT-V001") (violations r1))
    , ("EVT-W001: handler targets unknown event",
        any (\d -> dCode d == "EVT-W001") (warnings r2))
    , ("EVT-W002: unhandled event",
        let emitOnly = arch "evt-no-handler" $ do
              useLayers [core, application, interface]
              declare order
              declare orderRepo
              declare orderPlaced
              declare placeOrderWithEvent
            r3 = checkWith (coreRules ++ eventsRules) emitOnly
        in any (\d -> dCode d == "EVT-W002") (warnings r3))
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

  -- MOD-V001: expose unknown declaration
  let badDomain = domain "BadDomain" $ do
        expose order  -- order not in arch
      modBadArch = arch "mod-bad" $ do
        declare badDomain
      r1 = checkWith (coreRules ++ modulesRules) modBadArch

  -- MOD-V002: import from unknown module
  let nonExistentModule = domain "Phantom" $ pure ()
      badImport = domain "BadImport" $ do
        import_ nonExistentModule order
        expose paymentGateway
      modBadArch2 = arch "mod-bad2" $ do
        declare badImport
        declare paymentGateway
      r2 = checkWith (coreRules ++ modulesRules) modBadArch2

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
    , ("MOD-V001: expose unknown decl",
        any (\d -> dCode d == "MOD-V001") (violations r1))
    , ("MOD-V002: import unknown module",
        any (\d -> dCode d == "MOD-V002") (violations r2))
    , ("MOD-W001: import not exposed",
        let secretDecl = model "Secret" core $ field "x" int
            srcMod = domain "SrcDomain" $
              expose order  -- only exposes order, not secretDecl
            importMod = domain "ImportDomain" $ do
              import_ srcMod secretDecl  -- imports Secret which is not exposed
              expose paymentGateway
            modArch3 = arch "mod-encap" $ do
              useLayers [core, interface]
              declare order
              declare secretDecl
              declare paymentGateway
              declare srcMod
              declare importMod
            r3 = checkWith (coreRules ++ modulesRules) modArch3
        in any (\d -> dCode d == "MOD-W001") (warnings r3))
    ]

----------------------------------------------------------------------
-- MultiService extension tests
----------------------------------------------------------------------

testMultiService :: TestResult
testMultiService = do
  -- Define two separate services
  let -- Order service: has a public API boundary (orderRepo) and an internal boundary
      orderApiRepo = boundary "OrderRepository" interface $ do
        serviceApi
        op "save" ["order" .: ref order] ["err" .: error_]
        op "findById" ["id" .: uuid] ["order" .: ref order, "err" .: error_]

      internalNotifier = boundary "InternalNotifier" interface $ do
        op "notify" ["msg" .: string] []

      orderOp = operation "PlaceOrder" application $ do
        input "customerId" uuid
        output "err" error_
        needs orderApiRepo

      orderSvc = arch "order-service" $ do
        useLayers [core, application, interface]
        declare order
        declare orderApiRepo
        declare internalNotifier
        declare orderOp

      -- Payment service: depends on OrderRepository from order-service
      paymentApiGw = boundary "PaymentGateway" interface $ do
        serviceApi
        op "charge" ["amount" .: decimal] ["err" .: error_]

      processPayment = operation "ProcessPayment" application $ do
        input "amount" decimal
        output "err" error_
        needs paymentApiGw
        needs orderApiRepo  -- cross-service: depends on order service's boundary

      paymentSvc = arch "payment-service" $ do
        useLayers [core, application, interface]
        declare paymentApiGw
        declare processPayment

  -- Compose into system
  let Right sysArch = system "platform" $ do
        include "order" orderSvc
        include "payment" paymentSvc

  -- Query tests
  let apis = serviceApis sysArch
      deps = serviceDeps sysArch
      orderDecl = case filter (\d -> declName d == "Order") (archDecls sysArch) of
                    (d:_) -> d; [] -> error "no Order decl"

  -- Validation: all cross-service refs are to serviceApi boundaries → clean
  let r1 = checkWith (coreRules ++ multiServiceRules) sysArch
  T.putStrLn (prettyCheck r1)

  -- SVC-V001: cross-service needs non-API boundary
  let badOp = operation "BadOp" application $ do
        input "x" string
        needs internalNotifier  -- internalNotifier is NOT serviceApi
      badPaymentSvc = arch "bad-payment" $ do
        useLayers [core, application, interface]
        declare badOp
      Right badSys = system "bad-platform" $ do
        include "order" orderSvc
        include "bad-payment" badPaymentSvc
      r2 = checkWith (coreRules ++ multiServiceRules) badSys

  -- SVC-V002: circular service dependencies
  let svcA_bnd = boundary "SvcABoundary" interface $ do
        serviceApi
        op "doA" [] []
      svcB_bnd = boundary "SvcBBoundary" interface $ do
        serviceApi
        op "doB" [] []
      svcA_op = operation "OpA" application $ do
        needs svcB_bnd  -- A needs B
      svcB_op = operation "OpB" application $ do
        needs svcA_bnd  -- B needs A → cycle!
      svcA = arch "svc-a" $ do
        useLayers [core, application, interface]
        declare svcA_bnd
        declare svcA_op
      svcB = arch "svc-b" $ do
        useLayers [core, application, interface]
        declare svcB_bnd
        declare svcB_op
      Right cycleSys = system "cycle-platform" $ do
        include "svc-a" svcA
        include "svc-b" svcB
      r3 = checkWith (coreRules ++ multiServiceRules) cycleSys

  runTests
    [ ("system merges services",
        length (archDecls sysArch) == 6)  -- order, orderApiRepo, internalNotifier, orderOp, paymentApiGw, processPayment
    , ("origin tagged",
        originService orderDecl == Just "order")
    , ("serviceApis found",
        length apis == 2)  -- OrderRepository, PaymentGateway
    , ("service deps inferred",
        ("payment", "order") `elem` deps)
    , ("isServiceApi works",
        let apiRepoDecl = case filter (\d -> declName d == "OrderRepository") (archDecls sysArch) of
                            (d:_) -> d; [] -> error "no OrderRepository"
        in isServiceApi apiRepoDecl)
    , ("non-API not serviceApi",
        let intDecl = case filter (\d -> declName d == "InternalNotifier") (archDecls sysArch) of
                        (d:_) -> d; [] -> error "no InternalNotifier"
        in not (isServiceApi intDecl))
    , ("clean system has no SVC errors",
        not (any (\d -> dCode d == "SVC-V001") (violations r1)))
    , ("SVC-V001: cross-service non-API",
        any (\d -> dCode d == "SVC-V001") (violations r2))
    , ("SVC-V002: circular service deps",
        any (\d -> dCode d == "SVC-V002") (violations r3))
    , ("serviceRequires adds relation",
        let Right reqSys = system "req-platform" $ do
              include "order" orderSvc
              include "payment" paymentSvc
              serviceRequires "payment" "order" "OrderRepository"
        in any (\r -> relKind r == "service-requires") (archRelations reqSys))
    ]
