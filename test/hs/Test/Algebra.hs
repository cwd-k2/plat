module Test.Algebra
  ( testAlgebra
  , testAlgebraicProperties
  , testCompatibility
  ) where

import Plat.Core

import qualified Data.Set as Set
import qualified Data.Text as T

import Test.Harness
import Test.Fixtures

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

----------------------------------------------------------------------

testCompatibility :: TestResult
testCompatibility = do
  -- Two compatible architectures (no overlapping decls)
  let archA = arch "a" $ do
        useLayers [core, interface]
        declare order
        declare orderRepo

      archB = arch "b" $ do
        useLayers [core, interface, infra]
        declare paymentGateway
        declare stripePayment

  -- Architecture with same decl, same structure → compatible
  let archC = arch "c" $ do
        useLayers [core]
        declare order  -- same as archA's order

  -- Architecture with same name but different kind
  let conflictModel = model "OrderRepository" core $
        field "x" string
      archConflictKind = arch "d" $ do
        useLayers [core]
        declare conflictModel

  -- Architecture with same name but different layer
  let orderInfra = model "Order" infra $ do
        field "id" uuid
      archConflictLayer = arch "e" $ do
        useLayers [core, infra]
        declare orderInfra

  -- Architecture with same layer name but different deps
  let coreWithDeps = layer "core" `depends` [interface]
      archConflictLayerDeps = arch "f" $ do
        useLayers [coreWithDeps]  -- core depends on interface, unlike archA's core

  runTests
    [ ("no overlap → compatible",
        null (isCompatible archA archB))
    , ("same decl same structure → compatible",
        null (isCompatible archA archC))
    , ("kind mismatch → conflict",
        any (\c -> T.isInfixOf "kind mismatch" (conflictDesc c))
            (isCompatible archA archConflictKind))
    , ("layer mismatch → conflict",
        any (\c -> T.isInfixOf "layer mismatch" (conflictDesc c))
            (isCompatible archA archConflictLayer))
    , ("layer deps mismatch → conflict",
        any (\c -> T.isInfixOf "layer dependency mismatch" (conflictDesc c))
            (isCompatible archA archConflictLayerDeps))
    , ("conflict count for kind mismatch",
        length (isCompatible archA archConflictKind) >= 1)
    ]
