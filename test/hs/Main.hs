module Main where

import System.Exit (exitFailure)

import Test.Harness
import Test.Core
import Test.Ext
import Test.Constraint
import Test.Relation
import Test.Algebra
import Test.Evidence
import Test.Manifest

main :: IO ()
main = do
  writeGoldenManifest
  results <- sequence
    [ section "Core eDSL"          testCoreEdsl
    , section "Check"              testCheck
    , section "Layer violations"   testLayerViolations
    , section "Ext.DDD"            testDDD
    , section "Ext.CQRS"          testCQRS
    , section "Ext.CleanArch"     testCleanArch
    , section "Ext.Http"          testHttp
    , section "Ext.DBC"           testDBC
    , section "Ext.Flow"          testFlow
    , section "Ext.Events"        testEvents
    , section "Ext.Modules"       testModules
    , section "Ext.MultiService"  testMultiService
    , section "Meta-programming"  testMetaProgramming
    , section "V009/W003"         testNewRules
    , section "Constraints"       testConstraints
    , section "Relations"         testRelations
    , section "Meta relations"    testMetaRelations
    , section "Algebra"           testAlgebra
    , section "Manifest"          testManifest
    , section "Evidence"          testEvidence
    , section "Algebraic props"   testAlgebraicProperties
    , section "Constraint comp"   testConstraintComposition
    , section "Compatibility"     testCompatibility
    , section "Custom rule API"   testCustomRuleApi
    , section "Validated"         testValidated
    ]
  let total   = sum (map fst results)
      failed  = sum (map snd results)
  putStrLn $ "\n=== " ++ show total ++ " tests, " ++ show failed ++ " failures ==="
  if failed > 0 then exitFailure else pure ()
