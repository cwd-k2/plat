module Test.Manifest
  ( testManifest
  ) where

import Plat.Verify.Manifest

import qualified Data.Text as T

import Test.Harness
import Test.Fixtures

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
    , ("round-trip decls",        fmap (length . mDecls) parsed == Just (length (mDecls m)))
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
