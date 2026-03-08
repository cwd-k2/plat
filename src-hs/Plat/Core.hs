-- | Plat Core eDSL — アーキテクチャ記述の公開 API。
--
-- このモジュールをインポートすれば、レイヤー定義・型式・宣言構築・メタ DSL の
-- すべてが利用可能になる。通常はこのモジュールのみをインポートする。
--
-- @
-- import Plat.Core
--
-- order :: Decl 'Model
-- order = model "Order" enterprise $ do
--   field "id"    string
--   field "total" (ref money)
-- @
module Plat.Core
  ( -- * レイヤー定義
    LayerDef (..)
  , layer
  , depends

    -- * 型式
  , TypeExpr (..)
  , Builtin (..)
  , Param (..)
  , (.:)
    -- ** プリミティブ型
  , string, int, float, decimal, bool
  , unit, bytes, dateTime, any_
    -- ** 型コンストラクタ
  , list, option, set, map_, stream, nullable, result
    -- ** 参照
  , ref, idOf, alias, Referenceable
  , ext, customType, error_
    -- ** 型エイリアス
  , TypeAlias (..), (=:)
    -- ** レンダリング
  , renderTypeExpr

    -- * 宣言
  , DeclKind (..)
  , Decl (..), decl
  , Declaration (..)
  , DeclItem (..)
    -- ** 宣言コンストラクタ
  , model, boundary, operation, adapter, compose
    -- ** Model コンビネータ
  , field
    -- ** Boundary コンビネータ
  , op
    -- ** Operation コンビネータ
  , input, output, needs
    -- ** Adapter コンビネータ
  , implements, inject
    -- ** Compose コンビネータ
  , bind, entry
    -- ** 汎用コンビネータ
  , DeclWriter, HasPath
  , path, meta

    -- * アーキテクチャ
  , Architecture (..)
  , ArchBuilder
  , arch
  , useLayers, useTypes, registerType
  , declare, declares
  , constrain, relate

    -- * 制約
  , ArchConstraint (..)
  , require, forbid, forAll, holds
  , oneOf, neg
  , operationNeedsBoundary, unwiredBoundaries, noNeedsCycle

    -- * 関係グラフ
  , Relation (..)
  , relations, relationsOf
  , dependsOn, implementedBy, boundTo
  , transitive, reachable
  , isAcyclic, cyclicGroups
  , forwardImpact, reverseImpact
  , typeRefs

    -- * 代数
  , merge, mergeAll
  , Conflict (..), isCompatible
  , project, projectLayer, projectKind
  , ArchDiff (..), DeclChange (..), diff

    -- * メタ DSL
  , ExtId, MetaTag
  , extId, kind
  , tagAs, isTagged
  , attr, lookupAttr
  , annotate, annotations
  , refer, references

    -- * 宣言クエリ
  , findImplements, declFields, declOps, declNeeds, lookupMeta
  ) where

import Plat.Core.Types
import Plat.Core.Builder
import Plat.Core.Constraint
import Plat.Core.Relation
import Plat.Core.Algebra
import Plat.Core.TypeExpr
import Plat.Core.Meta
import Plat.Check.Presets
