-- | アーキテクチャ代数 — 合成・射影・比較。
--
-- Architecture を代数的に操作する関数群。マイクロサービス群の統合ビュー構築、
-- レイヤー単位の部分抽出、バージョン間差分検出に使う。
module Plat.Core.Algebra
  ( -- * Composition
    merge
  , mergeAll

    -- * Projection
  , project
  , projectLayer
  , projectKind

    -- * Comparison
  , ArchDiff (..)
  , DeclChange (..)
  , diff
  ) where

import Data.List (foldl')
import Data.Text (Text)
import qualified Data.Set as Set

import Plat.Core.Types

----------------------------------------------------------------------
-- Composition
----------------------------------------------------------------------

-- | 2 つの Architecture を合成する。名前の衝突は左優先で解決される。
--
-- @
-- system = merge "platform" orderService paymentService
-- @
merge :: Text -> Architecture -> Architecture -> Architecture
merge name a b = Architecture
  { archName        = name
  , archLayers      = nubBy' layerName (archLayers a ++ archLayers b)
  , archTypes       = nubBy' aliasName (archTypes a ++ archTypes b)
  , archCustomTypes = Set.toList (Set.fromList (archCustomTypes a ++ archCustomTypes b))
  , archDecls       = nubBy' declName  (archDecls a ++ archDecls b)
  , archConstraints = nubBy' acName    (archConstraints a ++ archConstraints b)
  , archRelations   = ordNub (archRelations a ++ archRelations b)
  , archMeta        = nubBy' fst       (archMeta a ++ archMeta b)
  }

-- | 複数の Architecture を合成する。空リストなら空のアーキテクチャを返す。
--
-- @
-- system = mergeAll "platform" [shared, orderService, paymentService]
-- @
mergeAll :: Text -> [Architecture] -> Architecture
mergeAll name = foldl' (merge name) empty
  where
    empty = Architecture name [] [] [] [] [] [] []

-- 左優先の名前ベース重複排除
nubBy' :: Ord k => (a -> k) -> [a] -> [a]
nubBy' f = go Set.empty
  where
    go _ [] = []
    go seen (x:xs)
      | f x `Set.member` seen = go seen xs
      | otherwise = x : go (Set.insert (f x) seen) xs

-- 順序保持の重複排除
ordNub :: (Eq a, Ord a) => [a] -> [a]
ordNub = go Set.empty
  where
    go _ [] = []
    go seen (x:xs)
      | x `Set.member` seen = go seen xs
      | otherwise = x : go (Set.insert x seen) xs

----------------------------------------------------------------------
-- Projection
----------------------------------------------------------------------

-- | 述語で Declaration をフィルタリングし、部分アーキテクチャを得る。
--
-- 除外された宣言を参照する Relation も自動的に除外される。
-- Constraint はそのまま保持される（検査関数が射影後の Architecture を受け取る）。
project :: (Declaration -> Bool) -> Architecture -> Architecture
project p a = a
  { archDecls     = kept
  , archRelations = filter relOk (archRelations a)
  }
  where
    kept  = filter p (archDecls a)
    names = Set.fromList (map declName kept)
    relOk r = relSource r `Set.member` names
           || relTarget r `Set.member` names

-- | 指定レイヤーの宣言のみを射影する。
projectLayer :: Text -> Architecture -> Architecture
projectLayer ly = project (\d -> declLayer d == Just ly)

-- | 指定種類の宣言のみを射影する。
projectKind :: DeclKind -> Architecture -> Architecture
projectKind k = project (\d -> declKind d == k)

----------------------------------------------------------------------
-- Comparison
----------------------------------------------------------------------

-- | 宣言の変更種別。
data DeclChange
  = Added Declaration           -- ^ 新規追加された宣言
  | Removed Declaration         -- ^ 削除された宣言
  | Modified Declaration Declaration  -- ^ 変更された宣言（旧, 新）
  deriving stock (Show, Eq)

-- | 2つの Architecture の構造的差分。
data ArchDiff = ArchDiff
  { diffDecls      :: [DeclChange]
  , diffLayers     :: ([LayerDef], [LayerDef])   -- ^ (追加, 削除)
  , diffRelations  :: ([Relation], [Relation])   -- ^ (追加, 削除)
  } deriving stock (Show, Eq)

-- | 2 つの Architecture の構造的差分を計算する。
--
-- @
-- let changes = diff v1Architecture v2Architecture
-- @
diff :: Architecture -> Architecture -> ArchDiff
diff old new = ArchDiff
  { diffDecls     = declChanges
  , diffLayers    = (addedLayers, removedLayers)
  , diffRelations = (addedRels, removedRels)
  }
  where
    -- Decl changes
    oldMap = [(declName d, d) | d <- archDecls old]
    newMap = [(declName d, d) | d <- archDecls new]
    oldNames = Set.fromList (map fst oldMap)
    newNames = Set.fromList (map fst newMap)

    added   = [Added d   | (n, d) <- newMap, n `Set.notMember` oldNames]
    removed = [Removed d | (n, d) <- oldMap, n `Set.notMember` newNames]
    modified = [ Modified o n
               | (name, n) <- newMap
               , name `Set.member` oldNames
               , Just o <- [lookup name oldMap]
               , o /= n
               ]
    declChanges = added ++ removed ++ modified

    -- Layer changes
    oldLayerNames = Set.fromList (map layerName (archLayers old))
    newLayerNames = Set.fromList (map layerName (archLayers new))
    addedLayers   = [l | l <- archLayers new, layerName l `Set.notMember` oldLayerNames]
    removedLayers = [l | l <- archLayers old, layerName l `Set.notMember` newLayerNames]

    -- Relation changes
    oldRelSet = Set.fromList (archRelations old)
    newRelSet = Set.fromList (archRelations new)
    addedRels   = Set.toList (Set.difference newRelSet oldRelSet)
    removedRels = Set.toList (Set.difference oldRelSet newRelSet)
