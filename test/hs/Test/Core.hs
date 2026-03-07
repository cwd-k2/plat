module Test.Core
  ( testCoreEdsl
  , testCheck
  , testRenderMermaid
  , testRenderMarkdown
  , testLayerViolations
  , testMetaProgramming
  , testNewRules
  ) where

import Plat.Core
import Plat.Check
import Plat.Generate.Mermaid (renderMermaid)
import Plat.Generate.Markdown (renderMarkdown)

import qualified Data.Text as T
import qualified Data.Text.IO as T

import Test.Harness
import Test.Fixtures

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
