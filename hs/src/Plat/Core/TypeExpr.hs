module Plat.Core.TypeExpr
  ( -- * Builtin types
    string
  , int
  , float
  , decimal
  , bool
  , unit
  , bytes
  , dateTime
  , any_

    -- * Generic type constructors
  , result
  , option
  , list
  , set
  , mapType
  , stream
  , nullable

    -- * References
  , ref
  , idOf
  , alias
  , Referenceable

    -- * External / custom types
  , ext
  , customType

    -- * Reserved type references
  , error_

    -- * Param helper
  , (.:)
  ) where

import Data.Text (Text)

import Plat.Core.Types

-- Builtin types

string, int, float, decimal, bool, unit, bytes, dateTime, any_ :: TypeExpr
string   = TBuiltin BString
int      = TBuiltin BInt
float    = TBuiltin BFloat
decimal  = TBuiltin BDecimal
bool     = TBuiltin BBool
unit     = TBuiltin BUnit
bytes    = TBuiltin BBytes
dateTime = TBuiltin BDateTime
any_     = TBuiltin BAny

-- Generic type constructors

result :: TypeExpr -> TypeExpr -> TypeExpr
result t e = TGeneric "Result" [t, e]

option :: TypeExpr -> TypeExpr
option t = TGeneric "Option" [t]

list :: TypeExpr -> TypeExpr
list t = TGeneric "List" [t]

set :: TypeExpr -> TypeExpr
set t = TGeneric "Set" [t]

mapType :: TypeExpr -> TypeExpr -> TypeExpr
mapType k v = TGeneric "Map" [k, v]

stream :: TypeExpr -> TypeExpr
stream t = TGeneric "Stream" [t]

nullable :: TypeExpr -> TypeExpr
nullable = TNullable

-- References

-- | 型参照を生成できる宣言種の制約
class Referenceable (k :: DeclKind)
instance Referenceable 'Model
instance Referenceable 'Boundary
instance Referenceable 'Operation

-- | 宣言への型参照
ref :: Referenceable k => Decl k -> TypeExpr
ref (Decl d) = TRef (declName d)

-- | model の Id 型
idOf :: Decl 'Model -> TypeExpr
idOf (Decl d) = TGeneric "Id" [TRef (declName d)]

-- | TypeAlias への型参照
alias :: TypeAlias -> TypeExpr
alias ta = TRef (aliasName ta)

-- External / custom types

-- | ターゲット言語固有の外部型（W002 検証対象外）
ext :: Text -> TypeExpr
ext = TRef

-- | プロジェクト定義のカスタム型（registerType で登録、W002 検証対象）
customType :: Text -> TypeExpr
customType = TRef

-- Reserved type references

-- | Error 型（予約型参照、W002 免除）
error_ :: TypeExpr
error_ = TRef "Error"

-- Param helper

-- | パラメータ構築の中置演算子
(.:) :: Text -> TypeExpr -> Param
name .: ty = Param name ty

infixl 7 .:
