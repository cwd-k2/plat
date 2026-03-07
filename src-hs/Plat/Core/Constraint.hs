-- | アーキテクチャ制約の述語コンビネータ。
--
-- 'Plat.Core.Builder.constrain' と組み合わせて使う。
--
-- @
-- constrain "adapter-has-impl"
--   "every adapter must implement a boundary" $
--   require Adapter "has no implements"
--     (\\d -> isJust (findImplements (declBody d)))
-- @
module Plat.Core.Constraint
  ( -- * Declaration-level predicates
    require
  , forbid
  , forAll

    -- * Architecture-level predicates
  , holds
  ) where

import Data.Text (Text)

import Plat.Core.Types

-- | 指定種の全宣言に述語を適用し、結果を集約する。
--
-- 各宣言に対して検査関数を適用し、返された違反メッセージを連結する。
-- 'require' と 'forbid' のプリミティブ。
forAll :: DeclKind -> (Declaration -> [Text]) -> Architecture -> [Text]
forAll k f a = concatMap f [d | d <- archDecls a, declKind d == k]

-- | 指定種の全宣言が述語を満たすことを要求する。
--
-- 述語が 'False' を返す宣言について、その名前と指定メッセージを違反として報告する。
require :: DeclKind -> Text -> (Declaration -> Bool) -> Architecture -> [Text]
require k msg p = forAll k $ \d ->
  [declName d <> ": " <> msg | not (p d)]

-- | 指定種のいかなる宣言も述語を満たさないことを要求する。
--
-- 述語が 'True' を返す宣言について、その名前と指定メッセージを違反として報告する。
forbid :: DeclKind -> Text -> (Declaration -> Bool) -> Architecture -> [Text]
forbid k msg p = forAll k $ \d ->
  [declName d <> ": " <> msg | p d]

-- | アーキテクチャ全体の性質を検査する。
--
-- 述語が 'False' なら指定メッセージを違反として報告する。
holds :: Text -> (Architecture -> Bool) -> Architecture -> [Text]
holds msg p a = [msg | not (p a)]
