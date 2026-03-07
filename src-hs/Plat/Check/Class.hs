-- | 検証ルールの型クラスと診断結果の定義。
--
-- 'PlatRule' 型クラスでルールを定義し、'SomeRule' 存在型で合成する。
-- 検証結果は 'CheckResult' に集約される。
module Plat.Check.Class
  ( -- * Rule type class
    PlatRule (..)
  , SomeRule (..)

    -- * Diagnostics
  , Diagnostic (..)
  , Severity (..)
  , CheckResult (..)
  , CheckEvidence (..)
  , hasViolations
  , hasWarnings

    -- * Validated architecture
  , Validated (..)
  , validate
  , unvalidate
  ) where

import Data.Text (Text)

import Plat.Core.Types (Architecture, Declaration)

-- | 診断の重大度
data Severity = Error | Warning
  deriving stock (Show, Eq, Ord)

-- | 診断結果
data Diagnostic = Diagnostic
  { dSeverity :: Severity   -- ^ 重大度 ('Error' または 'Warning')
  , dCode     :: Text       -- ^ ルールコード (例: @"V001"@)
  , dMessage  :: Text       -- ^ 人間向けのメッセージ
  , dSource   :: Text       -- ^ 違反元の宣言名
  , dTarget   :: Maybe Text -- ^ 違反先の宣言名 (存在する場合)
  } deriving stock (Show, Eq)

-- | 検証通過の証拠。どのルール・制約が適用され、何が充足されたかを記録する。
--
-- @merge@ / @project@ 後はアーキテクチャが変わるため、証拠は無効になる。
-- 再検証が必要かどうかの判断に使える。
data CheckEvidence = CheckEvidence
  { ceCheckedRules      :: [Text]  -- ^ 適用されたルールコードのリスト
  , cePassedConstraints :: [Text]  -- ^ 充足されたアーキテクチャ制約名のリスト
  } deriving stock (Show, Eq)

instance Semigroup CheckEvidence where
  CheckEvidence r1 c1 <> CheckEvidence r2 c2 =
    CheckEvidence (r1 <> r2) (c1 <> c2)

instance Monoid CheckEvidence where
  mempty = CheckEvidence [] []

-- | 検証結果。'Monoid' で複数ルールの結果を合成可能。
data CheckResult = CheckResult
  { violations :: [Diagnostic]    -- ^ 'Error' レベルの診断
  , warnings   :: [Diagnostic]    -- ^ 'Warning' レベルの診断
  , evidence   :: CheckEvidence   -- ^ 検証通過の証拠
  } deriving stock (Show, Eq)

instance Semigroup CheckResult where
  CheckResult v1 w1 e1 <> CheckResult v2 w2 e2 =
    CheckResult (v1 <> v2) (w1 <> w2) (e1 <> e2)

instance Monoid CheckResult where
  mempty = CheckResult [] [] mempty

-- | 'Error' レベルの診断が存在するか
hasViolations :: CheckResult -> Bool
hasViolations = not . null . violations

-- | 'Warning' レベルの診断が存在するか
hasWarnings :: CheckResult -> Bool
hasWarnings = not . null . warnings

-- | 検証ルールの型クラス。
-- 宣言単位の検査 ('checkDecl') とアーキテクチャ全体の検査 ('checkArch') を提供する。
class PlatRule a where
  -- | ルールコード (例: @"V001"@)
  ruleCode  :: a -> Text
  -- | 宣言単位の検査。デフォルトは空リスト。
  checkDecl :: a -> Architecture -> Declaration -> [Diagnostic]
  checkDecl _ _ _ = []
  -- | アーキテクチャ全体の検査。デフォルトは空リスト。
  checkArch :: a -> Architecture -> [Diagnostic]
  checkArch _ _ = []

-- | 'PlatRule' の存在型ラッパー。異なるルールをリストに格納可能にする。
data SomeRule where
  SomeRule :: PlatRule a => a -> SomeRule

----------------------------------------------------------------------
-- Validated architecture
----------------------------------------------------------------------

-- | 検証済みアーキテクチャ。'validate' でのみ構築される。
--
-- 'merge' / 'project' 等の代数的操作は 'Validated' を剥がすため、
-- 操作後は再検証が必要になる。これにより「検証済み」の不変条件が型で保証される。
--
-- @
-- case validate (check myArch) of
--   Left result -> T.putStrLn (prettyCheck result)  -- 違反あり
--   Right valid -> deploy (unvalidate valid)         -- 安全に使用
-- @
data Validated = Validated
  { validArch     :: Architecture    -- ^ 検証済みアーキテクチャ
  , validEvidence :: CheckEvidence   -- ^ 検証通過の証拠
  } deriving stock (Show, Eq)

-- | 検証結果から 'Validated' を構築する。違反がある場合は 'Left' を返す。
validate :: CheckResult -> Architecture -> Either CheckResult Validated
validate r a
  | hasViolations r = Left r
  | otherwise       = Right (Validated a (evidence r))

-- | 'Validated' から生の 'Architecture' を取り出す。
--
-- 代数的操作 ('merge', 'project' 等) に渡す際に使う。
-- 操作後は検証済み保証が失われる。
unvalidate :: Validated -> Architecture
unvalidate = validArch

