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

    -- * Constraint composition
  , oneOf
  , neg
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

----------------------------------------------------------------------
-- Constraint composition
--
-- Architecture -> [Text] は Monoid なので、論理積には標準の (<>) / mconcat を使う:
--
-- @
-- constrain "strict" "adapter rules" $
--   require Adapter "..." p1 <> forbid Model "..." p2
-- @
----------------------------------------------------------------------

-- | 複数の検査関数の論理和。いずれか一つでも違反なしなら全体を通過とする。
--
-- 全て違反ありの場合のみ、最初の検査関数の違反を報告する。
--
-- @
-- constrain "flexible" "at least one pattern" $
--   oneOf [require Adapter "..." p1, require Adapter "..." p2]
-- @
oneOf :: [Architecture -> [Text]] -> Architecture -> [Text]
oneOf [] _ = []
oneOf fs a = case [f a | f <- fs] of
  results | any null results -> []
  (r:_)                      -> r
  _                          -> []

-- | 検査関数の否定。違反なしを違反とし、違反ありを通過とする。
--
-- @
-- constrain "no-models-in-infra" "..." $
--   neg (require Model "must exist in infra" (\\d -> declLayer d == Just "infra"))
-- @
neg :: Text -> (Architecture -> [Text]) -> Architecture -> [Text]
neg msg f a = case f a of
  [] -> [msg]
  _  -> []
