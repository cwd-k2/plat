module Test.Harness
  ( TestResult
  , runTests
  , section
  ) where

import System.Exit (exitFailure)

-- | Returns (total, failures)
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

section :: String -> IO (Int, Int) -> IO (Int, Int)
section name act = do
  putStrLn $ "\n--- " ++ name ++ " ---"
  act
