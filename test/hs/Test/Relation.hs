module Test.Relation
  ( testRelations
  ) where

import Plat.Core
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
