module Test.Constraint
  ( testConstraints
  , testConstraintComposition
  ) where

import Plat.Core
import Plat.Check
import Plat.Verify.Manifest

import Data.Maybe (isJust)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as T

import Test.Harness
import Test.Fixtures

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

testConstraintComposition :: TestResult
testConstraintComposition = do
  let archWithConstraints = arch "constrained" $ do
        useLayers [core, application, interface, infra]
        useTypes  [money]
        registerType "UUID"
        declare order
        declare orderRepo
        declare placeOrder
        declare postgresOrderRepo

      -- Simple predicates for testing
      hasModels  = require Model "no models" (const True)
      neverPass  = holds "always fails" (const False)
      alwaysPass = holds "always passes" (const True)

  runTests
    [ ("(<>): combines violations",
        length ((neverPass <> neverPass) archWithConstraints) == 2)
    , ("(<>): one passes one fails",
        length ((alwaysPass <> neverPass) archWithConstraints) == 1)
    , ("(<>): both pass",
        null ((alwaysPass <> hasModels) archWithConstraints))
    , ("mconcat: empty list passes",
        null (mconcat ([] :: [Architecture -> [Text]]) archWithConstraints))
    , ("mconcat: all pass",
        null (mconcat [alwaysPass, hasModels] archWithConstraints))
    , ("mconcat: one fails",
        length (mconcat [alwaysPass, neverPass] archWithConstraints) == 1)
    , ("mconcat: all fail",
        length (mconcat [neverPass, neverPass] archWithConstraints) == 2)
    , ("oneOf: empty list passes",
        null (oneOf [] archWithConstraints))
    , ("oneOf: one passes",
        null (oneOf [neverPass, alwaysPass] archWithConstraints))
    , ("oneOf: all pass",
        null (oneOf [alwaysPass, hasModels] archWithConstraints))
    , ("oneOf: all fail → reports first",
        oneOf [neverPass, neverPass] archWithConstraints
          == neverPass archWithConstraints)
    , ("neg: inverts pass to fail",
        length (neg "should fail" alwaysPass archWithConstraints) == 1)
    , ("neg: inverts fail to pass",
        null (neg "inverted" neverPass archWithConstraints))
    , ("composition: (<>) + neg",
        null ((hasModels <> neg "no models" neverPass) archWithConstraints))
    ]
