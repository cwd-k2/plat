module Test.Relation
  ( testRelations
  , testMetaRelations
  ) where

import Plat.Core
import Plat.Ext.Events
import Plat.Ext.Modules
import Plat.Verify.Manifest

import qualified Data.Set as Set
import qualified Data.Text as T

import Test.Harness
import Test.Fixtures

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
    , ("cyclicGroups: no cycles in acyclic graph",
        null (cyclicGroups ["needs"] relArch))
    , ("cyclicGroups: detects cycle",
        let a = model "CycA" core $ field "x" string
            b = model "CycB" core $ field "y" string
            cycArch = arch "cyc-test" $ do
              useLayers [core]
              declare a
              declare b
              relate "dep" a b
              relate "dep" b a
            gs = cyclicGroups ["dep"] cycArch
        in not (null gs) && not (isAcyclic ["dep"] cycArch))
    , ("typeRefs extracts TRef",
        typeRefs (listOf order) == ["Order"])
    , ("typeRefs extracts nullable",
        typeRefs (nullable (ref order)) == ["Order"])
    , ("typeRefs excludes TExt",
        typeRefs (ext "*sql.DB") == [])
    , ("manifest has explicit relations",
        length (mRelations m) == 2)
    , ("manifest relation round-trip",
        fmap (length . mRelations) parsed == Just 2)
    , ("relations in json",
        "\"relations\"" `T.isInfixOf` json)
    ]

----------------------------------------------------------------------
-- Meta-derived relations
----------------------------------------------------------------------

testMetaRelations :: TestResult
testMetaRelations = do
  -- Events: emit, on_, apply
  let orderPlaced = event "OrderPlaced" core $ do
        field "orderId" uuid
        field "total" decimal

      placeOrderEvt = operation "PlaceOrderEvt" application $ do
        input "order" (ref order)
        output "err" error_
        needs orderRepo
        emit orderPlaced

      onOrderPlaced = on_ "HandleOrderPlaced" orderPlaced application $ do
        output "err" error_
        needs orderRepo

      orderAgg = model "OrderAggregate" core $ do
        field "id" uuid
        apply orderPlaced

  -- Modules: expose, import_
  let orderDomain = domain "OrderDomain" $ do
        expose order
        expose orderRepo

      paymentDomain = domain "PaymentDomain" $ do
        import_ orderDomain order
        expose paymentGateway

  let evtArch = arch "meta-rel-test" $ do
        useLayers [core, application, interface, infra]
        useTypes  [money]
        registerType "UUID"
        declare order
        declare orderRepo
        declare paymentGateway
        declare postgresOrderRepo
        declare stripePayment
        declare orderPlaced
        declare placeOrderEvt
        declare onOrderPlaced
        declare orderAgg
        declare orderDomain
        declare paymentDomain

      allRels = relations evtArch

  runTests
    [ ("emits relation from emit",
        any (\r -> relKind r == "emits" && relSource r == "PlaceOrderEvt"
                && relTarget r == "OrderPlaced") allRels)
    , ("subscribes relation from on_",
        any (\r -> relKind r == "subscribes" && relSource r == "HandleOrderPlaced"
                && relTarget r == "OrderPlaced") allRels)
    , ("applies relation from apply",
        any (\r -> relKind r == "applies" && relSource r == "OrderAggregate"
                && relTarget r == "OrderPlaced") allRels)
    , ("exposes relation from expose",
        any (\r -> relKind r == "exposes" && relSource r == "OrderDomain"
                && relTarget r == "Order") allRels)
    , ("exposes OrderRepository",
        any (\r -> relKind r == "exposes" && relSource r == "OrderDomain"
                && relTarget r == "OrderRepository") allRels)
    , ("imports relation from import_",
        any (\r -> relKind r == "imports" && relSource r == "PaymentDomain"
                && relTarget r == "Order") allRels)
    , ("imports has from-module meta",
        any (\r -> relKind r == "imports" && relSource r == "PaymentDomain"
                && lookup "from-module" (relMeta r) == Just "OrderDomain") allRels)
    , ("forwardImpact traces through events",
        let impact = forwardImpact "OrderPlaced" evtArch
        in "HandleOrderPlaced" `Set.member` impact
           || "OrderAggregate" `Set.member` impact)
    , ("reachable from emitter through event",
        let reach = reachable "PlaceOrderEvt" evtArch
        in "OrderPlaced" `Set.member` reach)
    ]
