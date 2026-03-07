-- | Plat Core eDSL — 公開 API の再エクスポート
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
import Plat.Core.TypeExpr
import Plat.Core.Meta
