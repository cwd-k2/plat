-- | Plat Core eDSL — アーキテクチャ記述の公開 API。
--
-- このモジュールをインポートすれば、レイヤー定義・型式・宣言構築・メタDSL の
-- すべてが利用可能になる。通常はこのモジュールのみをインポートする。
--
-- @
-- import Plat.Core
--
-- enterprise, interface :: LayerDef
-- enterprise = layer "enterprise"
-- interface  = layer "interface" \`depends\` [enterprise]
--
-- order :: Decl 'Model
-- order = model "Order" enterprise $ do
--   field "id"    string
--   field "total" int
-- @
module Plat.Core
  ( -- * Types (AST)
    DeclKind (..)
  , Architecture (..)
  , LayerDef (..)
  , TypeAlias (..)
  , Declaration (..)
  , Decl (..)
  , decl
  , DeclItem (..)
  , Param (..)
  , TypeExpr (..)
  , Builtin (..)

    -- * Helpers
  , findImplements
  , declFields
  , declOps
  , declNeeds
  , lookupMeta

    -- * Layer constructors
  , layer
  , depends

    -- * Type alias
  , (=:)

    -- * Declaration constructors
  , model
  , boundary
  , operation
  , adapter
  , compose

    -- * DeclWriter monad and combinators
  , DeclWriter
  , HasPath
  , field
  , op
  , op'
  , input
  , output
  , needs
  , implements
  , inject
  , bind
  , entry
  , entryName
  , path
  , meta

    -- * ArchBuilder monad
  , ArchBuilder
  , arch
  , useLayers
  , useTypes
  , registerType
  , declare
  , declares
  , constrain

    -- * Constraint combinators
  , ArchConstraint (..)
  , require
  , forbid
  , forAll
  , holds

    -- * Relations
  , Relation (..)
  , relate
  , relations
  , relationsOf
  , dependsOn
  , implementedBy
  , boundTo
  , transitive
  , reachable
  , isAcyclic
  , typeRefs

    -- * Meta DSL
  , ExtId
  , MetaTag
  , extId
  , kind
  , tagAs
  , isTagged
  , attr
  , lookupAttr
  , annotate
  , annotations
  , refer
  , references

    -- * Type expressions
  , string
  , int
  , float
  , decimal
  , bool
  , unit
  , bytes
  , dateTime
  , any_
  , result
  , option
  , list
  , set
  , mapType
  , stream
  , nullable
  , ref
  , idOf
  , alias
  , Referenceable
  , ext
  , customType
  , error_
  , (.:)
  , renderTypeExpr
  ) where

import Plat.Core.Types
import Plat.Core.Builder
import Plat.Core.Constraint
import Plat.Core.Relation
import Plat.Core.TypeExpr
import Plat.Core.Meta
