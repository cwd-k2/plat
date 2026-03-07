-- | plat の中核 AST 型。
--
-- 設計の要点:
--
-- * @'Decl' k@ — phantom-tagged。eDSL 構築時にコンビネータの誤用をコンパイル時に検出する
-- * 'Declaration' — untagged。検証・生成パイプラインはすべてこの均質な型で動作する
-- * @'decl' :: Decl k -> Declaration@ で消去。逆方向は存在しない
module Plat.Core.Types
  ( -- * Declaration kinds
    DeclKind (..)

    -- * Architecture
  , Architecture (..)
  , LayerDef (..)
  , TypeAlias (..)

    -- * Constraints
  , ArchConstraint (..)

    -- * Relations
  , Relation (..)

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

-- | アーキテクチャ制約。'Plat.Core.Builder.constrain' で宣言する。
--
-- 検査関数は違反メッセージのリストを返す。空リストなら制約を満たす。
-- 'Plat.Check.check' が自動的に評価し、違反を @Error@ として報告する。
data ArchConstraint = ArchConstraint
  { acName  :: Text                    -- ^ 制約名（一意であること）
  , acDesc  :: Text                    -- ^ 人間向けの説明
  , acCheck :: Architecture -> [Text]  -- ^ 検査関数（違反メッセージを返す）
  }

instance Show ArchConstraint where
  show ac = "ArchConstraint " ++ show (acName ac)

instance Eq ArchConstraint where
  a == b = acName a == acName b

-- | 宣言間の関係。DeclItem の暗黙的関係を補完する明示的な関係。
--
-- 'Plat.Core.Builder.relate' で宣言する。'Plat.Core.Relation.relations' で
-- DeclItem 由来の暗黙的関係と統合してクエリできる。
data Relation = Relation
  { relKind   :: Text            -- ^ 関係の種類（例: @"uses"@, @"publishes"@）
  , relSource :: Text            -- ^ 関係元の宣言名
  , relTarget :: Text            -- ^ 関係先の宣言名
  , relMeta   :: [(Text, Text)]  -- ^ 関係メタデータ
  } deriving stock (Show, Eq)

-- | アーキテクチャ全体。'Plat.Core.Builder.arch' で構築される。
data Architecture = Architecture
  { archName        :: Text              -- ^ アーキテクチャ名（例: @"order-service"@）
  , archLayers      :: [LayerDef]        -- ^ レイヤー定義（依存方向順）
  , archTypes       :: [TypeAlias]       -- ^ 型エイリアス
  , archCustomTypes :: [Text]            -- ^ 'registerType' で登録されたカスタム型名
  , archDecls       :: [Declaration]     -- ^ 全宣言
  , archConstraints :: [ArchConstraint]  -- ^ アーキテクチャ制約
  , archRelations   :: [Relation]        -- ^ 明示的な宣言間関係
  , archMeta        :: [(Text, Text)]    -- ^ アーキテクチャレベルのメタデータ
  } deriving stock (Show, Eq)

-- | レイヤー定義。'Plat.Core.Builder.layer' と 'Plat.Core.Builder.depends' で構築される。
data LayerDef = LayerDef
  { layerName :: Text    -- ^ レイヤー名
  , layerDeps :: [Text]  -- ^ このレイヤーが依存可能なレイヤー名のリスト
  } deriving stock (Show, Eq)

-- | 型エイリアス。'Plat.Core.Builder.=:' で構築される。
data TypeAlias = TypeAlias
  { aliasName :: Text      -- ^ エイリアス名
  , aliasType :: TypeExpr  -- ^ 展開先の型式
  } deriving stock (Show, Eq)

-- | 宣言（AST ノード、均質な値）。検証・生成はすべてこの型で動作する。
data Declaration = Declaration
  { declKind  :: DeclKind        -- ^ 宣言種
  , declName  :: Text            -- ^ 宣言名（一意であること）
  , declLayer :: Maybe Text      -- ^ 所属レイヤー（'Compose' は 'Nothing'）
  , declPaths :: [FilePath]      -- ^ 対応するソースファイルパス
  , declBody  :: [DeclItem]      -- ^ 構造要素（フィールド、オペレーション等）
  , declMeta  :: [(Text, Text)]  -- ^ メタデータ（拡張用）
  } deriving stock (Show, Eq)

-- | phantom-tagged 宣言（eDSL 構築時の型安全性）
newtype Decl (k :: DeclKind) = Decl { unDecl :: Declaration }
  deriving stock (Show, Eq)

-- | phantom tag の消去
decl :: Decl k -> Declaration
decl = unDecl

-- | 宣言内の構造要素。閉じた直和型であり、新しいコンストラクタは追加しない。
-- 拡張は 'declMeta' で行う。
data DeclItem
  = Field      Text TypeExpr      -- ^ モデルのフィールド（名前, 型）
  | Op         Text [Param] [Param]  -- ^ 境界のオペレーション（名前, 入力, 出力）
  | Input      Text TypeExpr      -- ^ オペレーションの入力（名前, 型）
  | Output     Text TypeExpr      -- ^ オペレーションの出力（名前, 型）
  | Needs      Text               -- ^ 依存する境界名
  | Implements Text               -- ^ 実装する境界名
  | Inject     Text TypeExpr      -- ^ 外部注入（名前, 型）。W002 検証から除外される
  | Bind       Text Text          -- ^ DI バインディング（境界名, アダプタ名）
  | Entry      Text               -- ^ エントリポイント（宣言名）
  deriving stock (Show, Eq)

-- | 名前付きパラメータ。'Plat.Core.TypeExpr..:' で簡潔に構築できる。
data Param = Param
  { paramName :: Text      -- ^ パラメータ名
  , paramType :: TypeExpr  -- ^ パラメータの型式
  } deriving stock (Show, Eq)

-- | 型式。言語非依存な型の AST。ターゲット言語ごとに具象型へ変換される。
data TypeExpr
  = TBuiltin  Builtin          -- ^ ビルトイン型（@string@, @int@ 等）
  | TRef      Text             -- ^ 他の宣言・型エイリアスへの参照
  | TGeneric  Text [TypeExpr]  -- ^ ジェネリック型（@List\<T\>@, @Result\<T, E\>@ 等）
  | TNullable TypeExpr         -- ^ nullable 修飾（@T?@）
  deriving stock (Show, Eq, Ord)

-- | ビルトイン型。言語非依存なプリミティブ。ターゲット言語の型マッピングで具象化される。
data Builtin
  = BString    -- ^ 文字列
  | BInt       -- ^ 整数
  | BFloat     -- ^ 浮動小数点
  | BDecimal   -- ^ 固定精度小数
  | BBool      -- ^ 真偽値
  | BUnit      -- ^ 単位型（void / unit）
  | BBytes     -- ^ バイト列
  | BDateTime  -- ^ 日時
  | BAny       -- ^ 任意の型（型消去）
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
