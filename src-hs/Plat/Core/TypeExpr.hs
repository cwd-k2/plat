-- | 型式 DSL。アーキテクチャ宣言内で型を記述するためのスマートコンストラクタを提供する。
--
-- 組み込み型 ('string', 'int' 等) とジェネリック型コンストラクタ ('list', 'option' 等) を
-- 組み合わせて 'TypeExpr' を構築する。構築された型式はターゲット言語に応じて変換される。
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

    -- * Rendering
  , renderTypeExpr
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import Plat.Core.Types

-- Builtin types

-- | 文字列型。ターゲット言語では @string@ / @String@ 等に変換される。
string,
-- | 整数型。ターゲット言語では @int@ / @i64@ 等に変換される。
  int,
-- | 浮動小数点数型。ターゲット言語では @float64@ / @number@ / @f64@ 等に変換される。
  float,
-- | 固定小数点数型。金額計算など精度が必要な場面で使用する。
  decimal,
-- | 真偽値型。
  bool,
-- | 空の値を表す型。戻り値のない操作に使用する。
  unit,
-- | バイト列型。
  bytes,
-- | 日時型。
  dateTime,
-- | 任意の型。型安全性を緩和する場面で使用する。
  any_
  :: TypeExpr
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

-- | 成功型と失敗型を持つ結果型。Go では多値戻り値、Rust では @Result\<T, E\>@ に変換される。
--
-- @
-- result (ref user) error_
-- @
result :: TypeExpr -> TypeExpr -> TypeExpr
result t e = TGeneric "Result" [t, e]

-- | 省略可能な値の型。Go では @*T@、Rust では @Option\<T\>@、TS では @T | undefined@ 等。
--
-- @
-- option string
-- @
option :: TypeExpr -> TypeExpr
option t = TGeneric "Option" [t]

-- | リスト（可変長配列）型。
--
-- @
-- list (ref user)
-- @
list :: TypeExpr -> TypeExpr
list t = TGeneric "List" [t]

-- | 集合型。要素の一意性を保証する。
set :: TypeExpr -> TypeExpr
set t = TGeneric "Set" [t]

-- | キーと値のマップ型。'Data.Map.Map' とは無関係。
--
-- @
-- mapType string (ref user)
-- @
mapType :: TypeExpr -> TypeExpr -> TypeExpr
mapType k v = TGeneric "Map" [k, v]

-- | ストリーム（非同期シーケンス）型。
stream :: TypeExpr -> TypeExpr
stream t = TGeneric "Stream" [t]

-- | null 許容型。'option' とは異なり、ターゲット言語の nullable 表現に直接対応する。
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

-- Rendering

-- | 'TypeExpr' を言語非依存のテキスト表現に変換する。デバッグや検証メッセージに使用。
renderTypeExpr :: TypeExpr -> Text
renderTypeExpr (TBuiltin b) = case b of
  BString   -> "String"
  BInt      -> "Int"
  BFloat    -> "Float"
  BDecimal  -> "Decimal"
  BBool     -> "Bool"
  BUnit     -> "Unit"
  BBytes    -> "Bytes"
  BDateTime -> "DateTime"
  BAny      -> "Any"
renderTypeExpr (TRef name) = name
renderTypeExpr (TGeneric name args) =
  name <> "<" <> T.intercalate ", " (map renderTypeExpr args) <> ">"
renderTypeExpr (TNullable t) = renderTypeExpr t <> "?"
