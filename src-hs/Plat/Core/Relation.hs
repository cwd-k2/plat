-- | 宣言間関係のクエリと走査。
--
-- DeclItem 由来の暗黙的関係と 'Plat.Core.Builder.relate' による明示的関係を
-- 統合して 'Relation' のリストとして提供する。グラフ走査のプリミティブも含む。
module Plat.Core.Relation
  ( -- * Unified extraction
    relations
  , relationsOf

    -- * Focused queries
  , dependsOn
  , implementedBy
  , boundTo

    -- * Graph traversal
  , transitive
  , reachable
  , isAcyclic

    -- * TypeExpr helpers
  , typeRefs
  ) where

import Data.Text (Text)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import Plat.Core.Types

-- | アーキテクチャ内の全関係を抽出する。
--
-- DeclItem 由来の暗黙的関係:
--
-- * @"needs"@ — Operation が Boundary に依存
-- * @"implements"@ — Adapter が Boundary を実装
-- * @"bind"@ — Compose が Boundary と Adapter を結合
-- * @"entry"@ — Compose のエントリポイント
-- * @"references"@ — フィールド型が他の宣言を参照
--
-- 加えて 'Plat.Core.Builder.relate' で登録された明示的関係。
relations :: Architecture -> [Relation]
relations a = implicit ++ archRelations a
  where
    implicit = concatMap declRelations (archDecls a)

-- | 単一宣言から暗黙的関係を抽出する。
declRelations :: Declaration -> [Relation]
declRelations d = concatMap (itemRelation (declName d)) (declBody d)

itemRelation :: Text -> DeclItem -> [Relation]
itemRelation src (Needs tgt)        = [Relation "needs" src tgt []]
itemRelation src (Implements tgt)   = [Relation "implements" src tgt []]
itemRelation src (Bind bnd adp)     = [Relation "bind" src bnd [("adapter", adp)]]
itemRelation src (Entry tgt)        = [Relation "entry" src tgt []]
itemRelation src (Field _ ty)       = [Relation "references" src t [] | t <- typeRefs ty]
itemRelation src (Input _ ty)       = [Relation "references" src t [] | t <- typeRefs ty]
itemRelation src (Output _ ty)      = [Relation "references" src t [] | t <- typeRefs ty]
itemRelation src (Inject _ ty)      = [Relation "references" src t [] | t <- typeRefs ty]
itemRelation _   (Op _ _ _)         = []  -- Op の中の Param は Boundary の内部構造

-- | 指定宣言を起点とする全関係。
relationsOf :: Text -> Architecture -> [Relation]
relationsOf name a = filter (\r -> relSource r == name) (relations a)

-- | 宣言が needs で依存する宣言名リスト。
dependsOn :: Text -> Architecture -> [Text]
dependsOn name a = [relTarget r | r <- relationsOf name a, relKind r == "needs"]

-- | 指定 Boundary を実装する Adapter 名リスト。
implementedBy :: Text -> Architecture -> [Text]
implementedBy name a =
  [relSource r | r <- relations a, relKind r == "implements", relTarget r == name]

-- | 指定 Boundary に bind されている Adapter 名リスト。
boundTo :: Text -> Architecture -> [Text]
boundTo name a =
  [ adp
  | r <- relations a
  , relKind r == "bind"
  , relTarget r == name
  , Just adp <- [lookup "adapter" (relMeta r)]
  ]

-- | 指定種類の関係に沿った推移閉包（起点自身は含まない）。
transitive :: [Text] -> Text -> Architecture -> Set.Set Text
transitive kinds start a = go Set.empty [start]
  where
    kindSet = Set.fromList kinds
    adjMap = Map.fromListWith (++)
      [ (relSource r, [relTarget r])
      | r <- relations a, relKind r `Set.member` kindSet
      ]
    go visited [] = visited
    go visited (x:xs)
      | x `Set.member` visited = go visited xs
      | otherwise = go (Set.insert x visited)
                       (Map.findWithDefault [] x adjMap ++ xs)

-- | 任意の関係に沿って到達可能な全宣言名（起点含む）。
reachable :: Text -> Architecture -> Set.Set Text
reachable start a = go Set.empty [start]
  where
    adjMap = Map.fromListWith (++)
      [ (relSource r, [relTarget r]) | r <- relations a ]
    go visited [] = visited
    go visited (x:xs)
      | x `Set.member` visited = go visited xs
      | otherwise = go (Set.insert x visited)
                       (Map.findWithDefault [] x adjMap ++ xs)

-- | 指定種類の関係がサイクルを含まないか検査する。
isAcyclic :: [Text] -> Architecture -> Bool
isAcyclic kinds a = all (\d -> declName d `Set.notMember` reach d) (archDecls a)
  where
    kindSet = Set.fromList kinds
    adjMap = Map.fromListWith (++)
      [ (relSource r, [relTarget r])
      | r <- relations a, relKind r `Set.member` kindSet
      ]
    reach d = go Set.empty (Map.findWithDefault [] (declName d) adjMap)
    go visited [] = visited
    go visited (x:xs)
      | x `Set.member` visited = go visited xs
      | otherwise = go (Set.insert x visited)
                       (Map.findWithDefault [] x adjMap ++ xs)

-- | TypeExpr から全 TRef 名を抽出する。
typeRefs :: TypeExpr -> [Text]
typeRefs (TBuiltin _)       = []
typeRefs (TRef name)        = [name]
typeRefs (TGeneric _ args)  = concatMap typeRefs args
typeRefs (TNullable t)      = typeRefs t
typeRefs (TExt _)           = []
