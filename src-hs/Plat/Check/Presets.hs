-- | よく使われるアーキテクチャ制約のプリセット。
--
-- 'Plat.Core.Builder.constrain' で直接使えるレベルの検査関数を提供する。
--
-- @
-- constrain "adapter-coverage" "all adapters must implement" operationNeedsBoundary
-- constrain "no-unwired"       "all boundaries must be wired" unwiredBoundaries
-- constrain "no-cycle"         "no circular needs"            noNeedsCycle
-- @
module Plat.Check.Presets
  ( operationNeedsBoundary
  , unwiredBoundaries
  , noNeedsCycle
  ) where

import Data.Text (Text)
import qualified Data.Set as Set

import Plat.Core.Types
import Plat.Core.Relation (isAcyclic)

-- | 全 adapter が boundary を implements していることを要求する。
operationNeedsBoundary :: Architecture -> [Text]
operationNeedsBoundary a =
  [ declName d <> ": adapter has no implements"
  | d <- archDecls a
  , declKind d == Adapter
  , Nothing == findImplements (declBody d)
  ]

-- | 全 boundary に bind された adapter が存在することを要求する。
unwiredBoundaries :: Architecture -> [Text]
unwiredBoundaries a =
  [ declName d <> ": boundary has no binding in any compose"
  | d <- archDecls a
  , declKind d == Boundary
  , declName d `Set.notMember` wiredBoundaries
  ]
  where
    wiredBoundaries = Set.fromList
      [ bnd | dd <- archDecls a, Bind bnd _ <- declBody dd ]

-- | needs 関係にサイクルがないことを要求する。
noNeedsCycle :: Architecture -> [Text]
noNeedsCycle a
  | isAcyclic ["needs"] a = []
  | otherwise = ["needs dependency graph contains a cycle"]
