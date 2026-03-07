module Plat.Core.Types
  ( -- * Declaration kinds
    DeclKind (..)

    -- * Architecture
  , Architecture (..)
  , LayerDef (..)
  , TypeAlias (..)

    -- * Declaration (AST node, untagged)
  , Declaration (..)

    -- * Declaration (phantom-tagged, eDSL surface)
  , Decl (..)
  , decl

    -- * Declaration items
  , DeclItem (..)
  , Param (..)

    -- * Type expressions
  , TypeExpr (..)
  , Builtin (..)

    -- * Helpers
  , findImplements
  , declFields
  , declOps
  , declNeeds
  , lookupMeta
  ) where

import Data.Text (Text)

-- | 宣言の種類（DataKinds で型レベルに昇格）
data DeclKind
  = Model
  | Boundary
  | Operation
  | Adapter
  | Compose
  deriving stock (Show, Eq, Ord)

-- | アーキテクチャ全体
data Architecture = Architecture
  { archName        :: Text
  , archLayers      :: [LayerDef]
  , archTypes       :: [TypeAlias]
  , archCustomTypes :: [Text]
  , archDecls       :: [Declaration]
  , archMeta        :: [(Text, Text)]
  } deriving stock (Show, Eq)

-- | レイヤー定義
data LayerDef = LayerDef
  { layerName :: Text
  , layerDeps :: [Text]
  } deriving stock (Show, Eq)

-- | 型エイリアス
data TypeAlias = TypeAlias
  { aliasName :: Text
  , aliasType :: TypeExpr
  } deriving stock (Show, Eq)

-- | 宣言（AST ノード、均質な値）
data Declaration = Declaration
  { declKind  :: DeclKind
  , declName  :: Text
  , declLayer :: Maybe Text
  , declPaths :: [FilePath]
  , declBody  :: [DeclItem]
  , declMeta  :: [(Text, Text)]
  } deriving stock (Show, Eq)

-- | phantom-tagged 宣言（eDSL 構築時の型安全性）
newtype Decl (k :: DeclKind) = Decl { unDecl :: Declaration }
  deriving stock (Show, Eq)

-- | phantom tag の消去
decl :: Decl k -> Declaration
decl = unDecl

-- | 宣言内の構造要素
data DeclItem
  = Field      Text TypeExpr
  | Op         Text [Param] [Param]
  | Input      Text TypeExpr
  | Output     Text TypeExpr
  | Needs      Text
  | Implements Text
  | Inject     Text TypeExpr
  | Bind       Text Text
  | Entry      Text
  deriving stock (Show, Eq)

-- | 名前付きパラメータ
data Param = Param
  { paramName :: Text
  , paramType :: TypeExpr
  } deriving stock (Show, Eq)

-- | 型式
data TypeExpr
  = TBuiltin  Builtin
  | TRef      Text
  | TGeneric  Text [TypeExpr]
  | TNullable TypeExpr
  deriving stock (Show, Eq, Ord)

-- | ビルトイン型
data Builtin
  = BString | BInt | BFloat | BDecimal
  | BBool | BUnit | BBytes | BDateTime
  | BAny
  deriving stock (Show, Eq, Ord, Enum, Bounded)

-- Helpers

-- | DeclItem リストから Implements を探す（最大 1 つ）
findImplements :: [DeclItem] -> Maybe Text
findImplements items =
  case [name | Implements name <- items] of
    []    -> Nothing
    names -> Just (last names)  -- last-write-wins

-- | Field 項目を抽出
declFields :: Declaration -> [(Text, TypeExpr)]
declFields d = [(n, t) | Field n t <- declBody d]

-- | Op 項目を抽出
declOps :: Declaration -> [(Text, [Param], [Param])]
declOps d = [(n, i, o) | Op n i o <- declBody d]

-- | Needs 項目を抽出
declNeeds :: Declaration -> [Text]
declNeeds d = [n | Needs n <- declBody d]

-- | メタデータの検索
lookupMeta :: Text -> Declaration -> Maybe Text
lookupMeta key d = lookup key (declMeta d)
