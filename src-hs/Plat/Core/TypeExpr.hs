-- | 型式 DSL。アーキテクチャ宣言内で型を記述するためのスマートコンストラクタを提供する。
--
-- 組み込み型 ('string', 'int' 等) とジェネリック型コンストラクタ ('list', 'option' 等) を
-- 組み合わせて 'TypeExpr' を構築する。型コンストラクタは @TypeExpr -> TypeExpr@ の
-- 自己準同型であり、'ref' による持ち上げと自由に合成できる:
--
-- @
-- field "items" (list (ref orderItem))   -- list . ref
-- field "cache" (map_ string (option (ref user)))
-- @
module Plat.Core.TypeExpr
  ( -- * プリミティブ型
    string
  , int
  , float
  , decimal
  , bool
  , unit
  , bytes
  , dateTime
  , any_

    -- * 型コンストラクタ
  , result
  , option
  , list
  , set
  , map_
  , stream
  , nullable

    -- * 参照
  , ref
  , idOf
  , alias
  , Referenceable

    -- * 外部型 / カスタム型
  , ext
  , customType

    -- * 予約型
  , error_

    -- * パラメータ構築
  , (.:)

    -- * レンダリング
  , renderTypeExpr
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import Plat.Core.Types

----------------------------------------------------------------------
-- プリミティブ型
----------------------------------------------------------------------

-- | 文字列型。ターゲット言語では @string@ / @String@ 等に変換される。
string,
-- | 整数型。ターゲット言語では @int@ / @i64@ 等に変換される。
  int,
-- | 浮動小数点数型。ターゲット言語では @float64@ / @f64@ 等に変換される。
  float,
-- | 固定精度小数型。金額計算など精度が必要な場面で使用する。
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

----------------------------------------------------------------------
-- 型コンストラクタ
--
-- 全て TypeExpr -> TypeExpr（または TypeExpr -> TypeExpr -> TypeExpr）の
-- 自己準同型。ref による持ち上げと自由に合成できる。
----------------------------------------------------------------------

-- | 成功型と失敗型を持つ結果型。Go では多値戻り値、Rust では @Result\<T, E\>@ に変換される。
--
-- @
-- op "save" ["order" .: ref order] ["id" .: result string error_]
-- @
result :: TypeExpr -> TypeExpr -> TypeExpr
result t e = TGeneric "Result" [t, e]

-- | 省略可能な値の型。Go では @*T@、Rust では @Option\<T\>@、TS では @T | undefined@ 等。
option :: TypeExpr -> TypeExpr
option t = TGeneric "Option" [t]

-- | リスト（可変長配列）型。
--
-- @
-- field "items" (list (ref orderItem))
-- @
list :: TypeExpr -> TypeExpr
list t = TGeneric "List" [t]

-- | 集合型。要素の一意性を保証する。
set :: TypeExpr -> TypeExpr
set t = TGeneric "Set" [t]

-- | キーと値のマップ型。@Prelude.map@ との衝突を避けるため @_@ suffix。
--
-- @
-- field "headers" (map_ string string)
-- @
map_ :: TypeExpr -> TypeExpr -> TypeExpr
map_ k v = TGeneric "Map" [k, v]

-- | ストリーム（非同期シーケンス）型。
stream :: TypeExpr -> TypeExpr
stream t = TGeneric "Stream" [t]

-- | null 許容型。'option' とは異なり、ターゲット言語の nullable 表現に直接対応する。
nullable :: TypeExpr -> TypeExpr
nullable = TNullable

----------------------------------------------------------------------
-- 参照
--
-- ref は Decl k を TypeExpr に持ち上げる唯一の関数。
-- 型コンストラクタとの合成で任意のジェネリック参照を表現する:
--   list (ref x), option (ref x), set (ref x), ...
----------------------------------------------------------------------

-- | 'Decl' を型参照に持ち上げる。eDSL 内で最も頻繁に使用される関数。
--
-- @
-- field "status" (ref orderStatus)   -- 単純参照
-- field "items"  (list (ref item))   -- コンストラクタとの合成
-- @
ref :: Referenceable k => Decl k -> TypeExpr
ref (Decl d) = TRef (declName d)

-- | 型参照を生成できる宣言種の制約。'Model', 'Boundary', 'Operation' で有効。
class Referenceable (k :: DeclKind)
instance Referenceable 'Model
instance Referenceable 'Boundary
instance Referenceable 'Operation

-- | モデルの識別子型。@Id\<T\>@ として展開される。
idOf :: Decl 'Model -> TypeExpr
idOf (Decl d) = TGeneric "Id" [TRef (declName d)]

-- | 'TypeAlias' への型参照。
alias :: TypeAlias -> TypeExpr
alias ta = TRef (aliasName ta)

----------------------------------------------------------------------
-- 外部型 / カスタム型
----------------------------------------------------------------------

-- | ターゲット言語固有の外部型。W002（未定義型）検証から除外される。
--
-- @
-- inject "db" (ext "*sql.DB")      -- Go の外部型
-- inject "client" (ext "HttpClient") -- 言語固有の型名をそのまま記述
-- @
ext :: Text -> TypeExpr
ext = TExt

-- | プロジェクト定義のカスタム型。'registerType' で登録し、W002 検証対象になる。
--
-- @
-- registerType "UUID"  -- ArchBuilder 内で登録
-- field "id" (customType "UUID")  -- 宣言内で参照
-- @
customType :: Text -> TypeExpr
customType = TRef

----------------------------------------------------------------------
-- 予約型
----------------------------------------------------------------------

-- | Error 型。予約された型参照であり、W002 検証から免除される。
error_ :: TypeExpr
error_ = TRef "Error"

----------------------------------------------------------------------
-- パラメータ構築
----------------------------------------------------------------------

-- | パラメータを構築する中置演算子。境界の 'op' で使用する。
--
-- @
-- op "findById" ["id" .: customType "UUID"] ["order" .: ref order, "err" .: error_]
-- @
(.:) :: Text -> TypeExpr -> Param
name .: ty = Param name ty

infixl 7 .:

----------------------------------------------------------------------
-- レンダリング
----------------------------------------------------------------------

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
renderTypeExpr (TExt name) = name
