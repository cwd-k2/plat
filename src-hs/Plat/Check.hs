-- | 検証エンジン
module Plat.Check
  ( -- * Check API
    check
  , checkWith
  , checkIO
  , checkOrFail
  , prettyCheck

    -- * Re-exports
  , CheckResult (..)
  , Diagnostic (..)
  , Severity (..)
  , SomeRule (..)
  , PlatRule (..)
  , coreRules
  , hasViolations
  , hasWarnings
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import System.Exit (exitFailure)
import System.Directory (doesFileExist)
import Control.Monad (when)

import Plat.Core.Types
import Plat.Check.Class
import Plat.Check.Rules

-- | 純粋な検証（coreRules を使用）
check :: Architecture -> CheckResult
check = checkWith coreRules

-- | 指定ルールで検証（アーキテクチャ制約も評価される）
checkWith :: [SomeRule] -> Architecture -> CheckResult
checkWith rules arch = ruleResults <> constraintResults
  where
    ruleResults = mconcat
      [ classify rule diag
      | SomeRule rule <- rules
      , diag <- checkArch rule arch
              ++ concatMap (checkDecl rule arch) (archDecls arch)
      ]
    classify :: PlatRule a => a -> Diagnostic -> CheckResult
    classify _ d = case dSeverity d of
      Error   -> CheckResult [d] []
      Warning -> CheckResult [] [d]
    constraintResults = CheckResult
      [ Diagnostic Error ("C:" <> acName c) msg (acName c) Nothing
      | c <- archConstraints arch
      , msg <- acCheck c arch
      ]
      []

-- | IO 検証（W003: ファイル存在確認を含む）
checkIO :: Architecture -> IO CheckResult
checkIO arch = do
  let pureResult = check arch
  pathResult <- checkPaths arch
  pure (pureResult <> pathResult)

-- | W003: @path のファイル不在チェック
checkPaths :: Architecture -> IO CheckResult
checkPaths arch = fmap mconcat $ sequence
  [ do exists <- doesFileExist fp
       pure $ if exists then mempty
              else CheckResult []
                [ Diagnostic Warning "W003"
                    ("file " <> T.pack fp <> " does not exist")
                    (declName d) (Just (T.pack fp))
                ]
  | d <- archDecls arch
  , fp <- declPaths d
  ]

-- | 検証結果を人間可読なテキストに変換
prettyCheck :: CheckResult -> Text
prettyCheck (CheckResult vs ws)
  | null vs && null ws = "All checks passed."
  | otherwise = T.unlines $
      map prettyDiag vs ++ map prettyDiag ws ++
      [ T.pack (show (length vs)) <> " error(s), "
        <> T.pack (show (length ws)) <> " warning(s)"
      ]

prettyDiag :: Diagnostic -> Text
prettyDiag d = mconcat
  [ bracket (dSeverity d)
  , " ", dCode d
  , ": ", dMessage d
  , " (", dSource d
  , maybe "" (\t -> " -> " <> t) (dTarget d)
  , ")"
  ]
  where
    bracket Error   = "[ERROR]"
    bracket Warning = "[WARN] "

-- | violation があれば exitFailure
checkOrFail :: Architecture -> IO ()
checkOrFail arch = do
  ioResult <- checkIO arch
  T.putStrLn (prettyCheck ioResult)
  when (hasViolations ioResult) exitFailure
