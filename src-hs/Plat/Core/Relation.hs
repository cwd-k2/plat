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
  , cyclicGroups

    -- * Impact analysis
  , forwardImpact
  , reverseImpact

    -- * TypeExpr helpers
  , typeRefs
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Graph (stronglyConnComp, SCC(..))

import Plat.Core.Types

-- | アーキテクチャ内の全関係を抽出する。
--
-- 三つのソースを統合する:
--
-- 1. DeclItem 由来の暗黙的関係:
--    * @"needs"@ — Operation が Boundary に依存
--    * @"implements"@ — Adapter が Boundary を実装
--    * @"bind"@ — Compose が Boundary と Adapter を結合
--    * @"entry"@ — Compose のエントリポイント
--    * @"references"@ — フィールド型が他の宣言を参照
--
-- 2. Meta 由来の拡張関係:
--    * @"emits"@ — Operation がイベントを発行 (Events: emit)
--    * @"subscribes"@ — Operation がイベントを購読 (Events: on_)
--    * @"applies"@ — Model がイベントを適用 (Events: apply)
--    * @"exposes"@ — Module が宣言を公開 (Modules: expose)
--    * @"imports"@ — Module が他モジュールから宣言を取り込む (Modules: import_)
--
-- 3. 'Plat.Core.Builder.relate' で登録された明示的関係。
relations :: Architecture -> [Relation]
relations a = implicit ++ archRelations a
  where
    implicit = concatMap declRelations (archDecls a)

-- | 単一宣言から暗黙的関係を抽出する。
--
-- DeclItem 由来の構造的関係に加え、declMeta に格納された
-- 拡張由来の関係も統合して抽出する。
declRelations :: Declaration -> [Relation]
declRelations d = itemRels ++ metaRels
  where
    src = declName d
    itemRels = concatMap (itemRelation src) (declBody d)
    metaRels = concatMap (metaRelation src) (declMeta d)

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

-- | Meta キーから拡張由来の関係を抽出する。
--
-- 対応するパターン:
--
-- * @plat-events:emit:{name}@  → @"emits"@
-- * @plat-events:on@           → @"subscribes"@
-- * @plat-events:apply:{name}@ → @"applies"@
-- * @plat-modules:expose:{name}@ → @"exposes"@
-- * @plat-modules:import:{name}@ → @"imports"@ (value = source module)
metaRelation :: Text -> (Text, Text) -> [Relation]
metaRelation src (key, val)
  | "plat-events:emit:" `T.isPrefixOf` key
  = [Relation "emits" src val []]
  | key == "plat-events:on"
  = [Relation "subscribes" src val []]
  | "plat-events:apply:" `T.isPrefixOf` key
  = [Relation "applies" src val []]
  | "plat-modules:expose:" `T.isPrefixOf` key
  = [Relation "exposes" src val []]
  | "plat-modules:import:" `T.isPrefixOf` key
  , let target = T.drop (T.length "plat-modules:import:") key
  = [Relation "imports" src target [("from-module", val)]]
  | otherwise = []

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
--
-- 内部で強連結成分分解 (Tarjan's SCC) を使用し O(V+E) で判定する。
isAcyclic :: [Text] -> Architecture -> Bool
isAcyclic kinds a = null (cyclicGroups kinds a)

-- | 指定種類の関係グラフに含まれるサイクル群を返す。
--
-- 各サイクルは強連結成分 (SCC) として報告される。
-- サイクルがなければ空リストを返す。O(V+E)。
cyclicGroups :: [Text] -> Architecture -> [[Text]]
cyclicGroups kinds a =
    [ ns | CyclicSCC ns <- stronglyConnComp graph ]
  where
    kindSet = Set.fromList kinds
    rels = [ (relSource r, relTarget r)
           | r <- relations a, relKind r `Set.member` kindSet
           ]
    allNodes = Set.toList $ Set.fromList
                 (map fst rels ++ map snd rels)
    adjMap = Map.fromListWith (++) [(s, [t]) | (s, t) <- rels]
    graph  = [ (n, n, Map.findWithDefault [] n adjMap)
             | n <- allNodes
             ]

-- | 指定宣言を変更した場合に影響を受ける宣言集合（起点は含まない）。
--
-- 全関係種について、指定宣言に依存する宣言を推移的に辿る。
forwardImpact :: Text -> Architecture -> Set.Set Text
forwardImpact start a = Set.delete start (go Set.empty [start])
  where
    -- 逆方向の隣接リスト: ターゲット → [ソース]
    revMap = Map.fromListWith (++)
      [ (relTarget r, [relSource r]) | r <- relations a ]
    go visited [] = visited
    go visited (x:xs)
      | x `Set.member` visited = go visited xs
      | otherwise = go (Set.insert x visited)
                       (Map.findWithDefault [] x revMap ++ xs)

-- | 指定宣言が依存する宣言集合（起点は含まない）。
--
-- 全関係種について、指定宣言から推移的に到達可能な宣言を辿る。
reverseImpact :: Text -> Architecture -> Set.Set Text
reverseImpact start a = Set.delete start (reachable start a)

-- | TypeExpr から全 TRef 名を抽出する。
typeRefs :: TypeExpr -> [Text]
typeRefs (TBuiltin _)       = []
typeRefs (TRef name)        = [name]
typeRefs (TGeneric _ args)  = concatMap typeRefs args
typeRefs (TNullable t)      = typeRefs t
typeRefs (TExt _)           = []
