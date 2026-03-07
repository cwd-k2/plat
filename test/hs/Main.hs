module Main where

import Plat.Core
import Plat.Check
import Plat.Generate.Mermaid (renderMermaid)
import Plat.Generate.Markdown (renderMarkdown)
import Plat.Ext.DDD
import Plat.Ext.CQRS
import Plat.Ext.CleanArch (cleanArchLayers, enterprise, framework, entity, port, impl)
import qualified Plat.Ext.CleanArch as CA
import Plat.Ext.Http
import Plat.Ext.DBC
import Plat.Ext.Flow
import Plat.Ext.Events
import Plat.Ext.Modules
import Plat.Verify.Manifest

import Data.Maybe (isJust)
import qualified Data.Set as Set
import qualified Data.Text as T
import qualified Data.Text.IO as T
import System.Exit (exitFailure)

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
  field "items"      (listOf orderItem)
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
  input  "items"      (listOf orderItem)
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
  entryName "MainServer"

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

----------------------------------------------------------------------
-- DDD extension test architecture
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
-- CQRS extension test
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
-- CleanArch extension test
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
-- Http extension test
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

main :: IO ()
main = do
  results <- sequence
    [ section "Core eDSL"          testCoreEdsl
    , section "Check"              testCheck
    , section "Render Mermaid"     testRenderMermaid
    , section "Render Markdown"    testRenderMarkdown
    , section "Layer violations"   testLayerViolations
    , section "Ext.DDD"            testDDD
    , section "Ext.CQRS"          testCQRS
    , section "Ext.CleanArch"     testCleanArch
    , section "Ext.Http"          testHttp
    , section "Ext.DBC"           testDBC
    , section "Ext.Flow"          testFlow
    , section "Ext.Events"        testEvents
    , section "Ext.Modules"       testModules
    , section "Meta-programming"  testMetaProgramming
    , section "V009/W003"         testNewRules
    , section "Constraints"       testConstraints
    , section "Relations"         testRelations
    , section "Algebra"           testAlgebra
    , section "Manifest"          testManifest
    , section "Evidence"          testEvidence
    , section "Algebraic props"   testAlgebraicProperties
    ]
  let total   = sum (map fst results)
      failed  = sum (map snd results)
  putStrLn $ "\n=== " ++ show total ++ " tests, " ++ show failed ++ " failures ==="
  if failed > 0 then exitFailure else pure ()

section :: String -> IO (Int, Int) -> IO (Int, Int)
section name act = do
  putStrLn $ "\n--- " ++ name ++ " ---"
  act

-- Returns (total, failures)
type TestResult = IO (Int, Int)

runTests :: [(String, Bool)] -> TestResult
runTests tests = do
  rs <- mapM (\(label, ok) -> do
    if ok
      then putStrLn ("  OK: " ++ label) >> pure True
      else putStrLn ("  FAIL: " ++ label) >> pure False
    ) tests
  let total = length rs
      failed = length (filter not rs)
  pure (total, failed)

----------------------------------------------------------------------

testCoreEdsl :: TestResult
testCoreEdsl = runTests
  [ ("architecture has 4 layers",  length (archLayers coreArch) == 4)
  , ("architecture has 12 decls",  length (archDecls coreArch) == 12)
  , ("order is Model",             declKind (decl order) == Model)
  , ("orderRepo is Boundary",      declKind (decl orderRepo) == Boundary)
  , ("placeOrder is Operation",    declKind (decl placeOrder) == Operation)
  , ("postgresOrderRepo is Adapter", declKind (decl postgresOrderRepo) == Adapter)
  , ("appRoot is Compose",         declKind (decl appRoot) == Compose)
  , ("order has 7 fields",         length (declFields (decl order)) == 7)
  , ("orderRepo has 2 ops",        length (declOps (decl orderRepo)) == 2)
  , ("placeOrder needs 2",         length (declNeeds (decl placeOrder)) == 2)
  , ("implements resolves",
      findImplements (declBody (decl postgresOrderRepo)) == Just "OrderRepository")
  , ("no implements = Nothing",
      findImplements (declBody (decl httpHandler)) == Nothing)
  , ("order has path",             declPaths (decl order) == ["domain/order.go"])
  , ("compose has no layer",       declLayer (decl appRoot) == Nothing)
  , ("model has layer",            declLayer (decl order) == Just "core")
  , ("TypeAlias works",            alias money == TRef "Money")
  , ("idOf produces Id<T>",        idOf order == TGeneric "Id" [TRef "Order"])
  , ("ref produces TRef",          ref order == TRef "Order")
  , ("list wraps",                 list int == TGeneric "List" [TBuiltin BInt])
  , ("nullable wraps",             nullable string == TNullable (TBuiltin BString))
  , ("result wraps",               result int error_ == TGeneric "Result" [TBuiltin BInt, TRef "Error"])
  , ("(.:) builds Param",          ("x" .: int) == Param "x" (TBuiltin BInt))
  , ("meta is preserved",
      lookupMeta "kind" (decl orderStatus) == Just "enum")
  , ("registerType in arch",       "UUID" `elem` archCustomTypes coreArch)
  ]

testCheck :: TestResult
testCheck = do
  let r = check coreArch
  T.putStrLn (prettyCheck r)
  runTests
    [ ("no violations",  not (hasViolations r))
    , ("no warnings",    not (hasWarnings r))
    ]

testRenderMermaid :: TestResult
testRenderMermaid = do
  let mmd = renderMermaid coreArch
  T.putStrLn mmd
  runTests
    [ ("mermaid non-empty",     T.length mmd > 0)
    , ("starts with graph TD",  "graph TD" `T.isInfixOf` mmd)
    , ("contains Order node",   "Order[" `T.isInfixOf` mmd)
    , ("contains needs edge",   "needs" `T.isInfixOf` mmd)
    , ("contains bind edge",    "bind" `T.isInfixOf` mmd)
    ]

testRenderMarkdown :: TestResult
testRenderMarkdown = do
  let md = renderMarkdown coreArch
  runTests
    [ ("markdown non-empty",    T.length md > 0)
    , ("has title",             "# order-service" `T.isInfixOf` md)
    , ("has layers section",    "## Layers" `T.isInfixOf` md)
    , ("has model section",     "## Order" `T.isInfixOf` md)
    , ("has field table",       "| Field | Type |" `T.isInfixOf` md)
    , ("has boundary section",  "## OrderRepository" `T.isInfixOf` md)
    , ("has operation section", "## PlaceOrder" `T.isInfixOf` md)
    , ("has depends on",        "**Depends on**" `T.isInfixOf` md)
    , ("has adapter section",   "## PostgresOrderRepo" `T.isInfixOf` md)
    , ("has compose section",   "## AppRoot" `T.isInfixOf` md)
    ]

testLayerViolations :: TestResult
testLayerViolations = do
  let badDecl' = operation "BadOp" core $
        needs orderRepo  -- core → interface: violation!
      badArch = arch "bad" $ do
        useLayers [core, interface]
        declare orderRepo
        declare badDecl'
      r = check badArch
  T.putStrLn (prettyCheck r)
  let diags = violations r
  runTests
    [ ("detects V001",          hasViolations r)
    , ("V001 in violations",    any (\d -> dCode d == "V001") diags)
    ]

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

testMetaProgramming :: TestResult
testMetaProgramming = do
  let crudBoundary :: Decl 'Model -> Decl 'Boundary
      crudBoundary e = boundary (declName (unDecl e) <> "Repository") interface $ do
        op "save"    ["e" .: ref e] ["err" .: error_]
        op "findById" ["id" .: idOf e] ["e" .: ref e, "err" .: error_]
        op "delete"  ["id" .: idOf e] ["err" .: error_]

      repos = map crudBoundary [order, orderItem]
      (repo1, repo2) = case repos of [a, b] -> (a, b); _ -> Prelude.error "unreachable"
      metaArch = arch "meta-test" $ do
        useLayers [core, interface]
        registerType "UUID"
        declare order
        declare orderItem
        declares (map decl repos)
      r = check metaArch
  runTests
    [ ("generates 2 repos",        length repos == 2)
    , ("first is OrderRepository", declName (decl repo1) == "OrderRepository")
    , ("second is OrderItemRepository", declName (decl repo2) == "OrderItemRepository")
    , ("each has 3 ops",           all (\d -> length (declOps (decl d)) == 3) repos)
    , ("no violations",            not (hasViolations r))
    ]

----------------------------------------------------------------------
-- DBC tests
----------------------------------------------------------------------

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

----------------------------------------------------------------------
-- Flow tests
----------------------------------------------------------------------

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

----------------------------------------------------------------------
-- Events tests
----------------------------------------------------------------------

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

----------------------------------------------------------------------
-- Modules tests
----------------------------------------------------------------------

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

----------------------------------------------------------------------
-- V009 / W003 tests
----------------------------------------------------------------------

testNewRules :: TestResult
testNewRules = do
  let dupArch = arch "dup-test" $ do
        useLayers [core]
        registerType "UUID"
        declare order
        declare order  -- duplicate!
      r1 = check dupArch
  T.putStrLn (prettyCheck r1)

  let multiImplAdapter = adapter "MultiAdapter" infra $ do
        implements orderRepo
        implements paymentGateway
      multiArch = arch "multi-impl" $ do
        useLayers [core, interface, infra]
        registerType "UUID"
        declare order
        declare orderRepo
        declare paymentGateway
        declare multiImplAdapter
      r2 = check multiArch
  T.putStrLn (prettyCheck r2)

  runTests
    [ ("V009: duplicate name",
        any (\d -> dCode d == "V009") (violations r1))
    , ("W003: multiple implements",
        any (\d -> dCode d == "W003") (warnings r2))
    , ("W003: mentions both boundaries",
        any (\d -> dCode d == "W003" && "OrderRepository" `T.isInfixOf` dMessage d
                                     && "PaymentGateway" `T.isInfixOf` dMessage d) (warnings r2))
    , ("multi-implements last wins",
        findImplements (declBody (decl multiImplAdapter)) == Just "PaymentGateway")
    ]

----------------------------------------------------------------------
-- Constraint tests
----------------------------------------------------------------------

testConstraints :: TestResult
testConstraints = do
  -- Architecture with a satisfied constraint
  let goodArch = arch "good" $ do
        useLayers [core, interface, infra]
        registerType "UUID"
        declare order
        declare orderRepo
        declare postgresOrderRepo

        constrain "adapter-has-impl"
          "every adapter must implement a boundary" $
          require Adapter "has no implements"
            (\d -> isJust (findImplements (declBody d)))

      r1 = check goodArch
  T.putStrLn (prettyCheck r1)

  -- Architecture with a violated constraint
  let noImplAdapter = adapter "BareAdapter" infra $ do
        inject "db" (ext "*sql.DB")

      badArch = arch "bad" $ do
        useLayers [core, interface, infra]
        registerType "UUID"
        declare order
        declare orderRepo
        declare noImplAdapter

        constrain "adapter-has-impl"
          "every adapter must implement a boundary" $
          require Adapter "has no implements"
            (\d -> isJust (findImplements (declBody d)))

      r2 = check badArch
  T.putStrLn (prettyCheck r2)

  -- Architecture-level constraint with 'holds'
  let noLayerArch = arch "no-layers" $ do
        declare order
        constrain "has-layers"
          "architecture must define layers" $
          holds "no layers defined" (not . null . archLayers)

      r3 = check noLayerArch
  T.putStrLn (prettyCheck r3)

  -- 'forbid' constraint
  let forbidArch = arch "forbid-test" $ do
        useLayers [core]
        declare order
        constrain "no-model-meta"
          "models should not have meta" $
          forbid Model "has meta" (not . null . declMeta)

      r4 = check forbidArch

  -- Manifest round-trip of constraints
  let m = manifest goodArch
      json = renderManifest m
      parsed = parseManifest json

  runTests
    [ ("satisfied constraint: no violations",
        not (hasViolations r1))
    , ("violated constraint: has violations",
        hasViolations r2)
    , ("violated constraint: code starts with C:",
        any (\d -> "C:" `T.isPrefixOf` dCode d) (violations r2))
    , ("violated constraint: mentions BareAdapter",
        any (\d -> "BareAdapter" `T.isInfixOf` dMessage d) (violations r2))
    , ("holds: no layers → violation",
        hasViolations r3)
    , ("holds: violation code",
        any (\d -> dCode d == "C:has-layers") (violations r3))
    , ("forbid: order has no meta → pass",
        not (hasViolations r4))
    , ("constraints in manifest",
        length (mConstraints m) == 1)
    , ("manifest constraint name",
        mcName (head (mConstraints m)) == "adapter-has-impl")
    , ("manifest constraint desc",
        mcDesc (head (mConstraints m)) == "every adapter must implement a boundary")
    , ("constraints round-trip",
        fmap (length . mConstraints) parsed == Just 1)
    , ("constraints in json",
        "constraints" `T.isInfixOf` json)
    ]

----------------------------------------------------------------------
-- Relation tests
----------------------------------------------------------------------

testRelations :: TestResult
testRelations = do
  -- Architecture with explicit relations
  let relArch = arch "rel-test" $ do
        useLayers [core, application, interface, infra]
        useTypes  [money]
        registerType "UUID"
        declare order
        declare orderRepo
        declare paymentGateway
        declare placeOrder
        declare cancelOrder
        declare getOrder
        declare postgresOrderRepo
        declare stripePayment
        declare appRoot

        relate "uses" getOrder placeOrder
        relate "publishes" placeOrder order

      allRels = relations relArch
      poRels  = relationsOf "PlaceOrder" relArch

  -- Manifest round-trip
  let m = manifest relArch
      json = renderManifest m
      parsed = parseManifest json

  runTests
    [ ("relations extracts needs",
        any (\r -> relKind r == "needs" && relSource r == "PlaceOrder"
                && relTarget r == "OrderRepository") allRels)
    , ("relations extracts implements",
        any (\r -> relKind r == "implements" && relSource r == "PostgresOrderRepo"
                && relTarget r == "OrderRepository") allRels)
    , ("relations extracts bind",
        any (\r -> relKind r == "bind" && relSource r == "AppRoot"
                && relTarget r == "OrderRepository") allRels)
    , ("relations extracts entry",
        any (\r -> relKind r == "entry") allRels)
    , ("relations extracts field references",
        any (\r -> relKind r == "references" && relSource r == "Order") allRels)
    , ("relations includes explicit",
        any (\r -> relKind r == "uses" && relSource r == "GetOrder"
                && relTarget r == "PlaceOrder") allRels)
    , ("relationsOf filters by source",
        all (\r -> relSource r == "PlaceOrder") poRels)
    , ("dependsOn returns needs",
        "OrderRepository" `elem` dependsOn "PlaceOrder" relArch)
    , ("dependsOn returns both needs",
        length (dependsOn "PlaceOrder" relArch) == 2)
    , ("implementedBy finds adapter",
        "PostgresOrderRepo" `elem` implementedBy "OrderRepository" relArch)
    , ("boundTo finds adapter",
        "PostgresOrderRepo" `elem` boundTo "OrderRepository" relArch)
    , ("transitive follows needs chain",
        let deps = transitive ["needs"] "PlaceOrder" relArch
        in "OrderRepository" `Set.member` deps && "PaymentGateway" `Set.member` deps)
    , ("reachable follows all edges",
        let reach = reachable "PlaceOrder" relArch
        in "PlaceOrder" `Set.member` reach && "OrderRepository" `Set.member` reach)
    , ("isAcyclic: needs is acyclic",
        isAcyclic ["needs"] relArch)
    , ("typeRefs extracts TRef",
        typeRefs (listOf order) == ["Order"])
    , ("typeRefs extracts nullable",
        typeRefs (nullable (ref order)) == ["Order"])
    , ("manifest has explicit relations",
        length (mRelations m) == 2)
    , ("manifest relation round-trip",
        fmap (length . mRelations) parsed == Just 2)
    , ("relations in json",
        "\"relations\"" `T.isInfixOf` json)
    ]

----------------------------------------------------------------------
-- Algebra tests
----------------------------------------------------------------------

testAlgebra :: TestResult
testAlgebra = do
  -- Two separate architectures
  let orderArch = arch "order" $ do
        useLayers [core, interface]
        registerType "UUID"
        declare order
        declare orderRepo

      paymentArch = arch "payment" $ do
        useLayers [core, interface, infra]
        declare paymentGateway
        declare stripePayment

      -- merge
      merged = merge "platform" orderArch paymentArch
      -- mergeAll
      merged2 = mergeAll "platform" [orderArch, paymentArch]

  -- project
  let domainOnly = projectLayer "core" merged
      boundariesOnly = projectKind Boundary merged

  -- diff
  let v1 = arch "svc" $ do
        useLayers [core, interface]
        declare order
        declare orderRepo
      v2 = arch "svc" $ do
        useLayers [core, interface, infra]
        declare order
        declare paymentGateway
        declare stripePayment
      d = diff v1 v2

  runTests
    [ ("merge: combined name",
        archName merged == "platform")
    , ("merge: layers deduplicated",
        length (archLayers merged) == 3)  -- core, interface, infra (deduped)
    , ("merge: all decls present",
        length (archDecls merged) == 4)
    , ("merge: customTypes combined",
        "UUID" `elem` archCustomTypes merged)
    , ("mergeAll: same result as merge",
        archDecls merged2 == archDecls merged)
    , ("mergeAll: empty list gives empty arch",
        null (archDecls (mergeAll "empty" [])))
    , ("project: core has Order",
        any (\d' -> declName d' == "Order") (archDecls domainOnly))
    , ("project: core has no Boundary",
        all (\d' -> declKind d' /= Boundary) (archDecls domainOnly))
    , ("projectKind: Boundary only",
        all (\d' -> declKind d' == Boundary) (archDecls boundariesOnly))
    , ("projectKind: keeps OrderRepository",
        any (\d' -> declName d' == "OrderRepository") (archDecls boundariesOnly))
    , ("diff: added decls",
        length [() | Added _ <- diffDecls d] == 2)  -- PaymentGateway, StripePayment
    , ("diff: removed decls",
        length [() | Removed _ <- diffDecls d] == 1)  -- OrderRepository
    , ("diff: unchanged decl (Order)",
        null [() | Modified _ _ <- diffDecls d])
    , ("diff: added layer",
        length (fst (diffLayers d)) == 1)  -- infra added
    , ("diff: no removed layers",
        null (snd (diffLayers d)))
    ]

----------------------------------------------------------------------
-- Manifest round-trip tests
----------------------------------------------------------------------

testManifest :: TestResult
testManifest = do
  let m = manifest coreArch
      json = renderManifest m
      parsed = parseManifest json
  runTests
    [ ("round-trip parses",       parsed /= Nothing)
    , ("round-trip name",         fmap mName parsed == Just "order-service")
    , ("round-trip version",      fmap mVersion parsed == Just "0.6")
    , ("round-trip layers",       fmap (length . mLayers) parsed == Just 4)
    , ("round-trip decls",        fmap (length . mDecls) parsed == Just (length (archDecls coreArch)))
    , ("round-trip bindings",     fmap (length . mBindings) parsed == Just 2)
    , ("type aliases present",    not (null (mTypeAliases m)))
    , ("type alias name",         mtaName (head (mTypeAliases m)) == "Money")
    , ("type alias type",         mtaType (head (mTypeAliases m)) == "Decimal")
    , ("decl has meta",
        let statusDecl = head [d | d <- mDecls m, mdName d == "OrderStatus"]
        in  not (null (mdMeta statusDecl)))
    , ("decl has paths",
        let orderDecl = head [d | d <- mDecls m, mdName d == "Order"]
        in  mdPaths orderDecl == ["domain/order.go"])
    , ("operation has inputs",
        let poDecl = head [d | d <- mDecls m, mdName d == "PlaceOrder"]
        in  not (null (mdInputs poDecl)))
    , ("operation has outputs",
        let poDecl = head [d | d <- mDecls m, mdName d == "PlaceOrder"]
        in  not (null (mdOutputs poDecl)))
    , ("schema_version in json",  "schema_version" `T.isInfixOf` json)
    , ("type_aliases in json",    "type_aliases" `T.isInfixOf` json)
    ]

----------------------------------------------------------------------
-- Evidence tests
----------------------------------------------------------------------

testEvidence :: TestResult
testEvidence = do
  -- Evidence on a clean architecture
  let r = check coreArch
      ev = evidence r
  -- Evidence on constrained architecture
  let constrainedArch = arch "constrained" $ do
        useLayers [core, interface, infra]
        registerType "UUID"
        declare order
        declare orderRepo
        declare postgresOrderRepo
        constrain "adapter-has-impl"
          "every adapter must implement a boundary" $
          require Adapter "has no implements"
            (\d -> isJust (findImplements (declBody d)))
        constrain "has-layers"
          "must have layers" $
          holds "no layers defined" (not . null . archLayers)
      r2 = check constrainedArch
      ev2 = evidence r2
  -- Violated constraint: evidence should only contain passing constraints
  let noImplAdapter = adapter "BareAdapter" infra $ do
        inject "db" (ext "*sql.DB")
      badArch = arch "bad" $ do
        useLayers [core, infra]
        declare noImplAdapter
        constrain "adapter-has-impl"
          "must implement" $
          require Adapter "has no implements"
            (\d -> isJust (findImplements (declBody d)))
        constrain "has-layers"
          "must have layers" $
          holds "no layers" (not . null . archLayers)
      r3 = check badArch
      ev3 = evidence r3
  runTests
    [ ("evidence records checked rules",
        not (null (ceCheckedRules ev)))
    , ("evidence includes V001",
        "V001" `elem` ceCheckedRules ev)
    , ("evidence includes V009",
        "V009" `elem` ceCheckedRules ev)
    , ("clean arch: no constraints to pass",
        null (cePassedConstraints ev))
    , ("constrained: both constraints pass",
        length (cePassedConstraints ev2) == 2)
    , ("constrained: adapter-has-impl passes",
        "adapter-has-impl" `elem` cePassedConstraints ev2)
    , ("constrained: has-layers passes",
        "has-layers" `elem` cePassedConstraints ev2)
    , ("violated: only has-layers passes",
        cePassedConstraints ev3 == ["has-layers"])
    , ("violated: adapter-has-impl not in passed",
        "adapter-has-impl" `notElem` cePassedConstraints ev3)
    , ("evidence is monoidal identity",
        evidence mempty == mempty)
    ]

----------------------------------------------------------------------
-- Algebraic property tests
----------------------------------------------------------------------

testAlgebraicProperties :: TestResult
testAlgebraicProperties = do
  -- Test architectures
  let archA = arch "a" $ do
        useLayers [core, interface]
        registerType "UUID"
        declare order
        declare orderRepo

      archB = arch "b" $ do
        useLayers [core, interface, infra]
        declare paymentGateway
        declare stripePayment

      archC = arch "c" $ do
        useLayers [core, application]
        declare placeOrder
        declare cancelOrder

      empty_ = mergeAll "empty" []

  -- merge associativity: merge (merge A B) C ≡ merge A (merge B C)
  -- (when no name collisions — guaranteed here since all decl names are unique)
  let ab_c = merge "x" (merge "x" archA archB) archC
      a_bc = merge "x" archA (merge "x" archB archC)

  -- merge idempotency: merge A A ≡ A (structurally, modulo name)
  let aa = merge "a" archA archA

  -- merge identity: merge A empty ≡ A (structurally)
  let a_empty = merge "a" archA empty_
      empty_a = merge "a" empty_ archA

  -- project idempotency: project p (project p a) ≡ project p a
  let merged = merge "all" archA archB
      proj1 = projectLayer "core" merged
      proj2 = projectLayer "core" proj1

  let projK1 = projectKind Boundary merged
      projK2 = projectKind Boundary projK1

  -- project predicate idempotency
  let pred_ d = declKind d == Model
      pProj1 = project pred_ merged
      pProj2 = project pred_ pProj1

  -- mergeAll ≡ foldl merge
  let byMergeAll = mergeAll "x" [archA, archB, archC]
      byFold     = merge "x" (merge "x" archA archB) archC

  -- diff symmetry: additions in diff A B correspond to removals in diff B A
  let d_ab = diff archA archB
      d_ba = diff archB archA
      addedInAB   = length [() | Added _ <- diffDecls d_ab]
      removedInBA = length [() | Removed _ <- diffDecls d_ba]
      removedInAB = length [() | Removed _ <- diffDecls d_ab]
      addedInBA   = length [() | Added _ <- diffDecls d_ba]

  -- diff identity: diff A A has no changes
  let d_aa = diff archA archA

  runTests
    [ ("merge assoc: same decl count",
        length (archDecls ab_c) == length (archDecls a_bc))
    , ("merge assoc: same decl names",
        Set.fromList (map declName (archDecls ab_c))
          == Set.fromList (map declName (archDecls a_bc)))
    , ("merge assoc: same layer count",
        length (archLayers ab_c) == length (archLayers a_bc))
    , ("merge assoc: same layer names",
        Set.fromList (map layerName (archLayers ab_c))
          == Set.fromList (map layerName (archLayers a_bc)))
    , ("merge idempotent: same decl count",
        length (archDecls aa) == length (archDecls archA))
    , ("merge idempotent: same decls",
        map declName (archDecls aa) == map declName (archDecls archA))
    , ("merge right identity: decls preserved",
        map declName (archDecls a_empty) == map declName (archDecls archA))
    , ("merge left identity: decls preserved",
        map declName (archDecls empty_a) == map declName (archDecls archA))
    , ("project idempotent (layer): same decls",
        map declName (archDecls proj1) == map declName (archDecls proj2))
    , ("project idempotent (kind): same decls",
        map declName (archDecls projK1) == map declName (archDecls projK2))
    , ("project idempotent (pred): same decls",
        map declName (archDecls pProj1) == map declName (archDecls pProj2))
    , ("mergeAll ≡ foldl merge: same decls",
        Set.fromList (map declName (archDecls byMergeAll))
          == Set.fromList (map declName (archDecls byFold)))
    , ("diff symmetry: added/removed correspondence",
        addedInAB == removedInBA && removedInAB == addedInBA)
    , ("diff identity: no changes",
        null (diffDecls d_aa))
    , ("diff identity: no layer changes",
        fst (diffLayers d_aa) == [] && snd (diffLayers d_aa) == [])
    ]
