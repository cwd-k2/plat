module Plat.Check.Class
  ( -- * Rule type class
    PlatRule (..)
  , SomeRule (..)

    -- * Diagnostics
  , Diagnostic (..)
  , Severity (..)
  , CheckResult (..)
  , hasViolations
  , hasWarnings
  ) where

import Data.Text (Text)

import Plat.Core.Types (Architecture, Declaration)

-- | 診断の重大度
data Severity = Error | Warning
  deriving stock (Show, Eq, Ord)

-- | 診断結果
data Diagnostic = Diagnostic
  { dSeverity :: Severity
  , dCode     :: Text
  , dMessage  :: Text
  , dSource   :: Text
  , dTarget   :: Maybe Text
  } deriving stock (Show, Eq)

-- | 検証結果
data CheckResult = CheckResult
  { violations :: [Diagnostic]
  , warnings   :: [Diagnostic]
  } deriving stock (Show, Eq)

instance Semigroup CheckResult where
  CheckResult v1 w1 <> CheckResult v2 w2 = CheckResult (v1 <> v2) (w1 <> w2)

instance Monoid CheckResult where
  mempty = CheckResult [] []

hasViolations :: CheckResult -> Bool
hasViolations = not . null . violations

hasWarnings :: CheckResult -> Bool
hasWarnings = not . null . warnings

-- | 検証ルールの型クラス
class PlatRule a where
  ruleCode  :: a -> Text
  checkDecl :: a -> Architecture -> Declaration -> [Diagnostic]
  checkDecl _ _ _ = []
  checkArch :: a -> Architecture -> [Diagnostic]
  checkArch _ _ = []

-- | 存在型ラッパー
data SomeRule where
  SomeRule :: PlatRule a => a -> SomeRule

