# AST

plat の抽象構文木を構成する型の定義。すべて `Plat.Core.Types` で定義される。

## DeclKind

宣言の種類。値レベルと DataKinds による型レベルの双方で使用される。

```haskell
data DeclKind = Model | Boundary | Operation | Adapter | Compose
```

| Kind | 用途 | 主要な DeclItem |
|------|------|-----------------|
| Model | データ構造の定義 | Field |
| Boundary | ポート/インターフェース | Op |
| Operation | ユースケース | Input, Output, Needs |
| Adapter | 外部実装 | Implements, Inject |
| Compose | 配線 | Bind, Entry |

## Declaration

均質な AST ノード。検証・生成はすべてこのレベルで動作する。

```haskell
data Declaration = Declaration
  { declKind  :: DeclKind
  , declName  :: Text
  , declLayer :: Maybe Text      -- Compose は Nothing
  , declPaths :: [FilePath]
  , declBody  :: [DeclItem]
  , declMeta  :: [(Text, Text)]  -- 拡張メタデータ（挿入順序保持）
  }
```

## Decl k

phantom-tagged newtype。構築時の型安全性を担う。

```haskell
newtype Decl (k :: DeclKind) = Decl { unDecl :: Declaration }

-- phantom tag の消去（逆方向は存在しない）
decl :: Decl k -> Declaration
decl = unDecl
```

## DeclItem

宣言内の構造要素。**閉じた型** — 拡張は `meta` タグで実現し、新しいコンストラクタは追加しない。

```haskell
data DeclItem
  = Field      Text TypeExpr            -- model: フィールド
  | Op         Text [Param] [Param]     -- boundary: 操作シグネチャ (名前, 入力, 出力)
  | Input      Text TypeExpr            -- operation: 入力パラメータ
  | Output     Text TypeExpr            -- operation: 出力パラメータ
  | Needs      Text                     -- operation: 依存 boundary 名
  | Implements Text                     -- adapter: 実装対象 boundary 名 (最大 1)
  | Inject     Text TypeExpr            -- adapter: DI 注入
  | Bind       Text Text                -- compose: boundary → adapter の束縛
  | Entry      Text                     -- compose: エントリポイント
```

### DeclKind x DeclItem 許容マトリクス

`DeclWriter k` の phantom type によりコンパイル時に強制される。

|            | Field | Op | Input | Output | Needs | Implements | Inject | Bind | Entry |
|------------|:-----:|:--:|:-----:|:------:|:-----:|:----------:|:------:|:----:|:-----:|
| Model      |   o   |    |       |        |       |            |        |      |       |
| Boundary   |       | o  |       |        |       |            |        |      |       |
| Operation  |       |    |   o   |   o    |   o   |            |        |      |       |
| Adapter    |       |    |       |        |       |     o      |   o    |      |       |
| Compose    |       |    |       |        |       |            |        |  o   |   o   |

`path` は Compose 以外で使用可能（`HasPath` 制約）。`meta` は全 DeclKind で使用可能。

## TypeExpr

型式。宣言のフィールドやパラメータの型を表現する。

```haskell
data TypeExpr
  = TBuiltin  Builtin          -- ビルトイン型
  | TRef      Text             -- 他の宣言・型エイリアスへの参照
  | TGeneric  Text [TypeExpr]  -- ジェネリック型
  | TNullable TypeExpr         -- nullable 修飾
  | TExt      Text             -- 外部型（ターゲット言語固有、W002 検証対象外）

data Builtin
  = BString | BInt | BFloat | BDecimal
  | BBool | BUnit | BBytes | BDateTime | BAny
```

**`TExt` と `TRef` の区別**: `ext` は `TExt` を生成し、`ref`/`customType` は `TRef` を生成する。`TExt` は W002 (未定義型参照) の検証対象外であり、`typeRefs` 関数でも無視される。これにより外部型（`*sql.DB` 等）とプロジェクト内の型参照を AST レベルで明確に区別できる。

## Param

名前付きパラメータ。Op の入出力に使用。

```haskell
data Param = Param { paramName :: Text, paramType :: TypeExpr }

-- 中置コンストラクタ
(.:) :: Text -> TypeExpr -> Param
```

## Architecture

アーキテクチャ全体を表すトップレベルの型。

```haskell
data Architecture = Architecture
  { archName        :: Text
  , archLayers      :: [LayerDef]
  , archTypes       :: [TypeAlias]
  , archCustomTypes :: [Text]           -- registerType で登録された型名
  , archDecls       :: [Declaration]
  , archConstraints :: [ArchConstraint]
  , archRelations   :: [Relation]       -- 明示的関係 (relate で登録)
  , archMeta        :: [(Text, Text)]
  }
```

## LayerDef

レイヤー定義。

```haskell
data LayerDef = LayerDef
  { layerName :: Text
  , layerDeps :: [Text]    -- 依存先レイヤー名
  }
```

## TypeAlias

型エイリアス。

```haskell
data TypeAlias = TypeAlias
  { aliasName :: Text
  , aliasType :: TypeExpr
  }
```

## ArchConstraint

アーキテクチャレベルの制約。関数フィールドを含むため Show/Eq は `acName` ベースの手動実装。

```haskell
data ArchConstraint = ArchConstraint
  { acName  :: Text
  , acDesc  :: Text
  , acCheck :: Architecture -> [Text]
  }
```

## Relation

宣言間の有向関係。

```haskell
data Relation = Relation
  { relKind   :: Text
  , relSource :: Text
  , relTarget :: Text
  , relMeta   :: [(Text, Text)]
  }
```
