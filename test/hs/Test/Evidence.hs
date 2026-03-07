module Test.Evidence
  ( testEvidence
  , testValidated
  ) where

import Plat.Core
import Plat.Check

import Test.Harness
import Test.Fixtures

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
          "every adapter must implement" $
          require Adapter "no impl"
            (\d -> any isImpl (declBody d))
        constrain "has-layers"
          "must have layers" $
          holds "no layers" (not . null . archLayers)
      r2 = check constrainedArch
      ev2 = evidence r2
  -- Violated constraint: evidence should only contain passing constraints
  let violatedArch = arch "violated" $ do
        declare order
        constrain "adapter-has-impl"
          "every adapter must implement" $
          require Adapter "no impl"
            (\d -> any isImpl (declBody d))
        constrain "has-layers"
          "must have layers" $
          holds "no layers" (not . null . archLayers)
      r3 = check violatedArch
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
        cePassedConstraints ev3 == ["adapter-has-impl"])
    , ("violated: adapter-has-impl not in passed",
        "has-layers" `notElem` cePassedConstraints ev3)
    , ("evidence is monoidal identity",
        evidence mempty == mempty)
    ]
  where
    isImpl (Implements _) = True
    isImpl _              = False

----------------------------------------------------------------------

testValidated :: TestResult
testValidated = do
  let r = check coreArch
  runTests
    [ ("validate clean arch → Right",
        case validate r coreArch of
          Right _ -> True
          Left  _ -> False)
    , ("validate preserves architecture",
        case validate r coreArch of
          Right v -> unvalidate v == coreArch
          Left  _ -> False)
    , ("validate preserves evidence",
        case validate r coreArch of
          Right v -> validEvidence v == evidence r
          Left  _ -> False)
    , ("validate with violations → Left",
        let badArch = arch "bad" $ do
              useLayers [core]
              declare order
              declare order  -- V009: duplicate declaration
            badR = check badArch
        in case validate badR badArch of
             Left _  -> True
             Right _ -> False)
    , ("validate warns-only arch → Right",
        let warnArch = arch "warn" $ do
              useLayers [core]
              declare order
            warnR = check warnArch
        in case validate warnR warnArch of
             Right _ -> True
             Left  _ -> False)
    ]
